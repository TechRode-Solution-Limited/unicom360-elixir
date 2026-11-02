defmodule Unicom360.Conformance.RetriesTest do
  @moduledoc "retries.json: responses and transport failures, the attempts, sleeps and outcome."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance

  # Every vector runs at both ends of the jitter range and in the middle.
  @randoms [0.0, 0.5, 0.999999]

  for vector <- Conformance.vectors("retries.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector

      Conformance.check_keys(
        vector,
        ~w(id operation params now_unix config steps expect),
        ~w(description)
      )

      Conformance.check_keys(vector["config"], ~w(max_retries max_retry_wait))
      Conformance.check_keys(vector["expect"], ~w(attempts sleeps outcome))

      for random <- @randoms do
        run(vector, random)
      end
    end
  end

  defp run(vector, random) do
    expect = vector["expect"]
    time = Conformance.fake_time(Conformance.to_ms(vector["now_unix"]))
    {plug, requests} = Conformance.fake_plug(vector["steps"])

    client =
      Conformance.client(plug,
        max_retries: vector["config"]["max_retries"],
        max_retry_wait: Conformance.to_ms(vector["config"]["max_retry_wait"]),
        clock: time.clock,
        sleeper: time.sleeper,
        random: fn -> random end
      )

    outcome = Conformance.call(client, vector["operation"], vector["params"])

    assert length(requests.()) == expect["attempts"], "attempts with random #{random}"

    sleeps = time.sleeps.()
    assert length(sleeps) == length(expect["sleeps"]), "sleeps #{inspect(sleeps)}"

    for {ms, range} <- Enum.zip(sleeps, expect["sleeps"]) do
      Conformance.check_keys(range, ~w(min max))
      seconds = ms / 1000
      assert seconds >= range["min"] - 1.0e-6, "#{seconds} s below #{inspect(range)}"
      assert seconds <= range["max"] + 1.0e-6, "#{seconds} s above #{inspect(range)}"
    end

    check_outcome(expect["outcome"], outcome, expect["attempts"])
  end

  defp check_outcome(%{"kind" => "result"} = expected, outcome, _attempts) do
    Conformance.check_keys(expected, ~w(kind))
    assert {:ok, _result} = outcome
  end

  defp check_outcome(%{"kind" => "error"} = expected, outcome, attempts) do
    Conformance.check_keys(expected, ~w(kind type class code http_status))
    assert {:error, error} = outcome
    assert Atom.to_string(error.type) == expected["type"]
    assert Unicom360.Error.class(error) == expected["class"]
    assert error.code == expected["code"]
    assert error.http_status == expected["http_status"]
    assert error.attempts == attempts
  end

  defp check_outcome(other, _outcome, _attempts),
    do: flunk("an outcome this harness does not understand: #{inspect(other)}")
end
