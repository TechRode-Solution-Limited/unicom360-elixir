defmodule Unicom360.Conformance.GSM7Test do
  @moduledoc "gsm7.json: a text and every GSM helper's answer."
  use ExUnit.Case, async: true

  alias Unicom360.GSM
  alias Unicom360.Test.Conformance

  @fixture Conformance.load("gsm7.json")

  test "the file's constants" do
    Conformance.check_keys(
      @fixture,
      ~w(version description charset max_length unit_length vectors)
    )

    assert GSM.charset() == @fixture["charset"]
    assert GSM.max_length() == @fixture["max_length"]
    assert GSM.unit_length() == @fixture["unit_length"]
  end

  for vector <- @fixture["vectors"] do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector

      Conformance.check_keys(
        vector,
        ~w(id text is_gsm7 length units non_gsm validate),
        ~w(description)
      )

      text = vector["text"]
      assert GSM.gsm7?(text) == vector["is_gsm7"]
      assert GSM.length(text) == vector["length"]
      assert GSM.units(text) == vector["units"]

      expected =
        Enum.map(vector["non_gsm"], fn entry ->
          Conformance.check_keys(entry, ~w(char index))
          {entry["char"], entry["index"]}
        end)

      assert GSM.non_gsm_characters(text) == expected
      assert Enum.map(GSM.validate_sms(text), &Atom.to_string/1) == vector["validate"]
    end
  end
end
