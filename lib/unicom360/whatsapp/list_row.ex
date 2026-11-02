defmodule Unicom360.WhatsApp.ListRow do
  @moduledoc """
  A row of an interactive list message (`Unicom360.WhatsApp.Session.list/5`). The builder also
  takes maps.
  """

  @type t :: %__MODULE__{id: String.t(), title: String.t(), description: String.t() | nil}

  @enforce_keys [:id, :title]
  defstruct [:id, :title, :description]

  @doc "Builds a row, with an optional description."
  @spec new(String.t(), String.t(), String.t() | nil) :: t()
  def new(id, title, description \\ nil),
    do: %__MODULE__{id: id, title: title, description: description}

  @doc false
  @spec to_api(t() | map()) :: map()
  def to_api(%__MODULE__{id: id, title: title, description: description}),
    do: Unicom360.Params.compact(id: id, title: title, description: description)

  def to_api(row) when is_map(row), do: Unicom360.Params.compact(row)
end
