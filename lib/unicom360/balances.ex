defmodule Unicom360.Balances do
  @moduledoc """
  The result of `Unicom360.Balance.all/2` (canonical name `Balances`).

    * `message`, `client_id`, `client_name`.
    * `balances` - a map from bundle type (`"SMS"`, `"EMAIL"`, `"WHATSAPP"`, ...) to `Decimal`.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  @known ["status", "message", "balances", "client_id", "client_name"]

  @type t :: %__MODULE__{
          message: String.t() | nil,
          balances: %{optional(String.t()) => Decimal.t()},
          client_id: String.t() | nil,
          client_name: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message: nil, balances: %{}, client_id: nil, client_name: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_json(map(), map()) :: t()
  def from_json(json, exact) do
    balances =
      case exact["balances"] do
        balances when is_map(balances) ->
          Map.new(balances, fn {bundle, value} -> {bundle, Unicom360.Balance.decimal(value)} end)

        _ ->
          %{}
      end

    %__MODULE__{
      message: json["message"],
      balances: balances,
      client_id: json["client_id"],
      client_name: json["client_name"],
      raw: json,
      extra: Map.drop(json, @known)
    }
  end
end
