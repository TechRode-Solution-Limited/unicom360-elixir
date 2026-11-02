defmodule Unicom360.WhatsApp.TemplateButton do
  @moduledoc """
  A template recipient's button parameter.

      TemplateButton.url(0, "ZM-4821")         # the dynamic part of a URL button
      TemplateButton.quick_reply(0, "rate-5")  # a quick-reply button's payload

  Sent as `{"index", "type", "value"}`. A recipient may also give a map in that shape.
  """

  @type t :: %__MODULE__{index: non_neg_integer(), type: String.t(), value: String.t()}

  @enforce_keys [:index, :type, :value]
  defstruct [:index, :type, :value]

  @doc "A URL button: `value` fills the button's URL variable."
  @spec url(non_neg_integer(), String.t()) :: t()
  def url(index, value), do: %__MODULE__{index: index, type: "url", value: value}

  @doc "A quick-reply button: `value` is the payload returned when it is tapped."
  @spec quick_reply(non_neg_integer(), String.t()) :: t()
  def quick_reply(index, value), do: %__MODULE__{index: index, type: "quick_reply", value: value}

  @doc false
  @spec to_api(t() | map()) :: map()
  def to_api(%__MODULE__{index: index, type: type, value: value}),
    do: %{"index" => index, "type" => type, "value" => value}

  def to_api(value) when is_map(value), do: Unicom360.Params.compact(value)
end
