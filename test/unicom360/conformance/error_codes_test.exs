defmodule Unicom360.Conformance.ErrorCodesTest do
  @moduledoc "error-codes.json: a raw server message and its normalised code."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance

  for vector <- Conformance.vectors("error-codes.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector
      Conformance.check_keys(vector, ~w(id message code source), ~w(note description))
      assert Unicom360.Codes.normalize(vector["message"]) == vector["code"]
    end
  end
end
