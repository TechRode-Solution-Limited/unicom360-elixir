defmodule Unicom360.References do
  @moduledoc false
  # `user_reference_id` handling: whether a call is retry-safe (docs/sdk-design.md 10.1) and the
  # `auto_reference_ids` option (10.5).

  @doc false
  @spec present?(term()) :: boolean()
  def present?(reference) when is_binary(reference), do: String.trim(reference) != ""
  def present?(_reference), do: false

  @doc """
  Returns `"u360-"` followed by 32 lowercase hex characters: a random UUID v4 without dashes.
  """
  @spec generate() :: String.t()
  def generate do
    <<a::48, _version::4, b::12, _variant::2, c::62>> = :crypto.strong_rand_bytes(16)
    uuid = <<a::48, 4::4, b::12, 2::2, c::62>>
    "u360-" <> Base.encode16(uuid, case: :lower)
  end

  @doc """
  Adds a generated reference to an API body that has none, when the client asks for it.
  Returns the body and the generated values (for the debug log line).
  """
  @spec put_missing(Unicom360.Client.t(), map()) :: {map(), [String.t()]}
  def put_missing(%{auto_reference_ids: false}, body), do: {body, []}

  def put_missing(_client, body) do
    if has_reference?(body) do
      {body, []}
    else
      reference = generate()
      {Map.put(body, reference_key(body), reference), [reference]}
    end
  end

  @doc false
  @spec reference(map()) :: term()
  def reference(body), do: Map.get(body, "user_reference_id", Map.get(body, :user_reference_id))

  defp has_reference?(body), do: not is_nil(reference(body))

  # A map passed in API shape keeps its own key style.
  defp reference_key(body) do
    if Enum.any?(Map.keys(body), &is_atom/1) and not Enum.any?(Map.keys(body), &is_binary/1),
      do: :user_reference_id,
      else: "user_reference_id"
  end
end
