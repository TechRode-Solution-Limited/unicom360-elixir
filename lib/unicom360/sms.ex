defmodule Unicom360.SMS do
  @moduledoc """
  Send SMS (`POST /api/v1/json/bulk/sms`).

      {:ok, result} =
        Unicom360.SMS.send(client, %{
          from: "Unicom360",
          to: ["260971234567", "260961234567"],
          message: "Your verification code is 482193. It expires in 5 minutes."
        })

      for recipient <- result.results do
        IO.puts("\#{recipient.mobile_number} \#{recipient.status} \#{recipient.message_id}")
      end

  The gateway accepts GSM-7 text only, at most 1,200 characters, and bills
  `max(1, ceil(length / 160))` units per recipient. The SDK does not check this itself; see
  `Unicom360.GSM` to check before sending.
  """

  alias Unicom360.{Client, HTTP, Params, References}
  alias Unicom360.SMS.SendResult

  @operation %{method: :post, path: "/api/v1/json/bulk/sms", kind: :envelope, auth: true}

  @typedoc """
  The SMS parameters, as a map or a keyword list:

    * `:from` (required) - a registered sender ID.
    * `:to` (required) - one number, or a list of numbers. International form (`"2609..."`).
    * `:message` (required) - the text.
    * `:user_reference_id` - your reference. Makes the send safe to retry, and lets the gateway
      refuse a repeat (`DUPLICATE_REFERENCE`).
    * `:callback_url` - where the gateway posts delivery reports (unsigned; see
      `Unicom360.Webhook.parse_sms_callback/1`).
    * `:source` - a label for your reporting.
  """
  @type params ::
          %{
            required(:from) => String.t(),
            required(:to) => String.t() | [String.t()],
            required(:message) => String.t(),
            optional(:user_reference_id) => String.t() | nil,
            optional(:callback_url) => String.t() | nil,
            optional(:source) => String.t() | nil
          }
          | keyword()

  @doc """
  Sends an SMS to one or more numbers.

  Returns `{:ok, %Unicom360.SMS.SendResult{}}`, whose `results` hold one entry per recipient. An
  invalid number among them is not an error: its entry's status is `"Invalid mobile number"`
  (see `Unicom360.SMS.SendResult.invalid/1`). **Results are not in request order past the
  tenth recipient**: find one with `Unicom360.SMS.SendResult.by_number/2`.

  Fails with `{:error, %Unicom360.Error{}}`: for example `code: "INVALID_SENDER_ID"` or
  `"INSUFFICIENT_BUNDLE"` (an `:api_error` on HTTP 200).

  Options: `:timeout` (ms per attempt) and `:max_retries` override the client's for this call.
  The send is retried after a failure that may have reached the gateway only when it has a
  `user_reference_id`.
  """
  @spec send(Client.t(), params(), keyword()) ::
          {:ok, SendResult.t()} | {:error, Unicom360.Error.t()}
  def send(%Client{} = client, params, opts \\ []) do
    body =
      Params.build!(
        params,
        [:from, :to, :message],
        [:user_reference_id, :callback_url, :source],
        "Unicom360.SMS.send/3"
      )

    {body, generated} = References.put_missing(client, body)
    meta = [safe: References.present?(body["user_reference_id"]), generated: generated]

    with {:ok, json, _text} <- HTTP.request(client, @operation, body, opts, meta) do
      {:ok, SendResult.from_envelope(json)}
    end
  end

  @doc """
  Like `send/3`, but returns the result or raises `Unicom360.Error`.
  """
  @spec send!(Client.t(), params(), keyword()) :: SendResult.t()
  def send!(%Client{} = client, params, opts \\ []) do
    case send(client, params, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end
end
