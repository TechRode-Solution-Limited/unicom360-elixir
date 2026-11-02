defmodule Unicom360.Client do
  @moduledoc """
  A configured, immutable Unicom360 client.

  Build one with `Unicom360.client/1` (or `Unicom360.client!/1`) and pass it to every operation.
  A client is a plain struct: it holds no process and is safe to share between processes and to
  keep in application config or a module attribute at runtime. `put_options/2` returns a copy
  with other options.

  The API key is never shown by `inspect/2`:

      #Unicom360.Client<base_url: "https://api.unicom360.com", api_key: [REDACTED], ...>

  ## Options

    * `:api_key` - required. Defaults to the `:unicom360` application environment, then the
      `UNICOM360_API_KEY` environment variable. A missing, empty or blank key is a
      `:configuration_error`. An explicit `api_key: ""` does not fall back to the environment.
    * `:base_url` - defaults to the application environment, then `UNICOM360_BASE_URL`, then
      `"https://api.unicom360.com"`. Must be `https`; plain `http` is allowed only for
      `localhost`, `127.0.0.0/8` and `::1` (a local mock). A path prefix is kept, trailing
      slashes are removed, and a query string or fragment is refused.
    * `:timeout` - milliseconds to wait for the response on each attempt (Req's
      `:receive_timeout`). Default `60_000`.
    * `:connect_timeout` - milliseconds to connect, TLS included. Default `10_000`.
    * `:max_retries` - retries after the first attempt. Default `2`.
    * `:max_retry_wait` - the longest single wait between attempts, in milliseconds. Default
      `60_000`. A rate-limit wait longer than this returns the error at once.
    * `:auto_reference_ids` - give every send without a `user_reference_id` a generated one,
      reused on every retry. Default `false`. See the README.
    * `:app_info` - `%{name: "shopsync", version: "2.3.0", url: "https://shopsync.example"}`
      (version and url optional), appended to the User-Agent.
    * `:req_options` - extra options for `Req.new/1` (for example `:finch`, `:connect_options`
      or a custom `:adapter`). The SDK always sets `retry: false` (it retries itself),
      `redirect: false` (the API key is never replayed to another host) and its own method,
      URL, body and headers.
    * `:plug` - a plug that answers instead of the network, for tests (`Req.Test`).
    * `:clock` - a 0-arity function returning the current Unix time in milliseconds. Used for
      rate-limit waits. Test seam.
    * `:sleeper` - a 1-arity function taking milliseconds; every retry wait goes through it.
      Test seam.
    * `:random` - a 0-arity function returning a float in `[0, 1)`, for jitter. Test seam.

  `:api_key`, `:base_url`, `:timeout`, `:connect_timeout`, `:max_retries`, `:max_retry_wait`,
  `:auto_reference_ids`, `:app_info` and `:req_options` can also be set in the application
  environment:

      # config/runtime.exs
      config :unicom360, api_key: System.get_env("UNICOM360_API_KEY")

  An option passed to `Unicom360.client/1` wins over the application environment, which wins
  over the environment variables, which win over the defaults. A value of `nil`, and an
  environment variable that is empty or blank, count as unset.
  """

  alias Unicom360.Error

  @default_base_url "https://api.unicom360.com"

  @defaults [
    timeout: 60_000,
    connect_timeout: 10_000,
    max_retries: 2,
    max_retry_wait: 60_000,
    auto_reference_ids: false,
    app_info: nil,
    req_options: [],
    plug: nil,
    clock: nil,
    sleeper: nil,
    random: nil
  ]

  @app_env_keys [
    :api_key,
    :base_url,
    :timeout,
    :connect_timeout,
    :max_retries,
    :max_retry_wait,
    :auto_reference_ids,
    :app_info,
    :req_options
  ]

  @option_keys [:api_key, :base_url | Keyword.keys(@defaults)]

  @typedoc "`%{name: String.t(), version: String.t() | nil, url: String.t() | nil}`"
  @type app_info :: %{name: String.t(), version: String.t() | nil, url: String.t() | nil}

  @type option ::
          {:api_key, String.t()}
          | {:base_url, String.t()}
          | {:timeout, pos_integer()}
          | {:connect_timeout, pos_integer()}
          | {:max_retries, non_neg_integer()}
          | {:max_retry_wait, non_neg_integer()}
          | {:auto_reference_ids, boolean()}
          | {:app_info, map() | keyword()}
          | {:req_options, keyword()}
          | {:plug, term()}
          | {:clock, (-> integer())}
          | {:sleeper, (non_neg_integer() -> term())}
          | {:random, (-> float())}

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          timeout: pos_integer(),
          connect_timeout: pos_integer(),
          max_retries: non_neg_integer(),
          max_retry_wait: non_neg_integer(),
          auto_reference_ids: boolean(),
          app_info: app_info() | nil,
          req_options: keyword(),
          plug: term(),
          clock: (-> integer()) | nil,
          sleeper: (non_neg_integer() -> term()) | nil,
          random: (-> float()) | nil,
          user_agent: String.t()
        }

  @enforce_keys [:api_key, :base_url, :user_agent]
  defstruct [:api_key, :base_url, :user_agent] ++ @defaults

  @doc false
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- check_keys(opts) do
      opts = Enum.reject(opts, fn {_key, value} -> is_nil(value) end)
      app_env = app_env()

      resolved =
        Enum.map(@option_keys, fn key ->
          {key, resolve(key, Keyword.fetch(opts, key), Keyword.fetch(app_env, key))}
        end)

      build(resolved)
    end
  end

  def new(_opts), do: {:error, Error.configuration("options must be a keyword list")}

  @doc """
  Returns a copy of the client with some options changed.

  Takes the same options as `Unicom360.client/1`; the ones not given keep their current value
  (the environment is not read again). Raises `Unicom360.Error` (`:configuration_error`) for an
  unusable option.

      fast = Unicom360.Client.put_options(client, timeout: 5_000, max_retries: 0)
  """
  @spec put_options(t(), [option()]) :: t()
  def put_options(%__MODULE__{} = client, opts) when is_list(opts) do
    with :ok <- check_keys(opts),
         current = Enum.map(@option_keys, &{&1, Map.fetch!(client, &1)}),
         {:ok, updated} <- build(Keyword.merge(current, opts)) do
      updated
    else
      {:error, error} -> raise error
    end
  end

  defp app_env do
    Enum.flat_map(@app_env_keys, fn key ->
      case Application.get_env(:unicom360, key) do
        nil -> []
        value -> [{key, value}]
      end
    end)
  end

  defp check_keys(opts) do
    if Keyword.keyword?(opts) do
      case Enum.uniq(Keyword.keys(opts)) -- @option_keys do
        [] -> :ok
        unknown -> {:error, Error.configuration("unknown options: #{inspect(unknown)}")}
      end
    else
      {:error, Error.configuration("options must be a keyword list")}
    end
  end

  defp resolve(:api_key, {:ok, value}, _app), do: value
  defp resolve(:api_key, :error, {:ok, value}), do: value
  defp resolve(:api_key, :error, :error), do: system_env("UNICOM360_API_KEY")
  defp resolve(:base_url, {:ok, value}, _app), do: value
  defp resolve(:base_url, :error, {:ok, value}), do: value

  defp resolve(:base_url, :error, :error),
    do: system_env("UNICOM360_BASE_URL") || @default_base_url

  defp resolve(_key, {:ok, value}, _app), do: value
  defp resolve(_key, :error, {:ok, value}), do: value
  defp resolve(key, :error, :error), do: Keyword.fetch!(@defaults, key)

  defp system_env(name) do
    case System.get_env(name) do
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: value
    end
  end

  defp build(options) do
    with {:ok, api_key} <- api_key(options[:api_key]),
         {:ok, base_url} <- base_url(options[:base_url]),
         {:ok, timeout} <- positive(:timeout, options[:timeout]),
         {:ok, connect_timeout} <- positive(:connect_timeout, options[:connect_timeout]),
         {:ok, max_retries} <- non_negative(:max_retries, options[:max_retries]),
         {:ok, max_retry_wait} <- non_negative(:max_retry_wait, options[:max_retry_wait]),
         {:ok, auto} <- boolean(:auto_reference_ids, options[:auto_reference_ids]),
         {:ok, app_info} <- app_info(options[:app_info]),
         {:ok, req_options} <- req_options(options[:req_options]),
         {:ok, clock} <- function(:clock, options[:clock], 0),
         {:ok, sleeper} <- function(:sleeper, options[:sleeper], 1),
         {:ok, random} <- function(:random, options[:random], 0) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         base_url: base_url,
         timeout: timeout,
         connect_timeout: connect_timeout,
         max_retries: max_retries,
         max_retry_wait: max_retry_wait,
         auto_reference_ids: auto,
         app_info: app_info,
         req_options: req_options,
         plug: options[:plug],
         clock: clock,
         sleeper: sleeper,
         random: random,
         user_agent: Unicom360.UserAgent.build(app_info)
       }}
    end
  end

  defp api_key(nil) do
    {:error,
     Error.configuration(
       "no API key: pass api_key: to Unicom360.client/1, set config :unicom360, api_key: ..., " <>
         "or set UNICOM360_API_KEY"
     )}
  end

  defp api_key(key) when is_binary(key) do
    if String.trim(key) == "",
      do: {:error, Error.configuration("the API key is empty")},
      else: {:ok, key}
  end

  defp api_key(_key), do: {:error, Error.configuration("the API key must be a string")}

  @doc false
  @spec base_url(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def base_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{} = uri} -> check_base_url(uri)
      {:error, _part} -> base_url_error(url, "is not a valid URL")
    end
  end

  def base_url(_url), do: {:error, Error.configuration("base_url must be a string")}

  defp check_base_url(%URI{host: host} = uri) when host in [nil, ""],
    do: base_url_error(uri, "has no host")

  defp check_base_url(%URI{query: query} = uri) when not is_nil(query),
    do: base_url_error(uri, "must not carry a query string")

  defp check_base_url(%URI{fragment: fragment} = uri) when not is_nil(fragment),
    do: base_url_error(uri, "must not carry a fragment")

  defp check_base_url(%URI{userinfo: userinfo} = uri) when not is_nil(userinfo),
    do: base_url_error(uri, "must not carry a user name or password")

  defp check_base_url(%URI{scheme: "https"} = uri), do: {:ok, normalize(uri)}

  defp check_base_url(%URI{scheme: "http", host: host} = uri) do
    if loopback?(host),
      do: {:ok, normalize(uri)},
      else: base_url_error(uri, "must use https (plain http is allowed only for localhost)")
  end

  defp check_base_url(uri), do: base_url_error(uri, "must use https")

  defp normalize(%URI{} = uri) do
    path = String.trim_trailing(uri.path || "", "/")
    uri |> Map.put(:path, path) |> URI.to_string() |> String.trim_trailing("/")
  end

  defp loopback?("localhost"), do: true
  defp loopback?("::1"), do: true

  defp loopback?(host) do
    case :inet.parse_ipv4strict_address(String.to_charlist(host)) do
      {:ok, {127, _b, _c, _d}} -> true
      _ -> false
    end
  end

  defp base_url_error(uri, problem) do
    # Never echo a URL that may carry credentials.
    shown = if is_struct(uri, URI), do: %{uri | userinfo: nil} |> URI.to_string(), else: "it"
    {:error, Error.configuration("base_url #{inspect(shown)} #{problem}")}
  end

  defp positive(_key, value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive(key, value),
    do: {:error, Error.configuration("#{key} must be a positive integer, got: #{inspect(value)}")}

  defp non_negative(_key, value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp non_negative(key, value) do
    {:error, Error.configuration("#{key} must be a non-negative integer, got: #{inspect(value)}")}
  end

  defp boolean(_key, value) when is_boolean(value), do: {:ok, value}

  defp boolean(key, value),
    do: {:error, Error.configuration("#{key} must be a boolean, got: #{inspect(value)}")}

  defp app_info(nil), do: {:ok, nil}

  defp app_info(info) when is_list(info) do
    if Keyword.keyword?(info),
      do: app_info(Map.new(info)),
      else: {:error, Error.configuration("app_info must be a map or a keyword list")}
  end

  defp app_info(%{name: name} = info) when is_binary(name) and name != "" do
    version = Map.get(info, :version)
    url = Map.get(info, :url)

    if (is_nil(version) or is_binary(version)) and (is_nil(url) or is_binary(url)) and
         Map.keys(info) -- [:name, :version, :url] == [] do
      {:ok, %{name: name, version: version, url: url}}
    else
      {:error, Error.configuration("app_info takes :name, and optionally :version and :url")}
    end
  end

  defp app_info(_info),
    do: {:error, Error.configuration("app_info needs a :name, and optionally :version and :url")}

  defp req_options(options) when is_list(options) do
    if Keyword.keyword?(options),
      do: {:ok, options},
      else: {:error, Error.configuration("req_options must be a keyword list")}
  end

  defp req_options(_options),
    do: {:error, Error.configuration("req_options must be a keyword list")}

  defp function(_key, nil, _arity), do: {:ok, nil}
  defp function(_key, fun, arity) when is_function(fun, arity), do: {:ok, fun}

  defp function(key, _value, arity),
    do: {:error, Error.configuration("#{key} must be a function of arity #{arity}")}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(client, opts) do
      fields = [
        base_url: client.base_url,
        api_key: :redacted,
        timeout: client.timeout,
        connect_timeout: client.connect_timeout,
        max_retries: client.max_retries,
        max_retry_wait: client.max_retry_wait,
        auto_reference_ids: client.auto_reference_ids,
        app_info: client.app_info
      ]

      pairs =
        Enum.map(fields, fn
          {:api_key, :redacted} -> "api_key: [REDACTED]"
          {key, value} -> concat(["#{key}: ", to_doc(value, opts)])
        end)

      container_doc("#Unicom360.Client<", pairs, ">", opts, fn doc, _opts -> doc end,
        separator: ","
      )
    end
  end
end
