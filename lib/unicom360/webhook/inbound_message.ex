defmodule Unicom360.Webhook.InboundMessage do
  @moduledoc """
  The `data` of a `message.received` event.

    * `message_id` - Meta's `wamid.` id; pass it as `:reply_to` or to a reaction.
    * `channel`, `from` (the customer), `to` (your number).
    * `type` - `"text"`, `"image"`, `"interactive"`, ... (open).
    * `text` - the text, a media caption, or the chosen title of an interactive or button reply.
    * `media` - a `Unicom360.Webhook.InboundMedia` or `nil`.
    * `payload` - Meta's object, set only for location, contacts (`%{"contacts" => [...]}`),
      reaction, sticker and unsupported messages; otherwise `nil`.
    * `reply_to` - the `wamid.` of the message replied to, or `nil`. An interactive reply's button
      or row id is not passed on.
    * `timestamp`, `window_expires_at` - ISO 8601 strings, as received.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.Webhook.InboundMedia

  @fields [
    message_id: :id,
    channel: :any,
    from: :any,
    to: :any,
    type: :any,
    text: :any,
    media: {:model, InboundMedia},
    payload: :any,
    reply_to: :any,
    timestamp: :any,
    window_expires_at: :any
  ]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          channel: String.t() | nil,
          from: String.t() | nil,
          to: String.t() | nil,
          type: String.t() | nil,
          text: String.t() | nil,
          media: InboundMedia.t() | nil,
          payload: map() | nil,
          reply_to: String.t() | nil,
          timestamp: String.t() | nil,
          window_expires_at: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil,
            channel: nil,
            from: nil,
            to: nil,
            type: nil,
            text: nil,
            media: nil,
            payload: nil,
            reply_to: nil,
            timestamp: nil,
            window_expires_at: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
