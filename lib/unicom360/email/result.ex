defmodule Unicom360.Email.Result do
  @moduledoc """
  One recipient of an email send (canonical name `EmailResult`).

    * `message_id` - always a string, even though the delivery report sends it as a number.
    * `status` - `"ACKNOWLEDGED"`, `"Invalid email address"`, or another value (open).
    * `email_address` - the address.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  @fields [message_id: :id, status: :any, email_address: :any]

  @type t :: %__MODULE__{
          message_id: String.t() | nil,
          status: String.t() | nil,
          email_address: String.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct message_id: nil, status: nil, email_address: nil, raw: %{}, extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
end
