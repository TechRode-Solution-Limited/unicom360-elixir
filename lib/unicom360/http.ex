defmodule Unicom360.HTTP do
  @moduledoc false
  # Sends one operation: builds the request, runs the attempts with the contract's retry rules
  # (docs/sdk-design.md section 10), interprets each response (section 7) and logs (section 13).

  require Logger

  alias Unicom360.{Client, Codes, Error, Model}
  alias Unicom360.WhatsApp.TemplateResult

  @type operation :: %{
          method: :get | :post,
          path: String.t(),
          kind: :envelope | :balance | :health,
          auth: boolean()
        }

  @type success :: {:ok, map(), String.t()}

  # How an attempt's failure may be retried: `:always` (429, nothing sent), `:if_safe` (sent,
  # 5xx, SEND_FAILED) or `:never`. A 429 is `:rate_limited`, which is always retried too.
  @typep retry_class :: :rate_limited | :always | :if_safe | :never
  @typep outcome :: success() | {:error, Error.t(), retry_class()}

  @request_options [:timeout, :max_retries]

  # Options the SDK owns; a caller's :req_options cannot replace them.
  @owned_req_options [
    :method,
    :url,
    :base_url,
    :body,
    :json,
    :form,
    :form_multipart,
    :params,
    :path_params,
    :auth,
    :retry,
    :redirect,
    :decode_body,
    :compressed,
    :user_agent,
    :receive_timeout,
    :plug,
    :into,
    :http_errors
  ]

  @owned_headers ["accept", "content-type", "x-api-key", "authorization", "user-agent"]

  @doc false
  @spec request(Client.t(), operation(), map() | nil, keyword(), keyword()) ::
          success() | {:error, Error.t()}
  def request(%Client{} = client, operation, body, opts, meta) do
    {timeout, max_retries} = request_options!(client, opts)

    state = %{
      client: client,
      operation: operation,
      req_options: req_options(client, operation, body, timeout),
      max_retries: max_retries,
      safe: Keyword.get(meta, :safe, false),
      generated: Keyword.get(meta, :generated, [])
    }

    run(state, 1)
  end

  @doc false
  @spec request_options!(Client.t(), keyword()) :: {pos_integer(), non_neg_integer()}
  def request_options!(client, opts) do
    check_request_keys!(opts)

    timeout = Keyword.get(opts, :timeout) || client.timeout
    max_retries = Keyword.get(opts, :max_retries) || client.max_retries

    if not (is_integer(timeout) and timeout > 0) do
      raise ArgumentError, "timeout must be a positive integer (ms), got: #{inspect(timeout)}"
    end

    if not (is_integer(max_retries) and max_retries >= 0) do
      raise ArgumentError,
            "max_retries must be a non-negative integer, got: #{inspect(max_retries)}"
    end

    {timeout, max_retries}
  end

  defp check_request_keys!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "request options must be a keyword list, got: #{inspect(opts)}"
    end

    case Enum.uniq(Keyword.keys(opts)) -- @request_options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown request options: #{inspect(unknown)}"
    end
  end

  defp req_options(client, operation, body, timeout) do
    user = client.req_options

    user_headers =
      user
      |> Keyword.get(:headers, [])
      |> Enum.reject(fn {name, _value} ->
        String.downcase(to_string(name)) in @owned_headers
      end)

    headers =
      [{"accept", "application/json"}] ++
        if(operation.auth, do: [{"x-api-key", client.api_key}], else: []) ++
        if(body, do: [{"content-type", "application/json"}], else: []) ++
        Enum.to_list(user_headers)

    options =
      user
      |> Keyword.drop([:headers | @owned_req_options])
      |> Keyword.merge(
        method: operation.method,
        url: client.base_url <> operation.path,
        headers: headers,
        retry: false,
        redirect: false,
        decode_body: false,
        compressed: false,
        user_agent: client.user_agent,
        receive_timeout: timeout
      )

    options =
      if body, do: Keyword.put(options, :body, Jason.encode_to_iodata!(body)), else: options

    cond do
      client.plug ->
        Keyword.put(options, :plug, client.plug)

      # Req refuses :finch together with :connect_options.
      Keyword.has_key?(options, :finch) ->
        options

      true ->
        connect = Keyword.get(options, :connect_options, [])

        Keyword.put(
          options,
          :connect_options,
          Keyword.put(connect, :timeout, client.connect_timeout)
        )
    end
  end

  defp run(state, attempt) do
    case attempt(state, attempt) do
      {:ok, _json, _text} = success ->
        success

      {:error, error, retry_class} ->
        retry_or_fail(state, %{error | attempts: attempt}, retry_class, attempt)
    end
  end

  defp retry_or_fail(state, error, retry_class, attempt) do
    with true <- retryable?(retry_class, state.safe) and attempt <= state.max_retries,
         {:wait, wait} <- wait(retry_class, error, attempt, state) do
      log_retry(state, error, attempt, wait)
      sleep(state.client, wait)
      run(state, attempt + 1)
    else
      _ -> {:error, error}
    end
  end

  defp retryable?(:rate_limited, _safe), do: true
  defp retryable?(:always, _safe), do: true
  defp retryable?(:if_safe, safe), do: safe
  defp retryable?(:never, _safe), do: false

  defp wait(:rate_limited, %Error{retry_after: base}, _attempt, state) do
    if base > state.client.max_retry_wait,
      do: :give_up,
      else: {:wait, max(1_000, base + trunc(random(state.client) * 1_000))}
  end

  defp wait(_class, _error, attempt, state) do
    cap = Enum.min([8_000, 500 * Integer.pow(2, min(attempt, 10)), state.client.max_retry_wait])
    {:wait, trunc(random(state.client) * cap)}
  end

  @spec attempt(map(), pos_integer()) :: outcome()
  defp attempt(state, attempt) do
    started = System.monotonic_time(:millisecond)
    response = Req.request(state.req_options)
    duration = System.monotonic_time(:millisecond) - started

    outcome =
      case response do
        {:ok, %Req.Response{status: status, headers: headers, body: body}} ->
          interpret(state.operation, status, headers, body_text(body), fn -> now(state.client) end)

        {:error, exception} ->
          transport_failure(exception)
      end

    log_attempt(state, attempt, duration, response, outcome)
    outcome
  end

  defp body_text(body) when is_binary(body), do: body
  defp body_text(nil), do: ""
  defp body_text(body), do: IO.iodata_to_binary(body)

  # ---------------------------------------------------------------------------------------
  # Section 7: interpreting a response
  # ---------------------------------------------------------------------------------------

  @doc false
  @spec interpret(operation(), integer(), map(), String.t(), (-> integer())) :: outcome()
  def interpret(operation, status, headers, text, _now) when status in 200..299 do
    json = decode(text)

    case success_flag(operation.kind, json) do
      true ->
        {:ok, json, text}

      false ->
        error = api_error(json, status, headers, text)
        {:error, error, if(error.code == "SEND_FAILED", do: :if_safe, else: :never)}

      _not_a_boolean ->
        {:error, not_an_envelope(status, headers, text), :never}
    end
  end

  def interpret(_operation, status, headers, text, now) do
    error = status_error(decode(text), status)
    error = %{error | http_status: status, headers: headers, raw_body: text}

    case status do
      429 ->
        {:error, %{error | retry_after: 60_000 - Integer.mod(now.(), 60_000)}, :rate_limited}

      status when status in 500..599 ->
        {:error, error, :if_safe}

      _other ->
        {:error, error, :never}
    end
  end

  defp success_flag(:health, json) when is_map(json), do: true
  defp success_flag(:balance, %{"status" => flag}), do: flag
  defp success_flag(:envelope, %{"success" => flag}), do: flag
  defp success_flag(_kind, _json), do: nil

  defp status_error(%{"message" => message} = json, status) do
    text = message_text(message)

    %Error{
      type: status_type(status),
      message: text || default_message(status),
      code: Codes.normalize(text),
      api_reference: Model.string_or_nil(json["api_reference"]),
      data: json["data"]
    }
  end

  defp status_error(%{"errors" => %{"detail" => detail}}, status) when is_binary(detail),
    do: %Error{type: status_type(status), message: detail, code: "UNKNOWN"}

  defp status_error(_json, status),
    do: %Error{type: status_type(status), message: default_message(status), code: "UNKNOWN"}

  defp api_error(json, status, headers, text) do
    message = message_text(json["message"])
    code = Codes.normalize(message)
    data = json["data"]

    error = %Error{
      type: :api_error,
      message: message || "the gateway refused the request",
      code: code,
      http_status: status,
      api_reference: Model.string_or_nil(json["api_reference"]),
      raw_body: text,
      data: data,
      headers: headers
    }

    case {code, data} do
      {"DUPLICATE_REFERENCE", %{"message_id" => id}} when is_binary(id) ->
        %{error | original_message_id: id}

      {"NO_VALID_RECIPIENTS", %{"results" => results}} when is_list(results) ->
        %{error | results: Enum.map(results, &TemplateResult.from_map/1)}

      _ ->
        error
    end
  end

  defp not_an_envelope(status, headers, text) do
    %Error{
      type: :api_status_error,
      message: "HTTP #{status} response is not a Unicom360 envelope",
      code: "UNKNOWN",
      http_status: status,
      headers: headers,
      raw_body: text
    }
  end

  defp status_type(400), do: :invalid_request_error
  defp status_type(401), do: :authentication_error
  defp status_type(429), do: :rate_limit_error
  defp status_type(status) when status in 500..599, do: :api_server_error
  defp status_type(_status), do: :api_status_error

  @doc false
  @spec message_text(term()) :: String.t() | nil
  def message_text(message) when is_binary(message), do: message

  def message_text(messages) when is_list(messages) do
    if Enum.all?(messages, &is_binary/1), do: Enum.join(messages, "; "), else: nil
  end

  def message_text(_message), do: nil

  @reasons %{
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See Other",
    304 => "Not Modified",
    307 => "Temporary Redirect",
    308 => "Permanent Redirect",
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable",
    408 => "Request Timeout",
    413 => "Content Too Large",
    415 => "Unsupported Media Type",
    422 => "Unprocessable Content",
    429 => "Too Many Requests",
    500 => "Internal Server Error",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Gateway Timeout"
  }

  defp default_message(status) do
    case Map.fetch(@reasons, status) do
      {:ok, reason} -> "HTTP #{status} #{reason}"
      :error -> "HTTP #{status}"
    end
  end

  defp decode(""), do: nil

  defp decode(text) do
    case Jason.decode(text) do
      {:ok, json} -> json
      {:error, _error} -> nil
    end
  end

  # ---------------------------------------------------------------------------------------
  # Section 3.4: transport failures
  # ---------------------------------------------------------------------------------------

  # Failures that happen before any byte of the request is written.
  @not_sent [
    :econnrefused,
    :nxdomain,
    :ehostunreach,
    :enetunreach,
    :ehostdown,
    :enetdown,
    :eaddrnotavail,
    :protocol_not_negotiated
  ]

  @doc false
  @spec transport_failure(Exception.t()) :: outcome()
  def transport_failure(exception) do
    {sent, timeout} = facts(exception)

    error = %Error{
      type: if(timeout, do: :timeout_error, else: :connection_error),
      message: "request failed: " <> Exception.message(exception),
      cause: exception
    }

    {:error, error, if(sent, do: :if_safe, else: :always)}
  end

  defp facts(%Unicom360.TransportError{sent: sent, timeout: timeout}), do: {sent, timeout}
  defp facts(%{__exception__: true, reason: reason}), do: reason_facts(reason)
  defp facts(_exception), do: {true, false}

  # When the library cannot say whether bytes were sent, they may have been (`sent: true`).
  defp reason_facts(:timeout), do: {true, true}
  defp reason_facts(:closed), do: {true, false}
  defp reason_facts(reason) when reason in @not_sent, do: {false, false}
  defp reason_facts({:tls_alert, _alert}), do: {false, false}
  defp reason_facts({:bad_alpn_protocol, _protocol}), do: {false, false}
  defp reason_facts({:options, _option}), do: {false, false}
  defp reason_facts(_reason), do: {true, false}

  # ---------------------------------------------------------------------------------------
  # Section 13: logging. Never a body, a header, a parameter, a number or an address.
  # ---------------------------------------------------------------------------------------

  defp log_attempt(state, attempt, duration, response, outcome) do
    status =
      case response do
        {:ok, %Req.Response{status: status}} -> "status=#{status}"
        {:error, exception} -> "transport_error=#{inspect(transport_reason(exception))}"
      end

    reference = reference(outcome)
    generated = state.generated

    metadata =
      [
        method: method(state),
        path: state.operation.path,
        status: status_value(response),
        api_reference: reference,
        attempt: attempt,
        duration_ms: duration
      ] ++ if(generated == [], do: [], else: [generated_user_reference_ids: generated])

    Logger.debug(
      fn ->
        "unicom360 #{method(state)} #{state.operation.path} #{status}" <>
          if(reference, do: " api_reference=#{reference}", else: "") <>
          " attempt=#{attempt} duration_ms=#{duration}" <>
          if(generated == [],
            do: "",
            else: " generated_user_reference_ids=#{Enum.join(generated, ",")}"
          )
      end,
      metadata
    )
  end

  defp log_retry(state, error, attempt, wait) do
    Logger.info(
      fn ->
        "unicom360 retrying #{method(state)} #{state.operation.path} after attempt=#{attempt} " <>
          "wait_ms=#{wait} cause=#{cause(error)}"
      end,
      attempt: attempt,
      wait_ms: wait,
      cause: cause(error)
    )
  end

  defp status_value({:ok, %Req.Response{status: status}}), do: status
  defp status_value({:error, exception}), do: transport_reason(exception)

  defp transport_reason(%{__exception__: true, reason: reason}), do: reason
  defp transport_reason(exception), do: exception.__struct__

  defp reference({:ok, json, _text}), do: Model.string_or_nil(json["api_reference"])
  defp reference({:error, %Error{api_reference: reference}, _class}), do: reference

  defp method(state), do: state.operation.method |> Atom.to_string() |> String.upcase()

  defp cause(%Error{type: type, code: nil}), do: Atom.to_string(type)
  defp cause(%Error{type: type, code: code}), do: "#{type} #{code}"

  # ---------------------------------------------------------------------------------------
  # Test seams
  # ---------------------------------------------------------------------------------------

  defp now(%Client{clock: nil}), do: System.os_time(:millisecond)
  defp now(%Client{clock: clock}), do: clock.() |> round()

  defp sleep(%Client{sleeper: nil}, ms), do: Process.sleep(ms)
  defp sleep(%Client{sleeper: sleeper}, ms), do: sleeper.(ms)

  defp random(%Client{random: nil}), do: :rand.uniform()
  defp random(%Client{random: random}), do: random.()
end
