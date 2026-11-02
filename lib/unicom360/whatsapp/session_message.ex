defmodule Unicom360.WhatsApp.SessionMessage do
  @moduledoc """
  A WhatsApp session message, built with `Unicom360.WhatsApp.Session` and sent with
  `Unicom360.WhatsApp.send_session/3`.

    * `to` - the recipient's WhatsApp number.
    * `type` - `"text"`, `"image"`, `"video"`, `"document"`, `"audio"`, `"sticker"`,
      `"interactive"`, `"location"`, `"contacts"` or `"reaction"`.
    * `content` - the type's own field, in the API's shape (`%{"text" => "Hi"}`,
      `%{"media" => %{"url" => ...}}`, ...).
    * `from`, `reply_to`, `user_reference_id`, `callback_url` - the common optional fields.

  The struct is plain data: change a common field with `%{message | user_reference_id: "s-1"}`.
  """

  @type t :: %__MODULE__{
          to: String.t(),
          type: String.t(),
          content: %{optional(String.t()) => term()},
          from: String.t() | nil,
          reply_to: String.t() | nil,
          user_reference_id: String.t() | nil,
          callback_url: String.t() | nil
        }

  @enforce_keys [:to, :type, :content]
  defstruct [:to, :type, :content, :from, :reply_to, :user_reference_id, :callback_url]

  @doc false
  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{} = message) do
    Unicom360.Params.compact(
      to: message.to,
      type: message.type,
      from: message.from,
      reply_to: message.reply_to,
      user_reference_id: message.user_reference_id,
      callback_url: message.callback_url
    )
    |> Map.merge(message.content)
  end
end
