defmodule Unicom360.Examples.EmailSend do
  @moduledoc """
  Send an email.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.EmailSend.main()"
  """

  alias Unicom360.Email.SendResult

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    result =
      Unicom360.Email.send!(client,
        from: "noreply@yourdomain.com",
        to: ["jane@example.com", "john@example.com"],
        subject: "Your order is confirmed",
        email_body: "<p>Thanks for your order. Order ZM4821 is confirmed.</p>",
        reply_to: "support@yourdomain.com"
      )

    jane = SendResult.by_address(result, "jane@example.com")
    {result.api_reference, jane && jane.message_id}
  end
end
