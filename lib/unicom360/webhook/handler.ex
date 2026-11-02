if Code.ensure_loaded?(Plug.Conn) do
  defmodule Unicom360.Webhook.Handler do
    @moduledoc """
    The behaviour of the module `Unicom360.Webhook.Plug` calls with each verified event.

        defmodule MyApp.WhatsAppEvents do
          @behaviour Unicom360.Webhook.Handler

          @impl true
          def handle_event(%Unicom360.Webhook.MessageReceivedEvent{data: message}, _conn) do
            MyApp.Inbox.store(message.from, message.text)
            :ok
          end

          def handle_event(_event, _conn), do: :ok
        end

    Return `:ok` to answer 200. Anything else answers 500, and the gateway delivers the event
    again later. Answer quickly (hand slow work to a job queue), and drop repeats by the event's
    `delivery_id`.
    """

    @callback handle_event(event :: Unicom360.Webhook.event(), conn :: Plug.Conn.t()) :: term()
  end
end
