defmodule Unicom360.WhatsApp.TemplateBody do
  @moduledoc """
  A template recipient's body parameters: positional or named.

      TemplateBody.of(["Ada", "ZM-4821"])                 # {{1}}, {{2}}
      TemplateBody.named(%{"name" => "Ada", "time" => "10:30"})  # {{name}}, {{time}}

  A recipient may also give a plain list or map.
  """

  @type t :: %__MODULE__{values: [String.t()] | %{optional(String.t() | atom()) => String.t()}}

  @enforce_keys [:values]
  defstruct [:values]

  @doc "Positional parameters, sent as a JSON list."
  @spec of([String.t()]) :: t()
  def of(values) when is_list(values), do: %__MODULE__{values: values}

  @doc "Named parameters, sent as a JSON object."
  @spec named(map()) :: t()
  def named(values) when is_map(values), do: %__MODULE__{values: values}

  @doc false
  @spec to_api(t() | list() | map()) :: list() | map()
  def to_api(%__MODULE__{values: values}), do: values
  def to_api(values) when is_list(values) or is_map(values), do: values
end
