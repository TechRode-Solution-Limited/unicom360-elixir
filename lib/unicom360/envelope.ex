defmodule Unicom360.Envelope do
  @moduledoc false
  # Helpers for the `{success, api_reference, message, data}` envelope and the result helpers.

  @envelope_keys ["success", "api_reference", "message", "data"]

  @doc false
  # For operations whose `data` is a list (SMS, email): the parsed list and the unknown members.
  @spec list(map(), (term() -> struct())) :: {[struct()], map()}
  def list(json, parse) do
    extra = Map.drop(json, @envelope_keys)

    case json["data"] do
      data when is_list(data) -> {Enum.map(data, parse), extra}
      data when is_map(data) -> {[], Map.merge(extra, data)}
      _ -> {[], extra}
    end
  end

  @doc false
  # For operations whose `data` is an object: the object and the unknown members, given the
  # data members the model reads.
  @spec object(map(), [String.t()]) :: {map(), map()}
  def object(json, known) do
    data = if is_map(json["data"]), do: json["data"], else: %{}
    {data, Map.merge(Map.drop(json, @envelope_keys), Map.drop(data, known))}
  end

  @doc false
  @spec by_number([struct()], atom(), String.t()) :: struct() | nil
  def by_number(results, field, number) do
    case digits(number) do
      "" -> Enum.find(results, &(Map.get(&1, field) == number))
      wanted -> Enum.find(results, &(digits(Map.get(&1, field)) == wanted))
    end
  end

  defp digits(value) when is_binary(value),
    do: for(<<c <- value>>, c in ?0..?9, into: "", do: <<c>>)

  defp digits(nil), do: ""
  defp digits(value), do: value |> to_string() |> digits()
end
