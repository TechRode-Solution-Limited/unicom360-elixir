defmodule Unicom360.WhatsApp.ListSection do
  @moduledoc """
  A section of an interactive list message (`Unicom360.WhatsApp.Session.list/5`): rows of
  `Unicom360.WhatsApp.ListRow`, with an optional title. The builder also takes maps.
  """

  alias Unicom360.WhatsApp.ListRow

  @type t :: %__MODULE__{rows: [ListRow.t() | map()], title: String.t() | nil}

  @enforce_keys [:rows]
  defstruct [:rows, :title]

  @doc "Builds a section, with an optional title."
  @spec new([ListRow.t() | map()], String.t() | nil) :: t()
  def new(rows, title \\ nil), do: %__MODULE__{rows: rows, title: title}

  @doc false
  @spec to_api(t() | map()) :: map()
  def to_api(%__MODULE__{rows: rows, title: title}),
    do: Unicom360.Params.compact(title: title, rows: Enum.map(rows, &ListRow.to_api/1))

  def to_api(section) when is_map(section) do
    section
    |> Unicom360.Params.compact()
    |> Map.update("rows", [], fn rows -> Enum.map(rows, &ListRow.to_api/1) end)
  end
end
