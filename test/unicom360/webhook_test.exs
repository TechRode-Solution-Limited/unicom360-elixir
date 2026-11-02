defmodule Unicom360.WebhookTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Unicom360.{Error, Webhook}

  # Throwaway test secret, not a credential.
  @secret "whsec_test_0123456789abcdefghijklmnopqrstuv"
  @body ~s({"created_at":"2026-10-24T09:30:00Z","data":{"message":"This is a test event."},"event":"webhook.test"})

  defp signature(timestamp, body, secret \\ @secret) do
    "sha256=" <>
      (:hmac
       |> :crypto.mac(:sha256, secret, "#{timestamp}.#{body}")
       |> Base.encode16(case: :lower))
  end

  defp signed_headers(body \\ @body, timestamp \\ System.os_time(:second)) do
    [
      {"x-unicom360-signature", signature(timestamp, body)},
      {"x-unicom360-timestamp", Integer.to_string(timestamp)},
      {"x-unicom360-delivery", "3001"},
      {"x-unicom360-event", "webhook.test"}
    ]
  end

  describe "verify/4" do
    test "uses the system clock and the five-minute tolerance by default" do
      assert Webhook.verify(@body, signed_headers(), @secret) == :ok

      stale = System.os_time(:second) - 301

      assert {:error, %Error{reason: :timestamp_out_of_tolerance}} =
               Webhook.verify(@body, signed_headers(@body, stale), @secret)
    end

    test "takes iodata" do
      assert Webhook.verify(["{", ~s("a":1), "}"], signed_headers(~s({"a":1})), @secret) == :ok
    end

    test "uses the first value of a repeated header" do
      timestamp = System.os_time(:second)

      headers = %{
        "X-Unicom360-Signature" => [signature(timestamp, @body), "sha256=nonsense"],
        "x-unicom360-timestamp" => [Integer.to_string(timestamp)]
      }

      assert Webhook.verify(@body, headers, @secret) == :ok
    end

    test "a timestamp too large for 64 bits is out of tolerance, without doing the arithmetic" do
      huge = String.duplicate("9", 2000)

      headers = [
        {"x-unicom360-signature", signature(huge, @body)},
        {"x-unicom360-timestamp", huge}
      ]

      assert {:error, %Error{reason: :timestamp_out_of_tolerance}} =
               Webhook.verify(@body, headers, @secret)
    end

    test "a trailing newline in a header is malformed, not valid" do
      timestamp = System.os_time(:second)

      assert {:error, %Error{reason: :invalid_timestamp}} =
               Webhook.verify(
                 @body,
                 [
                   {"x-unicom360-signature", signature(timestamp, @body)},
                   {"x-unicom360-timestamp", "#{timestamp}\n"}
                 ],
                 @secret
               )

      assert {:error, %Error{reason: :malformed_signature}} =
               Webhook.verify(
                 @body,
                 [
                   {"x-unicom360-signature", signature(timestamp, @body) <> "\n"},
                   {"x-unicom360-timestamp", "#{timestamp}"}
                 ],
                 @secret
               )
    end

    test "a nil tolerance cannot turn the check off" do
      assert_raise ArgumentError, ~r/tolerance/, fn ->
        Webhook.verify(@body, signed_headers(), @secret, tolerance: nil)
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, fn ->
        Webhook.verify(@body, signed_headers(), @secret, nope: 1)
      end
    end

    test "the error names its class and never includes the secret" do
      assert {:error, %Error{} = error} = Webhook.verify(@body, [], @secret)
      assert Error.class(error) == "SignatureVerificationError"
      refute inspect(error) =~ @secret
      refute Exception.message(error) =~ @secret
    end

    test "verify!/4 returns :ok or raises" do
      assert Webhook.verify!(@body, signed_headers(), @secret) == :ok
      assert_raise Error, ~r/missing_signature/, fn -> Webhook.verify!(@body, [], @secret) end
    end
  end

  describe "construct_event/4" do
    test "a verified body that is not an event is a base error" do
      for body <- ["", "[]", "not json", ~s({"event":1}), ~s({"data":{}})] do
        assert {:error, %Error{type: :unicom360_error} = error} =
                 Webhook.construct_event(body, signed_headers(body), @secret)

        assert Error.class(error) == "Unicom360Error"
      end
    end

    test "verification comes first" do
      assert {:error, %Error{reason: :missing_signature}} =
               Webhook.construct_event("not json", [], @secret)
    end

    test "a missing delivery header is a nil delivery_id" do
      timestamp = System.os_time(:second)

      headers = [
        {"x-unicom360-signature", signature(timestamp, @body)},
        {"x-unicom360-timestamp", Integer.to_string(timestamp)}
      ]

      assert {:ok, %Webhook.TestEvent{delivery_id: nil}} =
               Webhook.construct_event(@body, headers, @secret)
    end

    test "construct_event!/4 returns the event or raises" do
      assert %Webhook.TestEvent{delivery_id: "3001", data: %{message: "This is a test event."}} =
               Webhook.construct_event!(@body, signed_headers(), @secret)

      assert_raise Error, fn -> Webhook.construct_event!(@body, [], @secret) end
    end
  end

  describe "callbacks" do
    test "the bang variants" do
      assert %Webhook.SmsDeliveryReport{status: "DELIVERED"} =
               Webhook.parse_sms_callback!(~s({"message_id":"m","status":"DELIVERED"}))

      assert %Webhook.EmailDeliveryReport{message_id: "7"} =
               Webhook.parse_email_callback!(~s({"message_id":7}))

      assert_raise Error, ~r/not a JSON object/, fn -> Webhook.parse_sms_callback!("[]") end
      assert_raise Error, ~r/not a JSON object/, fn -> Webhook.parse_email_callback!("nope") end
    end
  end

  describe "BodyReader" do
    test "keeps the raw body, however many reads it takes" do
      conn = conn(:post, "/", "abcdef")

      assert {:more, "abc", conn} =
               Webhook.BodyReader.read_body(conn, length: 3, read_length: 3)

      assert conn.assigns.raw_body == "abc"
      assert {:ok, "def", conn} = Webhook.BodyReader.read_body(conn, length: 10)
      assert conn.assigns.raw_body == "abcdef"
    end

    test "works as Plug.Parsers' body_reader" do
      opts =
        Plug.Parsers.init(
          parsers: [:json],
          pass: ["*/*"],
          json_decoder: Jason,
          body_reader: {Webhook.BodyReader, :read_body, []}
        )

      conn =
        conn(:post, "/", ~s({"a":  1}))
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(opts)

      assert conn.body_params == %{"a" => 1}
      assert conn.assigns.raw_body == ~s({"a":  1})
    end
  end

  describe "Webhook.Plug" do
    defmodule Handler do
      @behaviour Unicom360.Webhook.Handler

      @impl true
      def handle_event(event, conn) do
        send(conn.assigns.test_pid, {:event, event})
        conn.assigns[:handler_result] || :ok
      end
    end

    defmodule SecretSource do
      def secret(value), do: value
    end

    defp call(conn, overrides \\ []) do
      opts = Webhook.Plug.init(Keyword.merge([secret: @secret, handler: Handler], overrides))
      conn |> assign(:test_pid, self()) |> Webhook.Plug.call(opts)
    end

    defp signed_conn(body \\ @body, headers \\ signed_headers()) do
      Enum.reduce(headers, conn(:post, "/", body), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)
    end

    test "a verified event reaches the handler and answers 200" do
      conn = signed_conn() |> call()

      assert conn.status == 200
      assert conn.halted
      assert_received {:event, %Webhook.TestEvent{delivery_id: "3001"}}
    end

    test "a verification failure answers 401 with the reason, and the handler is not called" do
      conn = conn(:post, "/", @body) |> call()

      assert conn.status == 401
      assert conn.resp_body == "missing_signature"
      assert conn.halted
      refute_received {:event, _}
    end

    test "a wrong secret answers 401" do
      conn = signed_conn() |> call(secret: "another-secret")

      assert conn.status == 401
      assert conn.resp_body == "signature_mismatch"
    end

    test "a stale delivery answers 401 under the plug's own tolerance" do
      timestamp = System.os_time(:second) - 60
      conn = signed_conn(@body, signed_headers(@body, timestamp)) |> call(tolerance: 30_000)

      assert conn.status == 401
      assert conn.resp_body == "timestamp_out_of_tolerance"
    end

    test "a verified body that is not an event answers 400" do
      conn = signed_conn("[]", signed_headers("[]")) |> call()
      assert conn.status == 400
    end

    test "a handler that does not return :ok answers 500" do
      conn = signed_conn() |> assign(:handler_result, {:error, :busy}) |> call()
      assert conn.status == 500
    end

    test "the secret can be read at request time from an {m, f, a}" do
      conn = signed_conn() |> call(secret: {SecretSource, :secret, [@secret]})
      assert conn.status == 200
    end

    test "uses conn.assigns.raw_body behind Plug.Parsers" do
      parsers =
        Plug.Parsers.init(
          parsers: [:json],
          pass: ["*/*"],
          json_decoder: Jason,
          body_reader: {Webhook.BodyReader, :read_body, []}
        )

      conn =
        signed_conn()
        |> put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(parsers)
        |> call()

      assert conn.status == 200
      assert_received {:event, %Webhook.TestEvent{}}
    end

    test "behind Plug.Parsers without the body reader: 401, and a log line says why" do
      parsers = Plug.Parsers.init(parsers: [:json], pass: ["*/*"], json_decoder: Jason)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn =
            signed_conn()
            |> put_req_header("content-type", "application/json")
            |> Plug.Parsers.call(parsers)
            |> call()

          assert conn.status == 401
        end)

      assert log =~ "Unicom360.Webhook.BodyReader"
    end

    test "a body over 1 MiB answers 413" do
      body = String.duplicate("a", 1_048_577)
      conn = signed_conn(body, signed_headers(body)) |> call()
      assert conn.status == 413
    end

    test "init/1 refuses unusable options" do
      for opts <- [
            [handler: Handler],
            [secret: @secret],
            [secret: "", handler: Handler],
            [secret: :nope, handler: Handler],
            [secret: @secret, handler: "nope"],
            [secret: @secret, handler: Handler, tolerance: nil],
            [secret: @secret, handler: Handler, nope: 1]
          ] do
        assert_raise ArgumentError, fn -> Webhook.Plug.init(opts) end
      end
    end

    test "a bad option's error never shows the secret" do
      error =
        assert_raise ArgumentError, fn ->
          Webhook.Plug.init(secret: @secret, handler: Handler, nope: 1)
        end

      assert Exception.message(error) =~ ":nope"
      refute Exception.message(error) =~ @secret
    end

    test "inspecting the plug's options never shows the secret" do
      shown = inspect(Webhook.Plug.init(secret: @secret, handler: Handler))
      refute shown =~ @secret
      assert shown =~ "[REDACTED]"
    end
  end
end
