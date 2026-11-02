defmodule Unicom360.WhatsApp.TemplateList do
  @moduledoc """
  The result of `Unicom360.WhatsApp.templates/2` (canonical name `TemplateList`): `templates`, a
  list of `Unicom360.WhatsApp.TemplateInfo`, plus `api_reference`, `message`, `raw` and `extra`.
  """

  alias Unicom360.WhatsApp.TemplateInfo

  @type t :: %__MODULE__{
          api_reference: String.t() | nil,
          message: String.t() | nil,
          templates: [TemplateInfo.t()],
          raw: map(),
          extra: map()
        }

  defstruct api_reference: nil, message: nil, templates: [], raw: %{}, extra: %{}

  @doc false
  @spec from_envelope(map()) :: t()
  def from_envelope(json) do
    {data, extra} = Unicom360.Envelope.object(json, ["templates"])

    %__MODULE__{
      api_reference: json["api_reference"],
      message: json["message"],
      templates: Unicom360.Model.convert({:list, TemplateInfo}, data["templates"]) || [],
      raw: json,
      extra: extra
    }
  end

  @doc """
  The first template named `name` (and in `language`, when given), or `nil`.
  """
  @spec by_name(t(), String.t(), String.t() | nil) :: TemplateInfo.t() | nil
  def by_name(%__MODULE__{templates: templates}, name, language \\ nil) do
    Enum.find(templates, fn template ->
      template.name == name and (is_nil(language) or template.language == language)
    end)
  end
end
