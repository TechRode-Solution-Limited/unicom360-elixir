defmodule Unicom360.Examples.Health do
  @moduledoc """
  Check that the API is up. Sends no API key (the client still needs one to be built).

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.Health.main()"
  """

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    {:ok, health} = Unicom360.health(client)
    {health.status, health.version}
  end
end
