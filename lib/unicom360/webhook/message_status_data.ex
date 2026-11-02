defmodule Unicom360.Webhook.MessageStatusData do
  @moduledoc """
  The `data` of a `message.status` event.

    * `message_id` - the id the send returned (a UUID).
    * `user_reference_id`, `channel`, `to`, `from`.
    * `status` - `"sent"`, `"delivered"`, `"read"` or `"failed"` (open).
    * `timestamp` - an ISO 8601 string, as received.
    * `error` - a `Unicom360.WhatsApp.MessageError` or `nil`.
    * `category`, `billable`.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.WhatsApp.MessageError

  @fields [
    message_id: :id,
    user_reference_id: :any,
    channel: :any,
    to: :any,
    from: :any,
    status: :any,
    timestamp: :any,
    error: {:model, MessageError},
    category: :any,
    billable: :any
  ]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          user_reference_id: String.t() | nil,
          channel: String.t() | nil,
          to: String.t() | nil,
          from: String.t() | nil,
          status: String.t() | nil,
          timestamp: String.t() | nil,
          error: MessageError.t() | nil,
          category: String.t() | nil,
          billable: boolean() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil,
            user_reference_id: nil,
            channel: nil,
            to: nil,
            from: nil,
            status: nil,
            timestamp: nil,
            error: nil,
            category: nil,
            billable: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
