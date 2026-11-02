defmodule Unicom360.WhatsApp.TemplateResult do
  @moduledoc """
  One recipient of a template send (canonical name `TemplateResult`).

    * `message_id` - a string; `nil` unless the message was queued (or, with reason
      `"DUPLICATE_MSG_REF"`, the original message's id).
    * `to`, `user_reference_id` - strings: a rejected recipient echoes what the request sent,
      converted to a string.
    * `status` - `"ACKNOWLEDGED"` or `"REJECTED"` (open).
    * `reason` - why it was rejected (open; for example `"INVALID_NUMBER"`); `nil` when accepted.
    * `category` - the template's category.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  @fields [
    message_id: :id,
    to: :id,
    user_reference_id: :id,
    status: :any,
    reason: :any,
    category: :any
  ]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          to: String.t() | nil,
          user_reference_id: String.t() | nil,
          status: String.t() | nil,
          reason: String.t() | nil,
          category: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil,
            to: nil,
            user_reference_id: nil,
            status: nil,
            reason: nil,
            category: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
