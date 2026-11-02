defmodule Unicom360.Examples.PhoenixWebhookController do
  @moduledoc """
  A Phoenix controller receiving Unicom360 webhooks.

  In `endpoint.ex`, keep the raw body the signature covers:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library(),
        body_reader: {Unicom360.Webhook.BodyReader, :read_body, []}

  In `router.ex`, a route outside any CSRF-protected pipeline:

      post "/webhooks/unicom360/whatsapp", Unicom360.Examples.PhoenixWebhookController, :whatsapp

  In your own app, `use MyAppWeb, :controller` replaces the `use Phoenix.Controller` line.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Unicom360.Examples.WebhookHandler

  def whatsapp(conn, _params) do
    secret = System.fetch_env!("UNICOM360_WEBHOOK_SECRET")

    case Unicom360.Webhook.construct_event(conn.assigns.raw_body, conn.req_headers, secret) do
      {:ok, event} ->
        :ok = WebhookHandler.handle_event(event, conn)
        send_resp(conn, 200, "")

      {:error, %Unicom360.Error{type: :signature_verification_error, reason: reason}} ->
        send_resp(conn, 401, Atom.to_string(reason))

      {:error, %Unicom360.Error{}} ->
        send_resp(conn, 400, "not a webhook event")
    end
  end
end
