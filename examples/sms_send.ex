defmodule Unicom360.Examples.SmsSend do
  @moduledoc """
  Send an SMS. Every accepted send is real and billed: there is no sandbox.

      UNICOM360_API_KEY=... MIX_ENV=test mix run -e "Unicom360.Examples.SmsSend.main()"
  """

  alias Unicom360.SMS.SendResult

  def main do
    client = Unicom360.client!()
    client |> run() |> inspect() |> IO.puts()
  end

  def run(client) do
    Unicom360.SMS.send(client, %{
      from: "Unicom360",
      to: ["260971234567", "260961234567"],
      message: "Your order ZM4821 is ready.",
      # Optional: makes the send safe to retry, and lets the gateway refuse a repeat.
      user_reference_id: "order-10421"
    })
    |> case do
      {:ok, result} ->
        # Results are not in request order past the tenth recipient: look them up.
        recipient = SendResult.by_number(result, "260971234567")
        {:ok, result.api_reference, recipient && recipient.status}

      {:error, %Unicom360.Error{code: "INSUFFICIENT_BUNDLE"}} ->
        {:error, :top_up_needed}

      {:error, %Unicom360.Error{} = error} ->
        {:error, Unicom360.Error.class(error), error.code, error.message, error.api_reference}
    end
  end
end
