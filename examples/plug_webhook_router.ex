defmodule Unicom360.Examples.PlugWebhookRouter do
  @moduledoc """
  A plain Plug webhook receiver. Run it under Bandit or Cowboy:

      children = [{Bandit, plug: Unicom360.Examples.PlugWebhookRouter, port: 4000}]

  `Unicom360.Webhook.Plug` is mounted ahead of `Plug.Parsers`, so it reads the raw body itself.
  Behind `Plug.Parsers`, add `Unicom360.Webhook.BodyReader` (see the Phoenix example).
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  forward("/webhooks/unicom360/whatsapp",
    to: Unicom360.Webhook.Plug,
    init_opts: [
      # Read at request time, so the secret is not compiled in.
      secret: {__MODULE__, :webhook_secret, []},
      handler: Unicom360.Examples.WebhookHandler
    ]
  )

  post "/webhooks/unicom360/sms" do
    # SMS delivery reports are unsigned and never retried: treat them as hints.
    {:ok, body, conn} = read_body(conn)

    case Unicom360.Webhook.parse_sms_callback(body) do
      {:ok, report} -> send_resp(conn, 200, report.status)
      {:error, %Unicom360.Error{}} -> send_resp(conn, 400, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  def webhook_secret, do: System.fetch_env!("UNICOM360_WEBHOOK_SECRET")
end
