defmodule Unicom360.WhatsApp.TemplateRecipient do
  @moduledoc """
  One recipient of a template send.

      TemplateRecipient.new("260971234567",
        user_reference_id: "inv-42",
        header: TemplateHeader.image("https://example.com/receipts/ZM-4821.png"),
        body: TemplateBody.of(["Ada", "ZM-4821"]),
        buttons: [TemplateButton.url(0, "ZM-4821")]
      )

    * `to` (required) - the recipient's WhatsApp number.
    * `user_reference_id` - your reference for this recipient. A template send is safe to retry
      only when every recipient has one.
    * `header` - a `Unicom360.WhatsApp.TemplateHeader`, a string or a map.
    * `body` - a `Unicom360.WhatsApp.TemplateBody`, a list or a map.
    * `buttons` - a list of `Unicom360.WhatsApp.TemplateButton` (or maps).
    * `otp` - the code, for an `AUTHENTICATION` template.

  A recipient may also be a plain map or keyword list with these keys.
  """

  alias Unicom360.WhatsApp.{TemplateBody, TemplateButton, TemplateHeader}

  @type t :: %__MODULE__{
          to: String.t(),
          user_reference_id: String.t() | nil,
          header: TemplateHeader.t() | String.t() | map() | nil,
          body: TemplateBody.t() | list() | map() | nil,
          buttons: [TemplateButton.t() | map()] | nil,
          otp: String.t() | nil
        }

  @enforce_keys [:to]
  defstruct [:to, :user_reference_id, :header, :body, :buttons, :otp]

  @keys [:user_reference_id, :header, :body, :buttons, :otp]

  @doc """
  Builds a recipient. `opts` takes `:user_reference_id`, `:header`, `:body`, `:buttons` and
  `:otp`.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(to, opts \\ []) do
    struct!(__MODULE__, [to: to] ++ Keyword.validate!(opts, @keys))
  end

  @doc false
  @spec to_api(t() | map() | keyword()) :: map()
  def to_api(%__MODULE__{} = recipient), do: recipient |> Map.from_struct() |> to_api()

  def to_api(recipient) do
    params =
      Unicom360.Params.build!(
        recipient,
        [:to],
        @keys,
        "Unicom360.WhatsApp.send_template/3 recipient"
      )

    params
    |> update("header", &TemplateHeader.to_api/1)
    |> update("body", &TemplateBody.to_api/1)
    |> update("buttons", fn buttons -> Enum.map(buttons, &TemplateButton.to_api/1) end)
  end

  defp update(map, key, fun) do
    case map do
      %{^key => value} -> %{map | key => fun.(value)}
      _ -> map
    end
  end
end
