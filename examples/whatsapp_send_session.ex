defmodule Unicom360.Examples.WhatsAppSendSession do
  @moduledoc """
  Send WhatsApp session messages, inside the 24-hour customer service window.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.WhatsAppSendSession.main()"
  """

  alias Unicom360.WhatsApp
  alias Unicom360.WhatsApp.{ListRow, ListSection, Session}

  @to "260971234567"

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    messages = [
      Session.text(@to, "Your order is ready.", user_reference_id: "s-1"),
      Session.image(@to, "https://example.com/receipt.png", caption: "Your receipt"),
      Session.document(@to, "https://example.com/invoice.pdf", filename: "invoice.pdf"),
      Session.buttons(@to, "Collect today or deliver?", [
        {"collect", "Collect"},
        {"deliver", "Deliver"}
      ]),
      Session.list(@to, "Choose a delivery slot", "Pick a slot", [
        ListSection.new(
          [ListRow.new("today-am", "Morning", "08:00 to 12:00")],
          "Today"
        )
      ]),
      Session.location(@to, -15.4167, 28.2833, name: "Cairo Road branch"),
      Session.reaction(@to, "7c1f3a2e-5b64-4d2f-9a8e-0f1b2c3d4e5f", "👍")
    ]

    Enum.map(messages, fn message ->
      case WhatsApp.send_session(client, message) do
        {:ok, sent} -> {:sent, sent.message_id}
        {:error, %Unicom360.Error{code: "SESSION_WINDOW_CLOSED"}} -> :send_a_template_instead
        {:error, %Unicom360.Error{} = error} -> {:failed, error.code}
      end
    end)
  end
end
