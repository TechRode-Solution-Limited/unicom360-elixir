defmodule Unicom360.SMS.SendResult do
  @moduledoc """
  The result of `Unicom360.SMS.send/3` (canonical name `SmsSendResult`).

    * `api_reference` - the gateway's reference for the request; quote it to support.
    * `message` - the gateway's message (`"successful"`).
    * `results` - one `Unicom360.SMS.Result` per recipient, **in the gateway's order, which is
      not the request's order past the tenth recipient**.
    * `raw` - the JSON object the result was parsed from, unmodified.
    * `extra` - every member of the envelope this version does not model.
  """

  alias Unicom360.SMS.Result

  @type t :: %__MODULE__{
          api_reference: String.t() | nil,
          message: String.t() | nil,
          results: [Result.t()],
          raw: map(),
          extra: map()
        }

  defstruct api_reference: nil, message: nil, results: [], raw: %{}, extra: %{}

  @doc false
  @spec from_envelope(map()) :: t()
  def from_envelope(json) do
    {results, extra} = Unicom360.Envelope.list(json, &Result.from_map/1)

    %__MODULE__{
      api_reference: json["api_reference"],
      message: json["message"],
      results: results,
      raw: json,
      extra: extra
    }
  end

  @doc """
  The results the gateway accepted (status exactly `"ACKNOWLEDGED"`), in response order.
  """
  @spec accepted(t()) :: [Result.t()]
  def accepted(%__MODULE__{results: results}),
    do: Enum.filter(results, &(&1.status == "ACKNOWLEDGED"))

  @doc """
  Every other result (for example `"Invalid mobile number"`), in response order.
  """
  @spec invalid(t()) :: [Result.t()]
  def invalid(%__MODULE__{results: results}),
    do: Enum.reject(results, &(&1.status == "ACKNOWLEDGED"))

  @doc """
  The first result for `number`, or `nil`.

  Compares digits only, so `"+260 97 123 4567"` finds `"260971234567"`. Local formats are not
  expanded: pass the international form.
  """
  @spec by_number(t(), String.t()) :: Result.t() | nil
  def by_number(%__MODULE__{results: results}, number),
    do: Unicom360.Envelope.by_number(results, :mobile_number, number)
end
