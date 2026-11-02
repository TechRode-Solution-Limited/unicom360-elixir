defmodule Unicom360.WhatsApp.MessageError do
  @moduledoc """
  Why a WhatsApp message failed: Meta's error `code` (an integer, or `nil`) and its `message`.
  """

  @fields [code: :any, message: :any]

  @type t :: %__MODULE__{
          code: integer() | nil,
          message: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct code: nil, message: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
