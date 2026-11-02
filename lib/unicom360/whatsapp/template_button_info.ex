defmodule Unicom360.WhatsApp.TemplateButtonInfo do
  @moduledoc """
  A button of an approved template (`Unicom360.WhatsApp.TemplateInfo`): `index`, `type`
  (`"url"`, `"quick_reply"`, `"otp"`, ...; open), and `text`, `url` and `otp_type` when the
  type has them.
  """

  @fields [index: :any, type: :any, text: :any, url: :any, otp_type: :any]

  @type t :: %__MODULE__{
          index: non_neg_integer() | nil,
          type: String.t() | nil,
          text: String.t() | nil,
          url: String.t() | nil,
          otp_type: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct index: nil, type: nil, text: nil, url: nil, otp_type: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
