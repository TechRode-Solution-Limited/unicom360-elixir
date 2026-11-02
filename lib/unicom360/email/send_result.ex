defmodule Unicom360.Email.SendResult do
  @moduledoc """
  The result of `Unicom360.Email.send/3` (canonical name `EmailSendResult`).

    * `api_reference`, `message` - from the envelope.
    * `results` - one `Unicom360.Email.Result` per recipient, **in the gateway's order, which is
      not the request's order past the tenth recipient**.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.Email.Result

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
  Every other result (for example `"Invalid email address"`), in response order.
  """
  @spec invalid(t()) :: [Result.t()]
  def invalid(%__MODULE__{results: results}),
    do: Enum.reject(results, &(&1.status == "ACKNOWLEDGED"))

  @doc """
  The first result for `address`, or `nil`. Ignores case and surrounding white space.
  """
  @spec by_address(t(), String.t()) :: Result.t() | nil
  def by_address(%__MODULE__{results: results}, address) do
    wanted = normalize(address)
    Enum.find(results, &(normalize(&1.email_address) == wanted))
  end

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(nil), do: ""
  defp normalize(value), do: value |> to_string() |> normalize()
end
