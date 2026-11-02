defmodule Unicom360.Examples.BalanceGet do
  @moduledoc """
  Read one balance: the SMS bundle, or another by `bundle_type:`.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.BalanceGet.main()"
  """

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    sms = Unicom360.Balance.get!(client)
    {:ok, whatsapp} = Unicom360.Balance.get(client, bundle_type: Unicom360.Balance.whatsapp())

    # Balances are Decimals, exactly as the gateway sent them.
    {Decimal.to_string(sms.balance), whatsapp.bundle_type}
  end
end
