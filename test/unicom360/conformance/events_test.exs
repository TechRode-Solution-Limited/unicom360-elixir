defmodule Unicom360.Conformance.EventsTest do
  @moduledoc "webhooks/events.json: a signed delivery and the event it parses to."
  use ExUnit.Case, async: true

  alias Unicom360.Test.Conformance
  alias Unicom360.Webhook

  @kinds %{
    "message_status" => Webhook.MessageStatusEvent,
    "message_received" => Webhook.MessageReceivedEvent,
    "test" => Webhook.TestEvent,
    "unknown" => Webhook.UnknownEvent
  }

  for vector <- Conformance.vectors("webhooks/events.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector

      Conformance.check_keys(
        vector,
        ~w(id secret headers body_text now_unix tolerance expect),
        ~w(description)
      )

      expect = vector["expect"]
      Conformance.check_keys(expect, ~w(kind event delivery_id created_at data))

      assert {:ok, event} =
               Webhook.construct_event(vector["body_text"], vector["headers"], vector["secret"],
                 tolerance: Conformance.to_ms(vector["tolerance"]),
                 now: Conformance.to_ms(vector["now_unix"])
               )

      assert event.__struct__ == Map.fetch!(@kinds, expect["kind"])
      assert event.event == expect["event"]
      assert event.delivery_id == expect["delivery_id"]
      assert event.created_at == expect["created_at"]
      Conformance.assert_canonical_equal(expect["data"], Conformance.canonical(event.data))
    end
  end
end
