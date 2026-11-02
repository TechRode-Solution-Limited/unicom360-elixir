defmodule Unicom360.Webhook.EmailDeliveryReport do
  @moduledoc """
  An email delivery report, from `Unicom360.Webhook.parse_email_callback/1`: `message_id` (a
  string, though the wire sends a number), `status` (`"SENT"`, `"DELIVERED"`, `"FAILED"`; open),
  `email_address`, `message`, `raw` and `extra`.

  **Unsigned and never retried**: anyone can post one, so treat it as a hint.
  """

  @fields [message_id: :id, status: :any, email_address: :any, message: :any]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          status: String.t() | nil,
          email_address: String.t() | nil,
          message: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil, status: nil, email_address: nil, message: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
