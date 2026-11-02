defmodule Unicom360.SMS.Result do
  @moduledoc """
  One recipient of an SMS send (canonical name `SmsResult`).

    * `message_id` - always a string; matches the delivery report's.
    * `status` - `"ACKNOWLEDGED"`, `"Invalid mobile number"`, or another value a later gateway
      sends (statuses are open).
    * `mobile_number` - the number as the gateway normalised it.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
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
