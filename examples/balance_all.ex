defmodule Unicom360.Examples.BalanceAll do
  @moduledoc """
  Read every balance.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.BalanceAll.main()"
  """

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    Unicom360.Balance.all!(client).balances
    |> Map.new(fn {bundle, balance} -> {bundle, Decimal.to_string(balance)} end)
  end
end
