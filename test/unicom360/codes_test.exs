defmodule Unicom360.CodesTest do
  use ExUnit.Case, async: true
  doctest Unicom360.Codes

  alias Unicom360.Codes

  test "anything that is not a string is UNKNOWN" do
    for value <- [nil, 1, ["a"], %{}] do
      assert Codes.normalize(value) == "UNKNOWN"
    end
  end

  test "a code followed by a colon needs white space to count" do
    assert Codes.normalize("NEW_CODE: detail") == "NEW_CODE"
    assert Codes.normalize("NEW_CODE:detail") == "UNKNOWN"
    assert Codes.normalize("NEW CODE: detail") == "UNKNOWN"
    assert Codes.normalize("NEW_CODE:\tdetail") == "NEW_CODE"
    assert Codes.normalize("NEW_CODE: detail") == "NEW_CODE"
  end

  test "a newline never sneaks past the patterns" do
    assert Codes.normalize("CODE\n") == "UNKNOWN"
  end

  test "every documented code has a constant" do
    assert Codes.insufficient_bundle() == "INSUFFICIENT_BUNDLE"
    assert Codes.rate_limit_exceeded() == "RATE_LIMIT_EXCEEDED"
    assert Codes.unknown() == "UNKNOWN"

    for code <- Codes.known() do
      assert apply(Codes, code |> String.downcase() |> String.to_atom(), []) == code
    end
  end
end
