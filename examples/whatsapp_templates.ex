defmodule Unicom360.Examples.WhatsAppTemplates do
  @moduledoc """
  List the account's approved WhatsApp templates.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.WhatsAppTemplates.main()"
  """

  alias Unicom360.WhatsApp

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    list = WhatsApp.templates!(client)
    order_ready = WhatsApp.TemplateList.by_name(list, "order_ready", "en_US")
    {Enum.map(list.templates, & &1.name), order_ready && order_ready.body.variables}
  end
end
