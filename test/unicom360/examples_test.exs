defmodule Unicom360.ExamplesTest do
  @moduledoc "The examples compile with the tests, and run here against canned responses."
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Unicom360.Examples
  alias Unicom360.Test.Conformance

  @canned Conformance.load("requests.json")["canned_responses"]

  # Answers the path's canned response from requests.json.
  defp canned_client do
    paths = %{
      "/api/v1/json/bulk/sms" => "sms.send",
      "/api/v1/json/bulk/email" => "email.send",
      "/api/v1/json/whatsapp/template" => "whatsapp.send_template",
      "/api/v1/json/whatsapp/session" => "whatsapp.send_session",
      "/api/v1/json/whatsapp/status" => "whatsapp.status",
      "/api/v1/json/whatsapp/templates" => "whatsapp.templates",
      "/api/v1/json/balance" => "balance.get",
      "/api/v1/json/balance/all" => "balance.all",
      "/health" => "health"
    }

    plug = fn conn ->
      http = Map.fetch!(@canned, Map.fetch!(paths, conn.request_path))

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(http["status"], http["body_text"])
    end

    Unicom360.client!(api_key: "k", plug: plug)
  end

  test "sms_send" do
    assert {:ok, "1764184470578998353", "ACKNOWLEDGED"} = Examples.SmsSend.run(canned_client())
  end

  test "sms_send handles an insufficient bundle" do
    plug = fn conn ->
      send_resp(conn, 200, ~s({"message":"INSUFFICIENT_BUNDLE","success":false}))
    end

    client = Unicom360.client!(api_key: "k", plug: plug)
    assert {:error, :top_up_needed} = Examples.SmsSend.run(client)
  end

  test "email_send" do
    assert {"1764184470578998353", "48213"} = Examples.EmailSend.run(canned_client())
  end

  test "whatsapp_send_template" do
    assert {1, 1, [{"12", "INVALID_NUMBER"}]} = Examples.WhatsAppSendTemplate.run(canned_client())
  end

  test "whatsapp_send_session" do
    results = Examples.WhatsAppSendSession.run(canned_client())
    assert length(results) == 7
    assert Enum.all?(results, &match?({:sent, _id}, &1))
  end

  test "whatsapp_status" do
    assert {"READ", nil} = Examples.WhatsAppStatus.run(canned_client())
  end

  test "whatsapp_templates" do
    assert {["order_ready", "login_code"], ["1", "2"]} =
             Examples.WhatsAppTemplates.run(canned_client())
  end

  test "balance_get" do
    assert {"1250", "SMS"} = Examples.BalanceGet.run(canned_client())
  end

  test "balance_all" do
    assert %{"SMS" => "1250", "EMAIL" => "4000", "WHATSAPP" => "37.5"} =
             Examples.BalanceAll.run(canned_client())
  end

  test "health" do
    assert {"ok", "0.1.0"} = Examples.Health.run(canned_client())
  end

  test "gsm" do
    assert {:ok, 1} = Examples.GSM.run("Hello")
    assert {:error, [:non_gsm], [{"’", 2}]} = Examples.GSM.run("It’s ready")
  end

  describe "webhook receivers" do
    @secret "throwaway-test-secret"
    @body ~s({"created_at":"2026-10-24T09:30:00Z","data":{"message":"Hi"},"event":"webhook.test"})

    setup do
      previous = System.get_env("UNICOM360_WEBHOOK_SECRET")
      System.put_env("UNICOM360_WEBHOOK_SECRET", @secret)

      on_exit(fn ->
        if previous,
          do: System.put_env("UNICOM360_WEBHOOK_SECRET", previous),
          else: System.delete_env("UNICOM360_WEBHOOK_SECRET")
      end)
    end

    defp signed(path) do
      timestamp = System.os_time(:second)

      mac =
        :hmac
        |> :crypto.mac(:sha256, @secret, "#{timestamp}.#{@body}")
        |> Base.encode16(case: :lower)

      conn(:post, path, @body)
      |> put_req_header("x-unicom360-signature", "sha256=#{mac}")
      |> put_req_header("x-unicom360-timestamp", Integer.to_string(timestamp))
      |> put_req_header("x-unicom360-delivery", "3001")
    end

    test "the Plug router accepts a signed delivery and refuses an unsigned one" do
      router = Examples.PlugWebhookRouter.init([])
      path = "/webhooks/unicom360/whatsapp"

      assert Examples.PlugWebhookRouter.call(signed(path), router).status == 200
      assert Examples.PlugWebhookRouter.call(conn(:post, path, @body), router).status == 401
    end

    test "the Plug router parses an SMS delivery report" do
      router = Examples.PlugWebhookRouter.init([])
      path = "/webhooks/unicom360/sms"

      conn = conn(:post, path, ~s({"message_id":"m","status":"DELIVERED"}))
      assert Examples.PlugWebhookRouter.call(conn, router).resp_body == "DELIVERED"
      assert Examples.PlugWebhookRouter.call(conn(:post, path, "[]"), router).status == 400
    end

    test "the Phoenix controller" do
      conn =
        signed("/")
        |> assign(:raw_body, @body)
        |> Examples.PhoenixWebhookController.whatsapp(%{})

      assert conn.status == 200

      conn =
        conn(:post, "/", @body)
        |> assign(:raw_body, @body)
        |> Examples.PhoenixWebhookController.whatsapp(%{})

      assert conn.status == 401
      assert conn.resp_body == "missing_signature"
    end
  end
end
