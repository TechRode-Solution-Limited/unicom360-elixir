defmodule Unicom360.Examples.WebhookHandler do
  @moduledoc """
  What the webhook receivers below call with each verified event. Deliveries are retried on any
  non-2xx, so answer quickly (hand slow work to a job queue) and drop repeats by `delivery_id`.
  """

  @behaviour Unicom360.Webhook.Handler

  require Logger

  alias Unicom360.Webhook.{MessageReceivedEvent, MessageStatusEvent, TestEvent, UnknownEvent}

  @impl true
  def handle_event(%MessageStatusEvent{delivery_id: delivery_id, data: data}, _conn) do
    Logger.info("delivery #{delivery_id}: message #{data.message_id} is #{data.status}")
    :ok
  end

  def handle_event(%MessageReceivedEvent{delivery_id: delivery_id, data: message}, _conn) do
    # A media caption arrives in `text`; an interactive reply's chosen title too.
    Logger.info("delivery #{delivery_id}: a #{message.type} message arrived")
    :ok
  end

  def handle_event(%TestEvent{data: data}, _conn) do
    Logger.info("test event: #{data.message}")
    :ok
  end

  # An event this version of the SDK does not know: never an error.
  def handle_event(%UnknownEvent{event: event}, _conn) do
    Logger.info("unknown event #{event}")
    :ok
  end
end
