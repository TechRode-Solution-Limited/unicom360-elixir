defmodule Unicom360.Webhook.UnknownEvent do
  @moduledoc """
  A verified webhook delivery of an event this version does not know. Never an error.

    * `event` - the event's name.
    * `delivery_id` - the `X-Unicom360-Delivery` header (`nil` when absent).
    * `created_at` - an ISO 8601 string, as received.
    * `data` - the raw JSON.
    * `raw` - the JSON object.
  """

  @type t :: %__MODULE__{
          event: String.t(),
          delivery_id: String.t() | nil,
          created_at: String.t() | nil,
          data: term(),
          raw: map()
        }

  @enforce_keys [:event]
  defstruct [:event, :delivery_id, :created_at, :data, raw: %{}]

  @doc false
  @spec from_map(map(), String.t() | nil) :: t()
  def from_map(json, delivery_id) do
    %__MODULE__{
      event: json["event"],
      delivery_id: delivery_id,
      created_at: Unicom360.Model.string_or_nil(json["created_at"]),
      data: json["data"],
      raw: json
    }
  end
end
