defmodule Unicom360 do
  @moduledoc """
  The official Elixir client for the [Unicom360](https://unicom360.com) API: SMS, email and
  WhatsApp over one JSON API.

      {:ok, client} = Unicom360.client()  # reads UNICOM360_API_KEY

      {:ok, result} =
        Unicom360.SMS.send(client, %{
          from: "Unicom360",
          to: "260971234567",
          message: "Your order ZM4821 is ready."
        })

  Every operation takes the client first and returns `{:ok, result}` or
  `{:error, %Unicom360.Error{}}`; each has a `!` variant that returns the result or raises.

  | Operation | Function | Returns |
  |---|---|---|
  | Send an SMS | `Unicom360.SMS.send/3` | `Unicom360.SMS.SendResult` |
  | Send an email | `Unicom360.Email.send/3` | `Unicom360.Email.SendResult` |
  | Send a WhatsApp template | `Unicom360.WhatsApp.send_template/3` | `Unicom360.WhatsApp.TemplateSendResult` |
  | Send a WhatsApp session message | `Unicom360.WhatsApp.send_session/3` | `Unicom360.WhatsApp.SessionSendResult` |
  | WhatsApp message status | `Unicom360.WhatsApp.status/3` | `Unicom360.WhatsApp.StatusResult` |
  | WhatsApp templates | `Unicom360.WhatsApp.templates/2` | `Unicom360.WhatsApp.TemplateList` |
  | One balance | `Unicom360.Balance.get/2` | `Unicom360.Balance` |
  | Every balance | `Unicom360.Balance.all/2` | `Unicom360.Balances` |
  | Health | `health/2` | `Unicom360.Health` |

  Webhooks and delivery reports are in `Unicom360.Webhook`, the opt-in GSM-7 helpers in
  `Unicom360.GSM`. There is no sandbox: every accepted send is real and billed.
  """

  alias Unicom360.{Client, Error, Health, HTTP}

  @version "0.1.0"
  @contract_version "0.1.0"

  @health %{method: :get, path: "/health", kind: :health, auth: false}

  @doc """
  The SDK's version.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  The version of the Unicom360 API contract (`openapi.yaml` and its conformance suite) this SDK
  targets.
  """
  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @doc """
  Builds a client. See `Unicom360.Client` for every option.

      {:ok, client} = Unicom360.client()
      {:ok, client} = Unicom360.client(api_key: "...", max_retries: 4)

  Returns `{:error, %Unicom360.Error{type: :configuration_error}}` when no API key is found or an
  option is unusable.
  """
  @spec client([Client.option()]) :: {:ok, Client.t()} | {:error, Error.t()}
  def client(opts \\ []), do: Client.new(opts)

  @doc """
  Like `client/1`, but returns the client or raises `Unicom360.Error`.
  """
  @spec client!([Client.option()]) :: Client.t()
  def client!(opts \\ []) do
    case client(opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc """
  Checks that the API is up (`GET /health`). Sends no API key.

  Options: `:timeout` (ms per attempt) and `:max_retries`.
  """
  @spec health(Client.t(), keyword()) :: {:ok, Health.t()} | {:error, Error.t()}
  def health(%Client{} = client, opts \\ []) do
    with {:ok, json, _text} <- HTTP.request(client, @health, nil, opts, safe: true) do
      {:ok, Health.from_map(json)}
    end
  end

  @doc """
  Like `health/2`, but returns the result or raises `Unicom360.Error`.
  """
  @spec health!(Client.t(), keyword()) :: Health.t()
  def health!(%Client{} = client, opts \\ []) do
    case health(client, opts) do
      {:ok, health} -> health
      {:error, error} -> raise error
    end
  end
end
