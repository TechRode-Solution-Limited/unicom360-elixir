defmodule Unicom360.Error do
  @moduledoc """
  The one error type of the SDK.

  Every function returns `{:error, %Unicom360.Error{}}` on failure, and its `!` variant raises
  the same struct. `type` says what went wrong; `class/1` names the canonical error class the
  other Unicom360 SDKs use, which also tells the business refusals apart.

  | `type` | `class/1` | When |
  |---|---|---|
  | `:configuration_error` | `ConfigurationError` | no API key, an unusable option, a blank webhook secret |
  | `:connection_error` | `APIConnectionError` | no complete response (refused, DNS, reset) |
  | `:timeout_error` | `APITimeoutError` | the connection or the response timed out |
  | `:api_status_error` | `APIStatusError` | any other non-2xx (3xx, 403, 404...), or a 2xx that is not an envelope |
  | `:authentication_error` | `AuthenticationError` | HTTP 401 |
  | `:rate_limit_error` | `RateLimitError` | HTTP 429; `retry_after` is set |
  | `:invalid_request_error` | `InvalidRequestError` | HTTP 400: the request's shape is wrong |
  | `:api_server_error` | `APIServerError` | HTTP 5xx |
  | `:api_error` | `APIError`, `InsufficientBundleError`, `DuplicateReferenceError`, `NoValidRecipientsError`, `SessionWindowClosedError` | HTTP 200 with `success: false` (or `status: false`): a business refusal |
  | `:signature_verification_error` | `SignatureVerificationError` | a webhook failed verification; `reason` says which check |
  | `:unicom360_error` | `Unicom360Error` | a webhook or callback body that is not a JSON object |

  HTTP 200 is not success: a refusal such as an unknown sender ID arrives as HTTP 200 with
  `success: false`, and is an `:api_error` whose `code` says why (see `Unicom360.Codes`).

  Fields:

    * `message`: human-readable text; for API errors, the gateway's message (an array of
      messages is joined with `"; "`). Never contains the API key.
    * `code`: the normalised code (`Unicom360.Codes.normalize/1`) on API errors, else `nil`.
    * `http_status`, `api_reference` (quote it to support), `raw_body`, `headers` (the
      response's, names lower-cased) and `data` (the envelope's `data`, raw) on API errors.
    * `attempts`: the HTTP attempts an operation made, retries included.
    * `retry_after`: on a `:rate_limit_error`, milliseconds until the next UTC minute, when the
      gateway's per-minute window resets.
    * `original_message_id`: on a `DuplicateReferenceError`, the `message_id` the earlier send
      returned, when the gateway says (session sends).
    * `results`: on a `NoValidRecipientsError`, why each recipient was rejected.
    * `reason`: on a `:signature_verification_error`, one of `:missing_signature`,
      `:missing_timestamp`, `:invalid_timestamp`, `:malformed_signature`,
      `:timestamp_out_of_tolerance`, `:signature_mismatch`.
    * `cause`: on a `:connection_error` or `:timeout_error`, the underlying exception.

  **A `DuplicateReferenceError` with `attempts` greater than 1 means an earlier attempt of the
  same call very probably succeeded**: the retry was refused because that attempt had already
  used the reference. Treat the message as sent.
  """

  @type type ::
          :unicom360_error
          | :configuration_error
          | :connection_error
          | :timeout_error
          | :api_status_error
          | :authentication_error
          | :rate_limit_error
          | :invalid_request_error
          | :api_server_error
          | :api_error
          | :signature_verification_error

  @type reason ::
          :missing_signature
          | :missing_timestamp
          | :invalid_timestamp
          | :malformed_signature
          | :timestamp_out_of_tolerance
          | :signature_mismatch

  @type t :: %__MODULE__{
          type: type(),
          message: String.t(),
          code: String.t() | nil,
          http_status: non_neg_integer() | nil,
          api_reference: String.t() | nil,
          raw_body: String.t() | nil,
          data: term(),
          headers: %{optional(String.t()) => [String.t()]} | nil,
          attempts: pos_integer() | nil,
          retry_after: non_neg_integer() | nil,
          reason: reason() | nil,
          original_message_id: String.t() | nil,
          results: [Unicom360.WhatsApp.TemplateResult.t()] | nil,
          cause: Exception.t() | nil
        }

  defexception type: :unicom360_error,
               message: "Unicom360 error",
               code: nil,
               http_status: nil,
               api_reference: nil,
               raw_body: nil,
               data: nil,
               headers: nil,
               attempts: nil,
               retry_after: nil,
               reason: nil,
               original_message_id: nil,
               results: nil,
               cause: nil

  @api_error_classes %{
    "INSUFFICIENT_BUNDLE" => "InsufficientBundleError",
    "DUPLICATE_REFERENCE" => "DuplicateReferenceError",
    "NO_VALID_RECIPIENTS" => "NoValidRecipientsError",
    "SESSION_WINDOW_CLOSED" => "SessionWindowClosedError"
  }

  @classes %{
    unicom360_error: "Unicom360Error",
    configuration_error: "ConfigurationError",
    connection_error: "APIConnectionError",
    timeout_error: "APITimeoutError",
    api_status_error: "APIStatusError",
    authentication_error: "AuthenticationError",
    rate_limit_error: "RateLimitError",
    invalid_request_error: "InvalidRequestError",
    api_server_error: "APIServerError",
    api_error: "APIError",
    signature_verification_error: "SignatureVerificationError"
  }

  @doc """
  The canonical class name of an error, as the other Unicom360 SDKs name it.

  An `:api_error` is classed by its code: `INSUFFICIENT_BUNDLE` is `"InsufficientBundleError"`,
  `DUPLICATE_REFERENCE` `"DuplicateReferenceError"`, `NO_VALID_RECIPIENTS`
  `"NoValidRecipientsError"`, `SESSION_WINDOW_CLOSED` `"SessionWindowClosedError"`, anything else
  `"APIError"`.

      iex> Unicom360.Error.class(%Unicom360.Error{type: :api_error, code: "INSUFFICIENT_BUNDLE"})
      "InsufficientBundleError"
      iex> Unicom360.Error.class(%Unicom360.Error{type: :rate_limit_error})
      "RateLimitError"
  """
  @spec class(t()) :: String.t()
  def class(%__MODULE__{type: :api_error, code: code}),
    do: Map.get(@api_error_classes, code, "APIError")

  def class(%__MODULE__{type: type}), do: Map.fetch!(@classes, type)

  @doc """
  Whether the error is a `:connection_error` or a `:timeout_error` (a timeout is a connection
  error too, as `APITimeoutError` extends `APIConnectionError`).
  """
  @spec connection_error?(t()) :: boolean()
  def connection_error?(%__MODULE__{type: type}), do: type in [:connection_error, :timeout_error]

  @doc """
  Whether the error came from a non-2xx response, or a 2xx that was not an envelope
  (`APIStatusError` and its subclasses).
  """
  @spec status_error?(t()) :: boolean()
  def status_error?(%__MODULE__{type: type}) do
    type in [
      :api_status_error,
      :authentication_error,
      :rate_limit_error,
      :invalid_request_error,
      :api_server_error
    ]
  end

  @impl true
  def message(%__MODULE__{message: message, api_reference: nil}), do: message

  def message(%__MODULE__{message: message, api_reference: reference}),
    do: "#{message} (api_reference #{reference})"

  @doc false
  @spec configuration(String.t()) :: t()
  def configuration(message), do: %__MODULE__{type: :configuration_error, message: message}

  @doc false
  @spec base(String.t()) :: t()
  def base(message), do: %__MODULE__{type: :unicom360_error, message: message}
end
