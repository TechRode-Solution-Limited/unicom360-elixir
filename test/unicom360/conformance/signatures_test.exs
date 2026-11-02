defmodule Unicom360.Conformance.SignaturesTest do
  @moduledoc "webhooks/signatures.json: a signed (or tampered) delivery and the verify outcome."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance
  alias Unicom360.Webhook

  for vector <- Conformance.vectors("webhooks/signatures.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector

      Conformance.check_keys(
        vector,
        ~w(id secret headers body_base64 body_text now_unix tolerance expect),
        ~w(description)
      )

      body = Base.decode64!(vector["body_base64"])
      assert body == vector["body_text"]

      opts = [
        tolerance: Conformance.to_ms(vector["tolerance"]),
        now: Conformance.to_ms(vector["now_unix"])
      ]

      outcome = Webhook.verify(body, vector["headers"], vector["secret"], opts)

      # The same delivery, as the list of pairs a Plug.Conn holds.
      pairs = Enum.to_list(vector["headers"])
      assert Webhook.verify(body, pairs, vector["secret"], opts) == outcome

      case vector["expect"] do
        %{"valid" => true} = expect ->
          Conformance.check_keys(expect, ~w(valid))
          assert outcome == :ok

        %{"valid" => false, "reason" => reason} = expect ->
          Conformance.check_keys(expect, ~w(valid reason))
          assert {:error, %Unicom360.Error{} = error} = outcome
          assert error.type == :signature_verification_error
          assert Unicom360.Error.class(error) == "SignatureVerificationError"
          assert Atom.to_string(error.reason) == reason

        other ->
          flunk("an expect this harness does not understand: #{inspect(other)}")
      end
    end
  end
end
