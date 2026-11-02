defmodule Unicom360.Conformance.RequestsTest do
  @moduledoc "requests.json: each SDK call and the exact HTTP request it must make."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance

  @fixture Conformance.load("requests.json")

  test "there is a canned response for every operation" do
    assert Enum.sort(Map.keys(@fixture["canned_responses"])) ==
             Enum.sort(Conformance.operations())
  end

  for vector <- @fixture["vectors"] do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector
      Conformance.check_keys(vector, ~w(id operation params expect), ~w(description))

      expect = vector["expect"]

      Conformance.check_keys(
        expect,
        ~w(method path headers absent_headers user_agent_prefix json absent_keys)
      )

      canned = Map.fetch!(@fixture["canned_responses"], vector["operation"])
      {plug, requests} = Conformance.fake_plug([%{"http" => canned}])
      client = Conformance.client(plug, max_retries: 0)

      assert {:ok, _result} = Conformance.call(client, vector["operation"], vector["params"])

      assert [request] = requests.()
      assert request.method == expect["method"]
      assert request.path == expect["path"]
      assert request.query == ""

      headers = Map.new(request.headers, fn {name, value} -> {String.downcase(name), value} end)

      for {name, value} <- expect["headers"] do
        wanted = String.replace(value, "<KEY>", Conformance.api_key())
        assert headers[String.downcase(name)] == wanted, "header #{name}"
      end

      for name <- expect["absent_headers"] do
        refute Map.has_key?(headers, String.downcase(name)), "header #{name} must be absent"
      end

      assert String.starts_with?(headers["user-agent"], expect["user_agent_prefix"])

      if is_nil(expect["json"]) do
        assert request.body == ""
      else
        body = Jason.decode!(request.body)
        Conformance.assert_json_equal(expect["json"], body)

        for pointer <- expect["absent_keys"] do
          refute Conformance.pointer_exists?(body, pointer), "#{pointer} must be absent"
        end
      end
    end
  end
end
