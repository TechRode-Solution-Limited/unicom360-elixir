defmodule Unicom360.Conformance.ResponsesTest do
  @moduledoc "responses.json: a canned HTTP response and the result or error it must produce."
  use ExUnit.Case, async: true

  alias Unicom360.Email
  alias Unicom360.SMS
  alias Unicom360.Test.Conformance
  alias Unicom360.WhatsApp.TemplateSendResult

  for vector <- Conformance.vectors("responses.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector

      Conformance.check_keys(
        vector,
        ~w(id operation http expect),
        ~w(description off_spec now_unix)
      )

      {plug, _requests} = Conformance.fake_plug([%{"http" => vector["http"]}])
      clock = vector["now_unix"] && fn -> Conformance.to_ms(vector["now_unix"]) end
      client = Conformance.client(plug, max_retries: 0, clock: clock)
      params = Conformance.sample_params(vector["operation"])

      case vector["expect"] do
        %{"error" => expected} = expect ->
          Conformance.check_keys(expect, ~w(error))
          assert {:error, error} = Conformance.call(client, vector["operation"], params)
          Conformance.assert_error(expected, error)
          assert error.attempts == 1
          assert error.raw_body == vector["http"]["body_text"]

        %{"result" => expected} = expect ->
          Conformance.check_keys(expect, ~w(result), ~w(helpers))
          assert {:ok, result} = Conformance.call(client, vector["operation"], params)
          Conformance.assert_canonical_equal(expected, Conformance.canonical(result))
          assert is_map(result.raw)
          check_helpers(vector["operation"], result, expect["helpers"])

        other ->
          flunk("an expect this harness does not understand: #{inspect(other)}")
      end
    end
  end

  defp check_helpers(_operation, _result, nil), do: :ok

  defp check_helpers("sms.send", result, helpers) do
    Conformance.check_keys(helpers, ~w(accepted invalid by_number))
    assert positions(result, SMS.SendResult.accepted(result)) == helpers["accepted"]
    assert positions(result, SMS.SendResult.invalid(result)) == helpers["invalid"]
    check_lookup(result, helpers["by_number"], &SMS.SendResult.by_number/2)
  end

  defp check_helpers("email.send", result, helpers) do
    Conformance.check_keys(helpers, ~w(accepted invalid by_address))
    assert positions(result, Email.SendResult.accepted(result)) == helpers["accepted"]
    assert positions(result, Email.SendResult.invalid(result)) == helpers["invalid"]
    check_lookup(result, helpers["by_address"], &Email.SendResult.by_address/2)
  end

  defp check_helpers("whatsapp.send_template", result, helpers) do
    Conformance.check_keys(helpers, ~w(accepted rejected by_number))
    assert positions(result, TemplateSendResult.accepted(result)) == helpers["accepted"]
    assert positions(result, TemplateSendResult.rejected(result)) == helpers["rejected"]
    check_lookup(result, helpers["by_number"], &TemplateSendResult.by_number/2)
  end

  defp check_helpers(operation, _result, helpers),
    do: flunk("helpers for #{operation}: #{inspect(helpers)}")

  defp check_lookup(result, lookups, lookup) do
    for {argument, position} <- lookups do
      found = lookup.(result, argument)
      actual = if found, do: position_of(result, found)
      assert actual == position, "lookup of #{inspect(argument)}"
    end
  end

  defp positions(result, items), do: Enum.map(items, &position_of(result, &1))

  defp position_of(result, item), do: Enum.find_index(result.results, &(&1 === item))
end
