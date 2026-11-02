defmodule Unicom360.WhatsApp do
  @moduledoc """
  WhatsApp Business messaging: approved templates, session messages inside the 24-hour customer
  service window, message status and the template list.

      alias Unicom360.WhatsApp
      alias Unicom360.WhatsApp.{Session, TemplateBody, TemplateHeader, TemplateRecipient}

      {:ok, result} =
        WhatsApp.send_template(client, %{
          template: "order_ready",
          language: "en_US",
          recipients: [
            TemplateRecipient.new("260971234567",
              user_reference_id: "inv-42",
              header: TemplateHeader.image("https://example.com/receipts/ZM-4821.png"),
              body: TemplateBody.of(["Ada", "ZM-4821"])
            )
          ]
        })

      {:ok, sent} = WhatsApp.send_session(client, Session.text("260971234567", "Ready!"))
      {:ok, status} = WhatsApp.status(client, [sent.message_id])
  """

  alias Unicom360.{Client, HTTP, Params, References}

  alias Unicom360.WhatsApp.{
    SessionMessage,
    SessionSendResult,
    StatusResult,
    TemplateList,
    TemplateRecipient,
    TemplateSendResult
  }

  @template %{method: :post, path: "/api/v1/json/whatsapp/template", kind: :envelope, auth: true}
  @session %{method: :post, path: "/api/v1/json/whatsapp/session", kind: :envelope, auth: true}
  @status %{method: :post, path: "/api/v1/json/whatsapp/status", kind: :envelope, auth: true}
  @templates %{method: :get, path: "/api/v1/json/whatsapp/templates", kind: :envelope, auth: true}

  @typedoc """
  The template send parameters, as a map or a keyword list:

    * `:template` (required) - the approved template's name.
    * `:recipients` (required) - a list of `Unicom360.WhatsApp.TemplateRecipient` (or maps with
      the same keys).
    * `:from` - your WhatsApp number, when the account has several.
    * `:language` - the template's language (`"en_US"`), when it exists in several.
    * `:callback_url` - an https URL for this send's `message.status` webhooks.
  """
  @type template_params ::
          %{
            required(:template) => String.t(),
            required(:recipients) => [TemplateRecipient.t() | map() | keyword()],
            optional(:from) => String.t() | nil,
            optional(:language) => String.t() | nil,
            optional(:callback_url) => String.t() | nil
          }
          | keyword()

  @doc """
  Sends an approved template to up to 1,000 recipients.

  Rejected recipients are not an error: see `Unicom360.WhatsApp.TemplateSendResult.rejected/1`.
  When every recipient is rejected, fails with `%Unicom360.Error{code: "NO_VALID_RECIPIENTS"}`
  (whose `results` say why).

  Safe to retry after a failure that may have reached the gateway only when every recipient has
  a `user_reference_id`. Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec send_template(Client.t(), template_params(), keyword()) ::
          {:ok, TemplateSendResult.t()} | {:error, Unicom360.Error.t()}
  def send_template(%Client{} = client, params, opts \\ []) do
    body =
      Params.build!(
        params,
        [:template, :recipients],
        [:from, :language, :callback_url],
        "Unicom360.WhatsApp.send_template/3"
      )

    if not is_list(body["recipients"]) do
      raise ArgumentError, "Unicom360.WhatsApp.send_template/3: :recipients must be a list"
    end

    {recipients, generated} =
      body["recipients"]
      |> Enum.map(&TemplateRecipient.to_api/1)
      |> Enum.map_reduce([], fn recipient, generated ->
        {recipient, new} = References.put_missing(client, recipient)
        {recipient, generated ++ new}
      end)

    body = %{body | "recipients" => recipients}

    safe =
      recipients != [] and
        Enum.all?(recipients, &References.present?(&1["user_reference_id"]))

    with {:ok, json, _text} <-
           HTTP.request(client, @template, body, opts, safe: safe, generated: generated) do
      {:ok, TemplateSendResult.from_envelope(json)}
    end
  end

  @doc """
  Like `send_template/3`, but returns the result or raises `Unicom360.Error`.
  """
  @spec send_template!(Client.t(), template_params(), keyword()) :: TemplateSendResult.t()
  def send_template!(%Client{} = client, params, opts \\ []),
    do: bang(send_template(client, params, opts))

  @doc """
  Sends a session message (free-form, inside the 24-hour customer service window).

  `message` is a `Unicom360.WhatsApp.SessionMessage` built with `Unicom360.WhatsApp.Session`, or
  a map in the API's shape, sent as given. Outside the window, fails with
  `%Unicom360.Error{code: "SESSION_WINDOW_CLOSED"}`: send a template instead.

  Safe to retry after a failure that may have reached the gateway only with a
  `user_reference_id`. Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec send_session(Client.t(), SessionMessage.t() | map(), keyword()) ::
          {:ok, SessionSendResult.t()} | {:error, Unicom360.Error.t()}
  def send_session(client, message, opts \\ [])

  def send_session(%Client{} = client, %SessionMessage{} = message, opts),
    do: send_session(client, SessionMessage.to_api(message), opts)

  def send_session(%Client{}, %{__struct__: _} = message, _opts) do
    raise ArgumentError,
          "Unicom360.WhatsApp.send_session/3 takes a SessionMessage or a map, got: " <>
            inspect(message)
  end

  def send_session(%Client{} = client, message, opts) when is_map(message) do
    {body, generated} = References.put_missing(client, message)
    safe = References.present?(References.reference(body))

    with {:ok, json, _text} <-
           HTTP.request(client, @session, body, opts, safe: safe, generated: generated) do
      {:ok, SessionSendResult.from_envelope(json)}
    end
  end

  @doc """
  Like `send_session/3`, but returns the result or raises `Unicom360.Error`.
  """
  @spec send_session!(Client.t(), SessionMessage.t() | map(), keyword()) :: SessionSendResult.t()
  def send_session!(%Client{} = client, message, opts \\ []),
    do: bang(send_session(client, message, opts))

  @doc """
  The status of 1 to 100 messages, by the `message_id` a send returned.

  The ids are sent as given (the gateway answers each distinct id once). An unknown id has
  status `"NOT_FOUND"`. Find one with `Unicom360.WhatsApp.StatusResult.by_id/2`.
  Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec status(Client.t(), [String.t()], keyword()) ::
          {:ok, StatusResult.t()} | {:error, Unicom360.Error.t()}
  def status(%Client{} = client, message_ids, opts \\ []) when is_list(message_ids) do
    with {:ok, json, _text} <-
           HTTP.request(client, @status, %{"message_ids" => message_ids}, opts, safe: true) do
      {:ok, StatusResult.from_envelope(json)}
    end
  end

  @doc """
  Like `status/3`, but returns the result or raises `Unicom360.Error`.
  """
  @spec status!(Client.t(), [String.t()], keyword()) :: StatusResult.t()
  def status!(%Client{} = client, message_ids, opts \\ []),
    do: bang(status(client, message_ids, opts))

  @doc """
  The account's approved templates, with their variables and buttons. Find one with
  `Unicom360.WhatsApp.TemplateList.by_name/3`.
  Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec templates(Client.t(), keyword()) ::
          {:ok, TemplateList.t()} | {:error, Unicom360.Error.t()}
  def templates(%Client{} = client, opts \\ []) do
    with {:ok, json, _text} <- HTTP.request(client, @templates, nil, opts, safe: true) do
      {:ok, TemplateList.from_envelope(json)}
    end
  end

  @doc """
  Like `templates/2`, but returns the result or raises `Unicom360.Error`.
  """
  @spec templates!(Client.t(), keyword()) :: TemplateList.t()
  def templates!(%Client{} = client, opts \\ []), do: bang(templates(client, opts))

  defp bang({:ok, result}), do: result
  defp bang({:error, error}), do: raise(error)
end
