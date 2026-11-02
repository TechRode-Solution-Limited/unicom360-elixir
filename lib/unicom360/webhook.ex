defmodule Unicom360.Webhook do
  @moduledoc """
  Verify and parse Unicom360 webhooks, and parse the unsigned SMS and email delivery reports.

  WhatsApp events (`message.status`, `message.received`, `webhook.test`) are signed. Verify and
  parse a delivery with `construct_event/4`, passing the **raw body**, the request headers and
  your webhook secret (the 43-character string from the portal, used as it is: never
  base64-decode it):

      case Unicom360.Webhook.construct_event(raw_body, conn.req_headers, secret) do
        {:ok, %Unicom360.Webhook.MessageStatusEvent{data: data}} -> data.status
        {:ok, %Unicom360.Webhook.MessageReceivedEvent{data: message}} -> message.text
        {:ok, %Unicom360.Webhook.TestEvent{}} -> :ok
        {:ok, %Unicom360.Webhook.UnknownEvent{event: event}} -> event
        {:error, %Unicom360.Error{type: :signature_verification_error, reason: reason}} -> reason
      end

  In Phoenix or Plug, `Unicom360.Webhook.Plug` does all of this, and
  `Unicom360.Webhook.BodyReader` keeps the raw body that `Plug.Parsers` would otherwise consume.

  Good to know:

    * Deliveries are retried on any non-2xx (after 30 s, 2 min, 10 min, 30 min, 1 h, 3 h, 6 h
      and 12 h). Answer 2xx quickly and drop repeats by the event's `delivery_id`.
    * A secret that is `nil`, empty or only whitespace (an unset environment variable, say) is a
      `:configuration_error` before any other check, because anyone can forge a signature with
      an empty key. That is a fault in your configuration, not a failed verification: answer 500,
      not 401. Otherwise the secret is used exactly as given, never trimmed.
    * In `message.received`: a media caption arrives in `text`, not in `media`; `payload` is set
      only for location, contacts (`%{"contacts" => [...]}`), reaction, sticker and unsupported
      messages; an interactive or button reply has the chosen title in `text`, `payload` is
      `nil`, and `reply_to` is the `wamid.` id of your interactive message (the button or row id
      is not passed on).
    * SMS and email delivery reports (`parse_sms_callback/1`, `parse_email_callback/1`) are
      **unsigned and never retried**: anyone can post one, so treat them as hints.

  Times are in milliseconds, as everywhere in this SDK: `:tolerance` defaults to `300_000`
  (five minutes) and `:now` is Unix time in milliseconds.
  """

  alias Unicom360.Error

  alias Unicom360.Webhook.{
    EmailDeliveryReport,
    MessageReceivedEvent,
    MessageStatusEvent,
    SmsDeliveryReport,
    TestEvent,
    UnknownEvent
  }

  @default_tolerance 300_000

  @typedoc """
  Request headers: a list of `{name, value}` pairs (as in `conn.req_headers`) or a map from name
  to a value or a list of values. Names are matched without regard to case; when a header has
  several values, the first is used.
  """
  @type headers ::
          [{String.t(), String.t()}] | %{optional(String.t()) => String.t() | [String.t()]}

  @typedoc "`:tolerance` (ms, default `300_000`) and `:now` (Unix time in ms, default the clock)."
  @type option :: {:tolerance, non_neg_integer()} | {:now, integer()}

  @type event ::
          MessageStatusEvent.t() | MessageReceivedEvent.t() | TestEvent.t() | UnknownEvent.t()

  @doc """
  Verifies a webhook delivery's signature.

  Returns `:ok`, or `{:error, %Unicom360.Error{type: :signature_verification_error}}` whose
  `reason` is the first check that failed: `:missing_signature`, `:missing_timestamp`,
  `:invalid_timestamp`, `:malformed_signature`, `:timestamp_out_of_tolerance` (more than
  `:tolerance` from `:now`, in either direction) or `:signature_mismatch`. The signature is
  compared in constant time.

  A secret that is `nil`, empty or only whitespace returns
  `{:error, %Unicom360.Error{type: :configuration_error}}`, with no `reason`, before any other
  check: anyone can forge a signature with an empty key.

  `raw_body` must be the exact bytes received, before any JSON parsing.
  """
  @spec verify(iodata(), headers(), String.t() | nil, [option()]) :: :ok | {:error, Error.t()}
  def verify(raw_body, headers, secret, opts \\ []) do
    with :ok <- check_secret(secret) do
      verify_signature(raw_body, headers, secret, opts)
    end
  end

  @doc false
  @spec check_secret(term()) :: :ok | {:error, Error.t()}
  def check_secret(secret) do
    if is_binary(secret) and String.trim(secret) != "" do
      :ok
    else
      {:error,
       Error.configuration(
         "the webhook secret is empty or only whitespace: set it to the secret from the portal"
       )}
    end
  end

  defp verify_signature(raw_body, headers, secret, opts) do
    opts = verify_options!(opts)
    body = IO.iodata_to_binary(raw_body)
    signature = header(headers, "x-unicom360-signature")
    timestamp = header(headers, "x-unicom360-timestamp")

    with :ok <- check(signature not in [nil, ""], :missing_signature),
         :ok <- check(timestamp not in [nil, ""], :missing_timestamp),
         :ok <- check(digits?(timestamp), :invalid_timestamp),
         :ok <- check(well_formed?(signature), :malformed_signature),
         :ok <- check(fresh?(timestamp, opts), :timestamp_out_of_tolerance) do
      check(matches?(signature, timestamp, body, secret), :signature_mismatch)
    end
  end

  defp verify_options!(opts) do
    opts = Keyword.validate!(opts, tolerance: @default_tolerance, now: nil)

    # A nil tolerance would compare as larger than any number and turn the check off.
    if not (is_integer(opts[:tolerance]) and opts[:tolerance] >= 0) do
      raise ArgumentError, "tolerance must be a non-negative integer (ms)"
    end

    opts
  end

  defp check(true, _reason), do: :ok

  defp check(false, reason) do
    {:error,
     %Error{
       type: :signature_verification_error,
       reason: reason,
       message: "webhook signature verification failed: #{reason}"
     }}
  end

  @doc """
  Like `verify/4`, but returns `:ok` or raises `Unicom360.Error`.
  """
  @spec verify!(iodata(), headers(), String.t() | nil, [option()]) :: :ok
  def verify!(raw_body, headers, secret, opts \\ []) do
    case verify(raw_body, headers, secret, opts) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  @doc """
  Verifies a delivery (see `verify/4`), then parses it into an event:
  `Unicom360.Webhook.MessageStatusEvent`, `Unicom360.Webhook.MessageReceivedEvent`,
  `Unicom360.Webhook.TestEvent`, or `Unicom360.Webhook.UnknownEvent` for an event this version
  does not know (never an error).

  The event's `delivery_id` is the `X-Unicom360-Delivery` header: drop repeats by it. A verified
  body that is not a JSON object with a string `event` is an error of type `:unicom360_error`. A
  secret that is `nil`, empty or only whitespace is a `:configuration_error`.
  """
  @spec construct_event(iodata(), headers(), String.t() | nil, [option()]) ::
          {:ok, event()} | {:error, Error.t()}
  def construct_event(raw_body, headers, secret, opts \\ []) do
    body = IO.iodata_to_binary(raw_body)

    with :ok <- verify(body, headers, secret, opts),
         {:ok, %{"event" => event} = json} when is_binary(event) <- decode(body) do
      delivery_id = header(headers, "x-unicom360-delivery")
      {:ok, event(event, json, delivery_id)}
    else
      {:error, %Error{}} = error -> error
      _ -> {:error, Error.base("the webhook body is not a JSON object with an event")}
    end
  end

  @doc """
  Like `construct_event/4`, but returns the event or raises `Unicom360.Error`.
  """
  @spec construct_event!(iodata(), headers(), String.t() | nil, [option()]) :: event()
  def construct_event!(raw_body, headers, secret, opts \\ []) do
    case construct_event(raw_body, headers, secret, opts) do
      {:ok, event} -> event
      {:error, error} -> raise error
    end
  end

  @doc """
  Parses an SMS delivery report posted to a send's `callback_url`.

  **Unsigned and never retried**: anyone can post one, so treat it as a hint. Returns
  `{:ok, %Unicom360.Webhook.SmsDeliveryReport{}}` (`message_id`, `status`: `"SENT"`,
  `"DELIVERED"`, `"FAILED"`, `"UNKNOWN_ERROR"` or another value, `mobile_number`), or an error of
  type `:unicom360_error` for a body that is not a JSON object.
  """
  @spec parse_sms_callback(iodata()) :: {:ok, SmsDeliveryReport.t()} | {:error, Error.t()}
  def parse_sms_callback(raw_body), do: callback(raw_body, "SMS", &SmsDeliveryReport.from_map/1)

  @doc """
  Like `parse_sms_callback/1`, but returns the report or raises `Unicom360.Error`.
  """
  @spec parse_sms_callback!(iodata()) :: SmsDeliveryReport.t()
  def parse_sms_callback!(raw_body), do: bang(parse_sms_callback(raw_body))

  @doc """
  Parses an email delivery report posted to a send's `callback_url`.

  **Unsigned and never retried**: treat it as a hint. Returns
  `{:ok, %Unicom360.Webhook.EmailDeliveryReport{}}` (`message_id` as a string, though the wire
  sends a number; `status`: `"SENT"`, `"DELIVERED"`, `"FAILED"` or another value;
  `email_address`; `message`), or an error of type `:unicom360_error` for a body that is not a
  JSON object.
  """
  @spec parse_email_callback(iodata()) :: {:ok, EmailDeliveryReport.t()} | {:error, Error.t()}
  def parse_email_callback(raw_body),
    do: callback(raw_body, "email", &EmailDeliveryReport.from_map/1)

  @doc """
  Like `parse_email_callback/1`, but returns the report or raises `Unicom360.Error`.
  """
  @spec parse_email_callback!(iodata()) :: EmailDeliveryReport.t()
  def parse_email_callback!(raw_body), do: bang(parse_email_callback(raw_body))

  defp callback(raw_body, kind, parse) do
    case decode(IO.iodata_to_binary(raw_body)) do
      {:ok, json} when is_map(json) -> {:ok, parse.(json)}
      _ -> {:error, Error.base("the #{kind} delivery report is not a JSON object")}
    end
  end

  defp event("message.status", json, delivery_id),
    do: MessageStatusEvent.from_map(json, delivery_id)

  defp event("message.received", json, delivery_id),
    do: MessageReceivedEvent.from_map(json, delivery_id)

  defp event("webhook.test", json, delivery_id), do: TestEvent.from_map(json, delivery_id)
  defp event(_event, json, delivery_id), do: UnknownEvent.from_map(json, delivery_id)

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, json} -> {:ok, json}
      {:error, _error} -> :error
    end
  end

  defp bang({:ok, result}), do: result
  defp bang({:error, error}), do: raise(error)

  @doc false
  @spec header(headers(), String.t()) :: String.t() | nil
  def header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: first(value)
    end)
  end

  defp first([value | _rest]), do: value
  defp first([]), do: nil
  defp first(value), do: value

  # `^[0-9]+$`
  defp digits?(<<>>), do: false
  defp digits?(text), do: for(<<c <- text>>, reduce: true, do: (ok -> ok and c in ?0..?9))

  # `^sha256=[0-9a-f]{64}$` (lowercase hex only)
  defp well_formed?(<<"sha256=", hex::binary-size(64)>>),
    do: for(<<c <- hex>>, reduce: true, do: (ok -> ok and (c in ?0..?9 or c in ?a..?f)))

  defp well_formed?(_signature), do: false

  # Inclusive. A timestamp too large for a 64-bit integer is out of tolerance.
  defp fresh?(timestamp, _opts) when byte_size(timestamp) > 18, do: false

  defp fresh?(timestamp, opts) do
    now = opts[:now] || System.os_time(:millisecond)
    abs(now - String.to_integer(timestamp) * 1_000) <= opts[:tolerance]
  end

  defp matches?("sha256=" <> given, timestamp, body, secret) do
    expected =
      :hmac
      |> :crypto.mac(:sha256, secret, [timestamp, ".", body])
      |> Base.encode16(case: :lower)

    :crypto.hash_equals(expected, given)
  end
end
