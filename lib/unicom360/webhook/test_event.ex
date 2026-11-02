defmodule Unicom360.Webhook.TestEvent do
  @moduledoc """
  A verified `webhook.test` webhook delivery, from `Unicom360.Webhook.construct_event/4`.

    * `event` - `"webhook.test"`.
    * `delivery_id` - the `X-Unicom360-Delivery` header (`nil` when absent). Deliveries are
      retried, so drop repeats by it.
    * `created_at` - an ISO 8601 string, as received.
    * `data` - a `Unicom360.Webhook.TestEventData`.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.Webhook.TestEventData

  @type t :: %__MODULE__{
          event: String.t(),
          delivery_id: String.t() | nil,
          created_at: String.t() | nil,
          data: TestEventData.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct event: "webhook.test",
            delivery_id: nil,
            created_at: nil,
            data: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(map(), String.t() | nil) :: t()
  def from_map(json, delivery_id) do
    %__MODULE__{
      event: json["event"],
      delivery_id: delivery_id,
      created_at: Unicom360.Model.string_or_nil(json["created_at"]),
      data: Unicom360.Model.convert({:model, TestEventData}, json["data"]),
      raw: json,
      extra: Map.drop(json, ["event", "created_at", "data"])
    }
  end
end
