defmodule Unicom360.Model do
  @moduledoc false
  # Builds result structs from decoded JSON: the typed fields, `raw` (the JSON object, unmodified)
  # and `extra` (every member the struct does not model, so a field the gateway adds tomorrow is
  # readable today).

  @typedoc """
  How one field is read: `:any` as received, `:id` as a string (numbers are converted),
  `{:model, module}` a nested model, `{:list, module}` a list of nested models. A field whose
  API name differs from the struct field is `{api_name, kind}`.
  """
  @type kind :: :any | :id | {:model, module()} | {:list, module()}
  @type field_spec :: {atom(), kind() | {String.t(), kind()}}

  @doc false
  @spec decode(module(), [field_spec()], term()) :: struct()
  def decode(module, fields, map) when is_map(map) do
    {values, names} =
      Enum.map_reduce(fields, [], fn {field, spec}, names ->
        {name, kind} = name_and_kind(field, spec)
        {{field, convert(kind, Map.get(map, name))}, [name | names]}
      end)

    struct(module, values ++ [raw: map, extra: Map.drop(map, names)])
  end

  def decode(module, _fields, other), do: struct(module, raw: other, extra: %{})

  @doc false
  @spec api_names([field_spec()]) :: [String.t()]
  def api_names(fields) do
    Enum.map(fields, fn {field, spec} -> field |> name_and_kind(spec) |> elem(0) end)
  end

  defp name_and_kind(_field, {name, kind}) when is_binary(name), do: {name, kind}
  defp name_and_kind(field, kind), do: {Atom.to_string(field), kind}

  @doc false
  @spec convert(kind(), term()) :: term()
  def convert(_kind, nil), do: nil
  def convert(:any, value), do: value
  def convert(:id, value), do: id(value)
  def convert({:model, module}, value) when is_map(value), do: module.from_map(value)
  def convert({:model, _module}, value), do: value

  def convert({:list, module}, values) when is_list(values),
    do: Enum.map(values, &module.from_map/1)

  def convert({:list, _module}, value), do: value

  @doc false
  @spec id(term()) :: term()
  def id(value) when is_integer(value), do: Integer.to_string(value)
  def id(value) when is_float(value), do: float_to_string(value)
  def id(value), do: value

  @doc false
  @spec string_or_nil(term()) :: String.t() | nil
  def string_or_nil(value) when is_binary(value), do: value
  def string_or_nil(_value), do: nil

  # The shortest text that reads back as the same float, without a trailing ".0" for whole
  # numbers (as JavaScript's String(n) writes them).
  defp float_to_string(value) do
    if value == Float.round(value) and abs(value) < 1.0e15 do
      value |> trunc() |> Integer.to_string()
    else
      Float.to_string(value)
    end
  end
end
