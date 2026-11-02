defmodule Unicom360.VersionTest do
  use ExUnit.Case, async: true

  test "version/0 matches mix.exs" do
    assert Unicom360.version() == Mix.Project.config()[:version]
    assert Unicom360.version() == "0.1.0"
  end

  test "the CHANGELOG has a section for this version" do
    changelog = File.read!("CHANGELOG.md")
    assert changelog =~ "## [#{Unicom360.version()}]"
    assert changelog =~ "[#{Unicom360.version()}]: "
  end

  test "the README targets this contract version" do
    assert File.read!("README.md") =~ "Unicom360 API contract v#{Unicom360.contract_version()}"
  end

  test "every Elixir block in the README parses" do
    blocks =
      ~r/```elixir\n(.*?)```/s
      |> Regex.scan(File.read!("README.md"), capture: :all_but_first)
      |> List.flatten()

    assert length(blocks) > 10

    for block <- blocks do
      assert {:ok, _quoted} = Code.string_to_quoted(block), "does not parse:\n#{block}"
    end
  end

  test "the README's install line allows this version" do
    [major, minor, _patch] = String.split(Unicom360.version(), ".")
    assert File.read!("README.md") =~ ~s({:unicom360, "~> #{major}.#{minor}"})
  end
end
