defmodule Unicom360.Examples.WhatsAppSendTemplate do
  @moduledoc """
  Send an approved WhatsApp template.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.WhatsAppSendTemplate.main()"
  """

  alias Unicom360.WhatsApp
  alias Unicom360.WhatsApp.{TemplateBody, TemplateButton, TemplateHeader, TemplateRecipient}

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    result =
      WhatsApp.send_template!(client, %{
        template: "order_ready",
        language: "en_US",
        recipients: [
          TemplateRecipient.new("260971234567",
            user_reference_id: "inv-42",
            header: TemplateHeader.image("https://example.com/receipts/ZM-4821.png"),
            body: TemplateBody.of(["Ada", "ZM-4821"]),
            buttons: [TemplateButton.url(0, "ZM-4821")]
          ),
          # A plain map works too.
          %{to: "260961234567", user_reference_id: "inv-43", body: ["Joseph", "ZM-4822"]}
        ]
      })

    # A rejected recipient is not an error.
    rejected = Enum.map(WhatsApp.TemplateSendResult.rejected(result), &{&1.to, &1.reason})
    {result.accepted_count, result.rejected_count, rejected}
  end
end
