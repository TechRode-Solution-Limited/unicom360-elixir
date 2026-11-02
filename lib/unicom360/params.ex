defmodule Unicom360.Params do
  @moduledoc false
  # Turns a caller's map or keyword list (atom keys) into the API's JSON object (string keys).
  # A key the operation does not take, or a required key that is missing or nil, raises
  # ArgumentError; an optional key that is nil is left out (unset fields are absent, never null).
  # Values are never checked or changed: the gateway validates them.

  @doc false
  @spec build!(term(), [atom()], [atom()], String.t()) :: %{optional(String.t()) => term()}
  def build!(params, required, optional, what) do
    params = to_map!(params, what)

    case Map.keys(params) -- (required ++ optional) do
      [] -> :ok
      unknown -> raise ArgumentError, "#{what}: unknown keys #{inspect(unknown)}"
    end

    case Enum.filter(required, &is_nil(Map.get(params, &1))) do
      [] -> :ok
      missing -> raise ArgumentError, "#{what}: missing required keys #{inspect(missing)}"
    end

    for {key, value} <- params, not is_nil(value), into: %{}, do: {Atom.to_string(key), value}
  end

  @doc false
  @spec to_map!(term(), String.t()) :: %{optional(atom()) => term()}
  def to_map!(params, what) when is_list(params) do
    if Keyword.keyword?(params) do
      # The first value of a repeated key wins, as in Keyword.get/2.
      params |> Enum.reverse() |> Map.new()
    else
      raise ArgumentError, "#{what}: expected a map or a keyword list, got: #{inspect(params)}"
    end
  end

  def to_map!(%{__struct__: _} = params, what) do
    raise ArgumentError, "#{what}: expected a map or a keyword list, got: #{inspect(params)}"
  end

  def to_map!(params, what) when is_map(params) do
    if Enum.all?(Map.keys(params), &is_atom/1) do
      params
    else
      raise ArgumentError, "#{what}: expected atom keys, got: #{inspect(Map.keys(params))}"
    end
  end

  def to_map!(params, what) do
    raise ArgumentError, "#{what}: expected a map or a keyword list, got: #{inspect(params)}"
  end

  @doc false
  @spec compact(keyword() | map()) :: map()
  def compact(pairs) do
    for {key, value} <- pairs, not is_nil(value), into: %{}, do: {to_string(key), value}
  end
end
