defmodule Unicom360.Balance do
  @moduledoc """
  Account balances (`POST /api/v1/json/balance` and `/balance/all`), and the struct
  `get/2` returns (canonical name `Balance`).

      {:ok, %Unicom360.Balance{balance: balance}} = Unicom360.Balance.get(client)
      {:ok, whatsapp} = Unicom360.Balance.get(client, bundle_type: "WHATSAPP")
      {:ok, %Unicom360.Balances{balances: balances}} = Unicom360.Balance.all(client)

  Balances are `Decimal`s, exactly as the gateway sent them. Bundle types: `"SMS"` (the
  default), `"SMS_INTERNATIONAL"`, `"EMAIL"` and `"WHATSAPP"`.

  Fields of `%Unicom360.Balance{}`: `message`, `balance` (a `Decimal`), `bundle_type`,
  `client_id`, `client_name`, `raw` and `extra`.
  """

  alias Unicom360.{Balances, Client, HTTP}

  @get %{method: :post, path: "/api/v1/json/balance", kind: :balance, auth: true}
  @all %{method: :post, path: "/api/v1/json/balance/all", kind: :balance, auth: true}

  @known ["status", "message", "balance", "bundle_type", "client_id", "client_name"]

  @type t :: %__MODULE__{
          message: String.t() | nil,
          balance: Decimal.t() | nil,
          bundle_type: String.t() | nil,
          client_id: String.t() | nil,
          client_name: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message: nil,
            balance: nil,
            bundle_type: nil,
            client_id: nil,
            client_name: nil,
            raw: %{},
            extra: %{}

  @doc "The SMS bundle type."
  @spec sms() :: String.t()
  def sms, do: "SMS"

  @doc "The international SMS bundle type."
  @spec sms_international() :: String.t()
  def sms_international, do: "SMS_INTERNATIONAL"

  @doc "The email bundle type."
  @spec email() :: String.t()
  def email, do: "EMAIL"

  @doc "The WhatsApp bundle type."
  @spec whatsapp() :: String.t()
  def whatsapp, do: "WHATSAPP"

  @doc """
  One balance: the SMS bundle, or the bundle given as `bundle_type:`.

  Options: `:bundle_type`, `:timeout` (ms per attempt) and `:max_retries`. A refusal (for
  example `code: "CLIENT_NOT_FOUND"`) is an `:api_error` with no `api_reference`.
  """
  @spec get(Client.t(), keyword()) :: {:ok, t()} | {:error, Unicom360.Error.t()}
  def get(%Client{} = client, opts \\ []) do
    {bundle, opts} = Keyword.pop(opts, :bundle_type)
    body = if is_nil(bundle), do: %{}, else: %{"bundle_type" => bundle}

    with {:ok, json, text} <- HTTP.request(client, @get, body, opts, safe: true) do
      exact = decimals(text)

      {:ok,
       %__MODULE__{
         message: json["message"],
         balance: decimal(exact["balance"]),
         bundle_type: json["bundle_type"],
         client_id: json["client_id"],
         client_name: json["client_name"],
         raw: json,
         extra: Map.drop(json, @known)
       }}
    end
  end

  @doc """
  Like `get/2`, but returns the balance or raises `Unicom360.Error`.
  """
  @spec get!(Client.t(), keyword()) :: t()
  def get!(%Client{} = client, opts \\ []) do
    case get(client, opts) do
      {:ok, balance} -> balance
      {:error, error} -> raise error
    end
  end

  @doc """
  Every balance, as a map from bundle type to `Decimal`.

  Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec all(Client.t(), keyword()) :: {:ok, Balances.t()} | {:error, Unicom360.Error.t()}
  def all(%Client{} = client, opts \\ []) do
    with {:ok, json, text} <- HTTP.request(client, @all, %{}, opts, safe: true) do
      {:ok, Balances.from_json(json, decimals(text))}
    end
  end

  @doc """
  Like `all/2`, but returns the balances or raises `Unicom360.Error`.
  """
  @spec all!(Client.t(), keyword()) :: Balances.t()
  def all!(%Client{} = client, opts \\ []) do
    case all(client, opts) do
      {:ok, balances} -> balances
      {:error, error} -> raise error
    end
  end

  # The body again, with every number exact (a float would round 0.1 and long values).
  defp decimals(text), do: Jason.decode!(text, floats: :decimals)

  @doc false
  @spec decimal(term()) :: Decimal.t() | term()
  def decimal(value) when is_integer(value), do: Decimal.new(value)
  def decimal(value), do: value
end
