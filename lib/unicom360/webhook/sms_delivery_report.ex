defmodule Unicom360.Webhook.SmsDeliveryReport do
  @moduledoc """
  An SMS delivery report, from `Unicom360.Webhook.parse_sms_callback/1`: `message_id`, `status`
  (`"SENT"`, `"DELIVERED"`, `"FAILED"`, `"UNKNOWN_ERROR"`; open), `mobile_number`, `raw` and
  `extra`.

  **Unsigned and never retried**: anyone can post one, so treat it as a hint.
  """

  @fields [message_id: :id, status: :any, mobile_number: :any]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          status: String.t() | nil,
          mobile_number: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil, status: nil, mobile_number: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
