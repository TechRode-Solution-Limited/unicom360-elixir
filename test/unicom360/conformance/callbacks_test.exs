defmodule Unicom360.Conformance.CallbacksTest do
  @moduledoc "callbacks.json: an unsigned SMS or email delivery report and its parsed form."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance
  alias Unicom360.Webhook

  for vector <- Conformance.vectors("callbacks.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector
      Conformance.check_keys(vector, ~w(id kind body_text expect), ~w(description off_spec))

      parsed =
        case vector["kind"] do
          "sms" -> Webhook.parse_sms_callback(vector["body_text"])
          "email" -> Webhook.parse_email_callback(vector["body_text"])
          other -> flunk("an unknown callback kind: #{inspect(other)}")
        end

      case vector["expect"] do
        %{"error" => true} = expect ->
          Conformance.check_keys(expect, ~w(error))
          assert {:error, %Unicom360.Error{type: :unicom360_error}} = parsed

        %{"result" => expected} = expect ->
          Conformance.check_keys(expect, ~w(result))
          assert {:ok, report} = parsed
          assert is_binary(report.message_id)
          Conformance.assert_canonical_equal(expected, Conformance.canonical(report))

        other ->
          flunk("an expect this harness does not understand: #{inspect(other)}")
      end
    end
  end
end
