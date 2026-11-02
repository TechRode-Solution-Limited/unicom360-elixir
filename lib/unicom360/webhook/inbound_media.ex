defmodule Unicom360.Webhook.InboundMedia do
  @moduledoc """
  The media of an inbound WhatsApp message: `id`, `mime_type` and `filename` (`nil` unless a
  document), plus `raw` and `extra`. A caption arrives in the message's `text`, not here.
  """

  @fields [id: :any, mime_type: :any, filename: :any]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          mime_type: String.t() | nil,
          filename: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct id: nil, mime_type: nil, filename: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
