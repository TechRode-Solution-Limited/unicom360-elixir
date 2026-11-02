defmodule Unicom360.Health do
  @moduledoc """
  The result of `Unicom360.health/2` (canonical name `Health`): `status` (`"ok"`), `timestamp`
  (an ISO 8601 string, as received), `version`, `environment`, `raw` and `extra`.
  """

  @fields [status: :any, timestamp: :any, version: :any, environment: :any]

  @type t :: %__MODULE__{
          status: String.t() | nil,
          timestamp: String.t() | nil,
          version: String.t() | nil,
          environment: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct status: nil, timestamp: nil, version: nil, environment: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
