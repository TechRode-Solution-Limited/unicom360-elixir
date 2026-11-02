defmodule Unicom360.WhatsApp.Session do
  @moduledoc """
  Builders for WhatsApp session messages, sent with `Unicom360.WhatsApp.send_session/3` inside
  the 24-hour customer service window.

      alias Unicom360.WhatsApp.Session

      Session.text("260971234567", "Your order is ready.", reply_to: inbound_wamid)
      Session.image("260971234567", "https://example.com/receipt.png", caption: "Your receipt")
      Session.buttons("260971234567", "Collect today or deliver?", [
        {"collect", "Collect"},
        {"deliver", "Deliver"}
      ])

  Every builder takes the keyword options `:from` (your WhatsApp number), `:user_reference_id`
  (makes the send safe to retry), `:callback_url` and, all but `reaction/4`, `:reply_to`.
  `:reply_to` and a reaction's `message_id` take either a `message_id` a send returned or the
  `wamid.` id of an inbound message, exactly as a `message.received` webhook delivers it.

  The SDK checks no lengths or limits; the gateway answers an invalid message with an
  `:invalid_request_error`.
  """

  alias Unicom360.Params
  alias Unicom360.WhatsApp.{ListSection, ReplyButton, SessionMessage}

  @common [:from, :reply_to, :user_reference_id, :callback_url]

  @doc """
  A text message. Options: the common ones.
  """
  @spec text(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def text(to, text, opts \\ []), do: build(to, "text", %{"text" => text}, opts, [])

  @doc """
  An image, with an optional `:caption`.
  """
  @spec image(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def image(to, url, opts \\ []), do: media(to, "image", url, opts, [:caption])

  @doc """
  A video, with an optional `:caption`.
  """
  @spec video(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def video(to, url, opts \\ []), do: media(to, "video", url, opts, [:caption])

  @doc """
  A document, with an optional `:caption` and `:filename`.
  """
  @spec document(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def document(to, url, opts \\ []), do: media(to, "document", url, opts, [:caption, :filename])

  @doc """
  An audio file.
  """
  @spec audio(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def audio(to, url, opts \\ []), do: media(to, "audio", url, opts, [])

  @doc """
  A sticker.
  """
  @spec sticker(String.t(), String.t(), keyword()) :: SessionMessage.t()
  def sticker(to, url, opts \\ []), do: media(to, "sticker", url, opts, [])

  @doc """
  An interactive message with up to three reply buttons, each a
  `Unicom360.WhatsApp.ReplyButton`, an `{id, title}` tuple or a map. Options: `:header`,
  `:footer` and the common ones.
  """
  @spec buttons(
          String.t(),
          String.t(),
          [ReplyButton.t() | {String.t(), String.t()} | map()],
          keyword()
        ) ::
          SessionMessage.t()
  def buttons(to, body, buttons, opts \\ []) do
    {own, opts} = split(opts, [:header, :footer])

    interactive =
      Params.compact(
        type: "button",
        header: own[:header],
        body: body,
        footer: own[:footer],
        buttons: Enum.map(buttons, &ReplyButton.to_api/1)
      )

    build(to, "interactive", %{"interactive" => interactive}, opts, [])
  end

  @doc """
  An interactive list: `button` is the text of the button that opens it, `sections` a list of
  `Unicom360.WhatsApp.ListSection` (or maps). Options: `:header`, `:footer` and the common ones.
  """
  @spec list(String.t(), String.t(), String.t(), [ListSection.t() | map()], keyword()) ::
          SessionMessage.t()
  def list(to, body, button, sections, opts \\ []) do
    {own, opts} = split(opts, [:header, :footer])

    interactive =
      Params.compact(
        type: "list",
        header: own[:header],
        body: body,
        footer: own[:footer],
        button: button,
        sections: Enum.map(sections, &ListSection.to_api/1)
      )

    build(to, "interactive", %{"interactive" => interactive}, opts, [])
  end

  @doc """
  A location pin. Options: `:name`, `:address` and the common ones.
  """
  @spec location(String.t(), number(), number(), keyword()) :: SessionMessage.t()
  def location(to, latitude, longitude, opts \\ []) do
    {own, opts} = split(opts, [:name, :address])

    location =
      Params.compact(
        latitude: latitude,
        longitude: longitude,
        name: own[:name],
        address: own[:address]
      )

    build(to, "location", %{"location" => location}, opts, [])
  end

  @doc """
  Contact cards, each a map in Meta's contact shape
  (`%{"name" => %{"formatted_name" => ...}, "phones" => [...]}`), sent as given.
  """
  @spec contacts(String.t(), [map()], keyword()) :: SessionMessage.t()
  def contacts(to, contacts, opts \\ []) when is_list(contacts),
    do: build(to, "contacts", %{"contacts" => contacts}, opts, [])

  @doc """
  A reaction to a message. An empty `emoji` (`""`) removes your reaction. Options: `:from`,
  `:user_reference_id` and `:callback_url` (a reaction takes no `:reply_to`).
  """
  @spec reaction(String.t(), String.t(), String.t(), keyword()) :: SessionMessage.t()
  def reaction(to, message_id, emoji, opts \\ []) do
    reaction = %{"message_id" => message_id, "emoji" => emoji}
    build(to, "reaction", %{"reaction" => reaction}, opts, [:reply_to])
  end

  defp media(to, type, url, opts, fields) do
    {own, opts} = split(opts, fields)
    media = Params.compact([url: url] ++ Enum.map(fields, &{&1, own[&1]}))
    build(to, type, %{"media" => media}, opts, [])
  end

  defp split(opts, fields), do: Keyword.split(opts, fields)

  defp build(to, type, content, opts, refused) do
    opts = Keyword.validate!(opts, @common -- refused)

    %SessionMessage{
      to: to,
      type: type,
      content: content,
      from: opts[:from],
      reply_to: opts[:reply_to],
      user_reference_id: opts[:user_reference_id],
      callback_url: opts[:callback_url]
    }
  end
end
