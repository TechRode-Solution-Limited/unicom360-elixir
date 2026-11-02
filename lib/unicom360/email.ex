defmodule Unicom360.Email do
  @moduledoc """
  Send email (`POST /api/v1/json/bulk/email`).

      {:ok, result} =
        Unicom360.Email.send(client, %{
          from: "noreply@yourdomain.com",
          to: ["jane@example.com", "john@example.com"],
          subject: "Your order is confirmed",
          email_body: "<p>Thanks for your order. Order ZM4821 is confirmed.</p>",
          reply_to: "support@yourdomain.com"
        })

      jane = Unicom360.Email.SendResult.by_address(result, "jane@example.com")

  **Email is never retried after the request may have reached the gateway**, even with a
  `user_reference_id`: the gateway's duplicate check for email is not atomic, so two
  overlapping attempts could both be sent. It is retried only after a 429 and after a failure to
  connect.
  """

  alias Unicom360.{Client, HTTP, Params, References}
  alias Unicom360.Email.SendResult

  @operation %{method: :post, path: "/api/v1/json/bulk/email", kind: :envelope, auth: true}

  @typedoc """
  The email parameters, as a map or a keyword list:

    * `:from` (required) - a registered sender address.
    * `:to` (required) - one address, or a list of addresses.
    * `:subject` (required).
    * `:email_body` (required) - HTML or plain text.
    * `:reply_to` - the Reply-To address.
    * `:user_reference_id` - your reference; the gateway refuses a later repeat of it
      (`DUPLICATE_REFERENCE`).
    * `:callback_url` - where the gateway posts delivery reports (unsigned; see
      `Unicom360.Webhook.parse_email_callback/1`).
    * `:source` - a label for your reporting.
  """
  @type params ::
          %{
            required(:from) => String.t(),
            required(:to) => String.t() | [String.t()],
            required(:subject) => String.t(),
            required(:email_body) => String.t(),
            optional(:reply_to) => String.t() | nil,
            optional(:user_reference_id) => String.t() | nil,
            optional(:callback_url) => String.t() | nil,
            optional(:source) => String.t() | nil
          }
          | keyword()

  @doc """
  Sends an email to one or more addresses.

  Returns `{:ok, %Unicom360.Email.SendResult{}}`, one entry per recipient. An invalid address is
  not an error: its entry's status is `"Invalid email address"`. **Results are not in request
  order past the tenth recipient**: find one with `Unicom360.Email.SendResult.by_address/2`.

  Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec send(Client.t(), params(), keyword()) ::
          {:ok, SendResult.t()} | {:error, Unicom360.Error.t()}
  def send(%Client{} = client, params, opts \\ []) do
    body =
      Params.build!(
        params,
        [:from, :to, :subject, :email_body],
        [:reply_to, :user_reference_id, :callback_url, :source],
        "Unicom360.Email.send/3"
      )

    {body, generated} = References.put_missing(client, body)

    # Never retry-safe (x-retry-safe: never): see the moduledoc.
    with {:ok, json, _text} <-
           HTTP.request(client, @operation, body, opts, safe: false, generated: generated) do
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
