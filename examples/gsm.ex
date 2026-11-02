defmodule Unicom360.Examples.GSM do
  @moduledoc """
  Check an SMS text before sending it. Needs no client and no network:

      MIX_ENV=test mix run -e "Unicom360.Examples.GSM.main()"
  """

  alias Unicom360.GSM

  def main, do: "It’s ready: order ZM4821" |> run() |> inspect() |> IO.puts()

  def run(text) do
    case GSM.validate_sms(text) do
      [] -> {:ok, GSM.units(text)}
      issues -> {:error, issues, GSM.non_gsm_characters(text)}
    end
  end
end
