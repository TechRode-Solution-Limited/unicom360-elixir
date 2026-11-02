defmodule Unicom360.WhatsApp.ReplyButton do
  @moduledoc """
  A reply button of an interactive buttons message (`Unicom360.WhatsApp.Session.buttons/4`).
  The builder also takes `{id, title}` tuples and maps.
  """

  @type t :: %__MODULE__{id: String.t(), title: String.t()}

  @enforce_keys [:id, :title]
  defstruct [:id, :title]

  @doc "Builds a reply button."
  @spec new(String.t(), String.t()) :: t()
  def new(id, title), do: %__MODULE__{id: id, title: title}

  @doc false
  @spec to_api(t() | {String.t(), String.t()} | map()) :: map()
  def to_api(%__MODULE__{id: id, title: title}), do: %{"id" => id, "title" => title}
  def to_api({id, title}), do: %{"id" => id, "title" => title}
  def to_api(button) when is_map(button), do: Unicom360.Params.compact(button)
end
