defmodule Unicom360.Webhook.TestEventData do
  @moduledoc "The `data` of a `webhook.test` event: `message`, `raw` and `extra`."

  @fields [message: :any]

  @type t :: %__MODULE__{message: String.t() | nil, raw: map(), extra: map()}

  defstruct message: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
