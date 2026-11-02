defmodule Unicom360.WhatsApp.StatusResult do
  @moduledoc """
  The result of `Unicom360.WhatsApp.status/3` (canonical name `StatusResult`): `results`, one
  `Unicom360.WhatsApp.MessageStatus` per distinct id asked for, plus `api_reference`, `message`,
  `raw` and `extra`.
  """

  alias Unicom360.WhatsApp.MessageStatus

  @type t :: %__MODULE__{
          api_reference: String.t() | nil,
          message: String.t() | nil,
          results: [MessageStatus.t()],
          raw: map(),
          extra: map()
        }

  defstruct api_reference: nil, message: nil, results: [], raw: %{}, extra: %{}

  @doc false
  @spec from_envelope(map()) :: t()
  def from_envelope(json) do
    {data, extra} = Unicom360.Envelope.object(json, ["results"])

    %__MODULE__{
      api_reference: json["api_reference"],
      message: json["message"],
      results: Unicom360.Model.convert({:list, MessageStatus}, data["results"]) || [],
      raw: json,
      extra: extra
    }
  end

  @doc "The status of `message_id` (exact match), or `nil`."
  @spec by_id(t(), String.t()) :: MessageStatus.t() | nil
  def by_id(%__MODULE__{results: results}, message_id),
    do: Enum.find(results, &(&1.message_id == message_id))
end
