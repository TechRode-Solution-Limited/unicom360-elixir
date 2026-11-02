defmodule Unicom360.WhatsApp.MessageStatus do
  @moduledoc """
  The status of one WhatsApp message (canonical name `MessageStatus`).

    * `message_id`, `status` - `"ACCEPTED"`, `"SENT"`, `"DELIVERED"`, `"READ"`, `"FAILED"`,
      `"REJECTED"` or `"NOT_FOUND"` (open).
    * Except on `NOT_FOUND`: `user_reference_id`, `to`, `from`, `sent_at`, `delivered_at`,
      `read_at` (ISO 8601 strings, as received), `error` (a `Unicom360.WhatsApp.MessageError` or
      `nil`), `category`, `billable` and `refunded`.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.WhatsApp.MessageError

  @fields [
    message_id: :id,
    status: :any,
    user_reference_id: :any,
    to: :any,
    from: :any,
    sent_at: :any,
    delivered_at: :any,
    read_at: :any,
    error: {:model, MessageError},
    category: :any,
    billable: :any,
    refunded: :any
  ]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          status: String.t() | nil,
          user_reference_id: String.t() | nil,
          to: String.t() | nil,
          from: String.t() | nil,
          sent_at: String.t() | nil,
          delivered_at: String.t() | nil,
          read_at: String.t() | nil,
          error: MessageError.t() | nil,
          category: String.t() | nil,
          billable: boolean() | nil,
          refunded: boolean() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil,
            status: nil,
            user_reference_id: nil,
            to: nil,
            from: nil,
            sent_at: nil,
            delivered_at: nil,
            read_at: nil,
            error: nil,
            category: nil,
            billable: nil,
            refunded: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
