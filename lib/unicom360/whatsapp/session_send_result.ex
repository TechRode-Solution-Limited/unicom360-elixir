defmodule Unicom360.WhatsApp.SessionSendResult do
  @moduledoc """
  The result of `Unicom360.WhatsApp.send_session/3` (canonical name `SessionSendResult`).

    * `api_reference`, `message` - from the envelope.
    * `message_id` - the message's id (a string); pass it to `Unicom360.WhatsApp.status/3`, or as
      a later message's `:reply_to`.
    * `to`, `user_reference_id`, `status` (`"ACKNOWLEDGED"`), `category` (`"SERVICE"`).
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  @data_fields [
    message_id: :id,
    to: :id,
    user_reference_id: :id,
    status: :any,
    category: :any
  ]

  @type t :: %__MODULE__{
          api_reference: String.t() | nil,
          message: String.t() | nil,
          message_id: String.t() | nil,
          to: String.t() | nil,
          user_reference_id: String.t() | nil,
          status: String.t() | nil,
          category: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct api_reference: nil,
            message: nil,
            message_id: nil,
            to: nil,
            user_reference_id: nil,
            status: nil,
            category: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_envelope(map()) :: t()
  def from_envelope(json) do
    {data, extra} = Unicom360.Envelope.object(json, Unicom360.Model.api_names(@data_fields))

    values =
      for {field, kind} <- @data_fields,
          do: {field, Unicom360.Model.convert(kind, data[Atom.to_string(field)])}

    struct(
      __MODULE__,
      [api_reference: json["api_reference"], message: json["message"], raw: json, extra: extra] ++
        values
    )
  end
end
