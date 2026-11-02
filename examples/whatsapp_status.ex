defmodule Unicom360.Examples.WhatsAppStatus do
  @moduledoc """
  Look up the status of WhatsApp messages.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.WhatsAppStatus.main()"
  """

  alias Unicom360.WhatsApp

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    id = "7c1f3a2e-5b64-4d2f-9a8e-0f1b2c3d4e5f"
    status = WhatsApp.status!(client, [id])

    case WhatsApp.StatusResult.by_id(status, id) do
      nil -> :not_asked_for
      entry -> {entry.status, entry.error && entry.error.message}
    end
  end
end
