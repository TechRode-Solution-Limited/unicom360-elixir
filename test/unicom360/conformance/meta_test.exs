defmodule Unicom360.Conformance.MetaTest do
  @moduledoc "The vendored fixtures are unmodified, and every fixture file has a harness."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance

  defp version do
    Conformance.fixtures_dir()
    |> Path.join("VERSION")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [key, value] = String.split(line, "=", parts: 2)
      {key, value}
    end)
  end

  defp files do
    dir = Conformance.fixtures_dir()

    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  test "the tree hash matches VERSION (what scripts/sync-conformance --check does)" do
    listing =
      files()
      |> Enum.reject(&(&1 == "VERSION"))
      |> Enum.map_join(fn name ->
        bytes = File.read!(Path.join(Conformance.fixtures_dir(), name))
        hash = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
        "#{hash}  #{name}\n"
      end)

    actual = :sha256 |> :crypto.hash(listing) |> Base.encode16(case: :lower)
    assert version()["source"] == "unicom360-openapi"
    assert actual == version()["sha256"]
  end

  test "the fixtures target this contract version" do
    assert version()["version"] == Unicom360.contract_version()
    assert version()["tag"] == "v#{Unicom360.contract_version()}"

    for name <- Map.keys(Conformance.files()) do
      assert Conformance.load(name)["version"] == Unicom360.contract_version()
    end
  end

  test "every fixture file has a harness" do
    found =
      files()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.reject(&String.starts_with?(&1, "schema/"))
      |> Enum.sort()

    assert found == Enum.sort(Map.keys(Conformance.files()))
  end

  test "vector ids are unique per file" do
    for name <- Map.keys(Conformance.files()) do
      ids = Enum.map(Conformance.vectors(name), & &1["id"])
      assert ids != [], name
      assert ids == Enum.uniq(ids), name
    end
  end
end
