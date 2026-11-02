defmodule Unicom360.TransportTest do
  use ExUnit.Case, async: true

  alias Unicom360.{Error, TransportError}
  alias Unicom360.WhatsApp.{Session, TemplateRecipient}

  @sms %{from: "Unicom360", to: "260971234567", message: "Hello"}
  @ok %{
    "api_reference" => "r",
    "success" => true,
    "message" => "successful",
    "data" => []
  }

  defp client(plug, options \\ []) do
    Unicom360.client!(
      [
        api_key: "k",
        plug: plug,
        sleeper: fn _ms -> :ok end,
        random: fn -> 0.0 end
      ] ++ options
    )
  end

  # Req 0.7 takes a module with run/1 and deprecates functions; Req 0.5 and 0.6 take only a
  # function.
  defp adapter(module) do
    version = :req |> Application.spec(:vsn) |> to_string()
    if Version.match?(version, ">= 0.7.0"), do: module, else: &module.run/1
  end

  defp failing_then_ok(reason) do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    plug = fn conn ->
      case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
        0 -> Req.Test.transport_error(conn, reason)
        _ -> Req.Test.json(conn, @ok)
      end
    end

    {plug, fn -> Agent.get(attempts, & &1) end}
  end

  describe "classifying Req's transport errors" do
    for reason <- [:econnrefused, :nxdomain, :ehostunreach, :enetunreach] do
      test "#{reason} was never sent, so an unsafe send is retried" do
        {plug, attempts} = failing_then_ok(unquote(reason))
        assert {:ok, _} = Unicom360.SMS.send(client(plug), @sms)
        assert attempts.() == 2
      end
    end

    test ":timeout may have been sent: an unsafe send is not retried, and it is a timeout" do
      {plug, attempts} = failing_then_ok(:timeout)

      assert {:error, %Error{type: :timeout_error, attempts: 1} = error} =
               Unicom360.SMS.send(client(plug), @sms)

      assert Error.class(error) == "APITimeoutError"
      assert Error.connection_error?(error)
      assert %Req.TransportError{reason: :timeout} = error.cause
      assert attempts.() == 1
    end

    test ":closed may have been sent: an unsafe send is not retried" do
      {plug, attempts} = failing_then_ok(:closed)

      assert {:error, %Error{type: :connection_error, attempts: 1} = error} =
               Unicom360.SMS.send(client(plug), @sms)

      assert Error.class(error) == "APIConnectionError"
      assert attempts.() == 1
    end

    test ":closed on a safe send is retried" do
      {plug, attempts} = failing_then_ok(:closed)
      params = Map.put(@sms, :user_reference_id, "order-1")
      assert {:ok, _} = Unicom360.SMS.send(client(plug), params)
      assert attempts.() == 2
    end

    test "an unknown reason counts as sent" do
      {plug, attempts} = failing_then_ok(:eacces)
      assert {:error, %Error{type: :connection_error}} = Unicom360.SMS.send(client(plug), @sms)
      assert attempts.() == 1
    end
  end

  describe "a custom adapter stating the facts with Unicom360.TransportError" do
    defmodule NotSent do
      def run(request) do
        {request, %TransportError{reason: :custom, sent: false, timeout: true}}
      end
    end

    defmodule Sent do
      def run(request) do
        {request, %TransportError{reason: :custom, sent: true, timeout: false}}
      end
    end

    test "sent: false, timeout: true is retried and classed as a timeout" do
      {:ok, sleeps} = Agent.start_link(fn -> 0 end)

      client =
        Unicom360.client!(
          api_key: "k",
          req_options: [adapter: adapter(NotSent)],
          sleeper: fn _ms -> Agent.update(sleeps, &(&1 + 1)) end,
          random: fn -> 0.0 end
        )

      assert {:error, %Error{type: :timeout_error, attempts: 3} = error} =
               Unicom360.SMS.send(client, @sms)

      assert %TransportError{reason: :custom} = error.cause
      assert error.message =~ "transport failure"
      assert Agent.get(sleeps, & &1) == 2
    end

    test "sent: true is not retried on an unsafe send" do
      client = Unicom360.client!(api_key: "k", req_options: [adapter: adapter(Sent)])

      assert {:error, %Error{type: :connection_error, attempts: 1}} =
               Unicom360.SMS.send(client, @sms)
    end
  end

  describe "real sockets" do
    # The transport errors below come from Req and Finch themselves, not from a fake.
    defp closed_port do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)
      port
    end

    # Accepts every connection and hands it to `fun`.
    defp server(fun) do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(socket)

      start_supervised!(
        {Task,
         fn ->
           Stream.repeatedly(fn -> :gen_tcp.accept(socket) end)
           |> Enum.each(fn {:ok, connection} -> fun.(connection) end)
         end}
      )

      port
    end

    defp real_client(port, options) do
      Unicom360.client!(
        options ++
          [
            api_key: "k",
            base_url: "http://127.0.0.1:#{port}",
            sleeper: fn _ms -> :ok end,
            random: fn -> 0.0 end
          ]
      )
    end

    test "a refused connection was never sent: an unsafe send is retried, then fails" do
      port = closed_port()
      test_pid = self()

      client =
        real_client(port,
          max_retries: 1,
          sleeper: fn ms -> send(test_pid, {:slept, ms}) end
        )

      assert {:error, %Error{type: :connection_error, attempts: 2} = error} =
               Unicom360.SMS.send(client, @sms)

      assert_received {:slept, 0}
      assert %Req.TransportError{reason: :econnrefused} = error.cause
      assert error.message =~ "request failed"
    end

    test "a server that never answers times out, per call, and is not retried" do
      port = server(fn _connection -> Process.sleep(:infinity) end)
      client = real_client(port, [])

      assert {:error, %Error{type: :timeout_error, attempts: 1} = error} =
               Unicom360.SMS.send(client, @sms, timeout: 50)

      assert %Req.TransportError{reason: :timeout} = error.cause
    end

    test "a connection closed before the response may have been sent: not retried" do
      port =
        server(fn connection ->
          {:ok, _request} = :gen_tcp.recv(connection, 0)
          :gen_tcp.close(connection)
        end)

      assert {:error, %Error{type: :connection_error, attempts: 1} = error} =
               Unicom360.SMS.send(real_client(port, []), @sms)

      assert %Req.TransportError{reason: :closed} = error.cause
    end

    test "a real response goes through, with the headers on the wire" do
      test_pid = self()

      port =
        server(fn connection ->
          {:ok, request} = :gen_tcp.recv(connection, 0)
          send(test_pid, {:request, request})
          body = ~s({"status":"ok"})

          :ok =
            :gen_tcp.send(
              connection,
              "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
            )
        end)

      assert {:ok, %Unicom360.Health{status: "ok"}} = Unicom360.health(real_client(port, []))
      assert_received {:request, request}
      assert request =~ "GET /health HTTP/1.1"
      assert request =~ ~r/user-agent: unicom360-elixir/i
      refute request =~ ~r/x-api-key/i
    end
  end

  describe "the options a request is sent with" do
    defmodule Capture do
      def run(request) do
        send(self(), {:options, request.options})
        {request, Req.Response.new(status: 200, body: ~s({"status":"ok"}))}
      end
    end

    defp capturing(options \\ []) do
      Unicom360.client!([api_key: "k", req_options: [adapter: adapter(Capture)]] ++ options)
    end

    test "the client's timeouts" do
      assert {:ok, _} = Unicom360.health(capturing(timeout: 5_000, connect_timeout: 1_000))
      assert_received {:options, options}
      assert options[:receive_timeout] == 5_000
      assert options[:connect_options][:timeout] == 1_000
      assert options[:retry] == false
      assert options[:redirect] == false
    end

    test "a per-call timeout" do
      assert {:ok, _} = Unicom360.health(capturing(), timeout: 123)
      assert_received {:options, options}
      assert options[:receive_timeout] == 123
    end

    test "other connect options are kept, and :finch is passed instead of them" do
      client =
        Unicom360.client!(
          api_key: "k",
          req_options: [adapter: adapter(Capture), connect_options: [protocols: [:http1]]]
        )

      assert {:ok, _} = Unicom360.health(client)
      assert_received {:options, options}
      assert options[:connect_options][:protocols] == [:http1]
      assert options[:connect_options][:timeout] == 10_000
    end
  end

  test "a Req.Test stub works as the README says" do
    client = Unicom360.client!(api_key: "test", plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        success: true,
        message: "successful",
        api_reference: "1",
        data: [%{message_id: "m-1", status: "ACKNOWLEDGED", mobile_number: "260971234567"}]
      })
    end)

    assert {:ok, %{results: [%{message_id: "m-1"}]}} = Unicom360.SMS.send(client, @sms)
  end

  describe "the response" do
    test "a redirect is not followed: it is an APIStatusError and the key goes nowhere else" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        Agent.update(calls, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("location", "https://evil.example/steal")
        |> Plug.Conn.send_resp(302, "")
      end

      assert {:error, %Error{type: :api_status_error, http_status: 302} = error} =
               Unicom360.SMS.send(client(plug), @sms)

      assert Error.class(error) == "APIStatusError"
      assert Error.status_error?(error)
      assert error.message == "HTTP 302 Found"
      assert error.headers["location"] == ["https://evil.example/steal"]
      assert Agent.get(calls, & &1) == 1
    end

    test "an unknown status gets a generated message" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 418, "") end

      assert {:error, %Error{type: :api_status_error, message: "HTTP 418"}} =
               Unicom360.SMS.send(client(plug), @sms)
    end

    test "a message of the wrong type gets a generated message" do
      plug = fn conn -> Req.Test.json(conn, %{success: false, message: 42}) end

      assert {:error, %Error{type: :api_error, code: "UNKNOWN", message: message}} =
               Unicom360.SMS.send(client(plug), @sms)

      assert is_binary(message) and message != ""
    end

    test "a message list holding a non-string gets a generated message on a 400" do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, ~s({"message":["a",1],"success":false}))
      end

      assert {:error, %Error{type: :invalid_request_error, code: "UNKNOWN", message: message}} =
               Unicom360.SMS.send(client(plug), @sms)

      assert message == "HTTP 400 Bad Request"
    end

    test "error fields: headers, raw body, data, original_message_id and results" do
      body =
        ~s({"message":"DUPLICATE_MSG_REF","success":false,"api_reference":"r","data":{"message_id":"m-1"}})

      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-request-id", "abc")
        |> Plug.Conn.send_resp(200, body)
      end

      message = Session.text("260971234567", "Hello")

      assert {:error, %Error{} = error} =
               Unicom360.WhatsApp.send_session(client(plug), message)

      assert Error.class(error) == "DuplicateReferenceError"
      assert error.original_message_id == "m-1"
      assert error.data == %{"message_id" => "m-1"}
      assert error.raw_body == body
      assert error.headers["x-request-id"] == ["abc"]
    end

    test "a NoValidRecipientsError carries the parsed results" do
      body =
        ~s({"message":"NO_VALID_RECIPIENTS","success":false,"data":{"results":[{"status":"REJECTED","to":12,"reason":"INVALID_NUMBER"}]}})

      plug = fn conn -> Plug.Conn.send_resp(conn, 200, body) end

      assert {:error, %Error{results: [rejected]} = error} =
               Unicom360.WhatsApp.send_template(client(plug), %{
                 template: "t",
                 recipients: [%{to: "12"}]
               })

      assert Error.class(error) == "NoValidRecipientsError"
      assert %Unicom360.WhatsApp.TemplateResult{to: "12", reason: "INVALID_NUMBER"} = rejected
    end

    test "the bang variants raise the same error" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 500, "") end
      client = client(plug, max_retries: 0)
      message = Session.text("260971234567", "Hello")

      for fun <- [
            fn -> Unicom360.SMS.send!(client, @sms) end,
            fn ->
              Unicom360.Email.send!(client, %{from: "a", to: "b", subject: "c", email_body: "d"})
            end,
            fn -> Unicom360.WhatsApp.send_template!(client, %{template: "t", recipients: []}) end,
            fn -> Unicom360.WhatsApp.send_session!(client, message) end,
            fn -> Unicom360.WhatsApp.status!(client, ["m"]) end,
            fn -> Unicom360.WhatsApp.templates!(client) end,
            fn -> Unicom360.Balance.get!(client) end,
            fn -> Unicom360.Balance.all!(client) end,
            fn -> Unicom360.health!(client) end
          ] do
        assert_raise Error, ~r/HTTP 500/, fun
      end
    end

    test "the bang variants return the result" do
      plug = fn conn -> Req.Test.json(conn, %{success: true, status: "ok", data: []}) end
      assert %Unicom360.Health{status: "ok"} = Unicom360.health!(client(plug))
      assert %Unicom360.SMS.SendResult{} = Unicom360.SMS.send!(client(plug), @sms)
    end
  end

  describe "request options" do
    test "max_retries per call overrides the client's" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        Agent.update(calls, &(&1 + 1))
        Plug.Conn.send_resp(conn, 500, "")
      end

      assert {:error, _} = Unicom360.Balance.get(client(plug), max_retries: 0)
      assert Agent.get(calls, & &1) == 1
    end

    test "max_retries: 0 is honoured, not treated as unset" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      plug = fn conn ->
        Agent.update(calls, &(&1 + 1))
        Plug.Conn.send_resp(conn, 500, "")
      end

      assert {:error, _} = Unicom360.health(client(plug, max_retries: 5), max_retries: 0)
      assert Agent.get(calls, & &1) == 1
    end

    test "unknown or unusable request options raise" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 500, "") end

      assert_raise ArgumentError, ~r/unknown request options/, fn ->
        Unicom360.health(client(plug), nope: 1)
      end

      assert_raise ArgumentError, ~r/timeout/, fn ->
        Unicom360.health(client(plug), timeout: 0)
      end

      assert_raise ArgumentError, ~r/max_retries/, fn ->
        Unicom360.health(client(plug), max_retries: -1)
      end
    end

    test ":req_options pass through; the SDK's own options and headers cannot be replaced" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:headers, conn.req_headers, conn.method, conn.request_path})
        Req.Test.json(conn, @ok)
      end

      client =
        Unicom360.client!(
          api_key: "k",
          plug: plug,
          req_options: [
            headers: [
              {"x-trace-id", "t-1"},
              {"X-API-Key", "other"},
              {"Authorization", "Bearer no"}
            ],
            url: "https://evil.example",
            method: :delete,
            retry: :transient,
            redirect: true
          ]
        )

      assert {:ok, _} = Unicom360.SMS.send(client, @sms)
      assert_received {:headers, headers, "POST", "/api/v1/json/bulk/sms"}

      assert {"x-trace-id", "t-1"} in headers
      assert {"x-api-key", "k"} in headers
      refute List.keymember?(headers, "authorization", 0)
    end
  end

  describe "parameters" do
    test "unknown or missing keys raise ArgumentError" do
      plug = fn conn -> Req.Test.json(conn, @ok) end

      assert_raise ArgumentError, ~r/unknown keys \[:mesage\]/, fn ->
        Unicom360.SMS.send(client(plug), %{from: "a", to: "b", mesage: "c", message: "d"})
      end

      assert_raise ArgumentError, ~r/missing required keys \[:message\]/, fn ->
        Unicom360.SMS.send(client(plug), %{from: "a", to: "b"})
      end

      assert_raise ArgumentError, ~r/expected atom keys/, fn ->
        Unicom360.SMS.send(client(plug), %{"from" => "a", "to" => "b", "message" => "c"})
      end

      assert_raise ArgumentError, ~r/expected a map or a keyword list/, fn ->
        Unicom360.SMS.send(client(plug), "nope")
      end

      assert_raise ArgumentError, ~r/:recipients must be a list/, fn ->
        Unicom360.WhatsApp.send_template(client(plug), %{template: "t", recipients: "nope"})
      end
    end

    test "keyword lists work too, and nil means unset" do
      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})
        Req.Test.json(conn, @ok)
      end

      assert {:ok, _} =
               Unicom360.SMS.send(client(plug),
                 from: "a",
                 to: "b",
                 message: "c",
                 source: nil
               )

      assert_received {:body, %{"from" => "a", "to" => "b", "message" => "c"} = body}
      refute Map.has_key?(body, "source")
    end

    test "send_session takes a map in the API's shape, sent as given" do
      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, data: %{message_id: "m"}})
      end

      assert {:ok, %{message_id: "m"}} =
               Unicom360.WhatsApp.send_session(client(plug), %{
                 "to" => "260971234567",
                 "type" => "text",
                 "text" => "Hi"
               })

      assert_received {:body, %{"to" => "260971234567", "type" => "text", "text" => "Hi"}}

      assert_raise ArgumentError, ~r/SessionMessage or a map/, fn ->
        Unicom360.WhatsApp.send_session(client(plug), %TransportError{})
      end
    end

    test "builders refuse options they do not take" do
      assert_raise ArgumentError, fn ->
        Session.reaction("1", "m", "x", reply_to: "n")
      end

      assert_raise ArgumentError, fn ->
        Session.audio("1", "https://a.example", caption: "no")
      end

      assert_raise ArgumentError, fn ->
        TemplateRecipient.new("1", nope: 1)
      end
    end

    test "plain maps and strings work for recipients, headers, bodies and buttons" do
      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})
        Req.Test.json(conn, %{success: true, data: %{accepted: 1, rejected: 0, results: []}})
      end

      assert {:ok, %{accepted_count: 1, rejected_count: 0}} =
               Unicom360.WhatsApp.send_template(client(plug),
                 template: "t",
                 recipients: [
                   %{
                     to: "1",
                     header: "Ada",
                     body: ["x"],
                     buttons: [%{index: 0, type: "url", value: "v"}]
                   },
                   [to: "2", header: %{type: "image", url: "https://a.example"}, body: %{a: "b"}]
                 ]
               )

      assert_received {:body, %{"recipients" => [first, second]}}
      assert first["header"] == "Ada"
      assert first["buttons"] == [%{"index" => 0, "type" => "url", "value" => "v"}]
      assert second["header"] == %{"type" => "image", "url" => "https://a.example"}
      assert second["body"] == %{"a" => "b"}
    end

    test "session builders accept tuples and maps for buttons, sections and rows" do
      message =
        Session.buttons("1", "b", [{"a", "A"}, %{id: "b", title: "B"}], header: "h", footer: "f")

      assert message.content["interactive"]["buttons"] == [
               %{"id" => "a", "title" => "A"},
               %{"id" => "b", "title" => "B"}
             ]

      message =
        Session.list("1", "b", "open", [
          %{title: "s", rows: [%{id: "r", title: "R", description: "d"}]}
        ])

      assert message.content["interactive"]["sections"] == [
               %{
                 "title" => "s",
                 "rows" => [%{"id" => "r", "title" => "R", "description" => "d"}]
               }
             ]
    end
  end

  test "models keep raw and the fields they do not model" do
    body =
      ~s({"success":true,"api_reference":"r","message":"ok","new_top":1,"data":[{"message_id":7,"status":"S","new_item":2}]})

    plug = fn conn -> Plug.Conn.send_resp(conn, 200, body) end

    assert {:ok, result} = Unicom360.SMS.send(client(plug), @sms)
    assert result.raw == Jason.decode!(body)
    assert result.extra == %{"new_top" => 1}

    assert [%{message_id: "7", extra: %{"new_item" => 2}, raw: %{"message_id" => 7}}] =
             result.results
  end

  test "a balance keeps every digit" do
    body = ~s({"status":true,"balance":12345678901234567.89,"bundle_type":"SMS"})
    plug = fn conn -> Plug.Conn.send_resp(conn, 200, body) end

    assert {:ok, %Unicom360.Balance{balance: balance}} = Unicom360.Balance.get(client(plug))
    assert Decimal.equal?(balance, Decimal.new("12345678901234567.89"))
  end

  test "bundle type constants" do
    assert Unicom360.Balance.sms() == "SMS"
    assert Unicom360.Balance.sms_international() == "SMS_INTERNATIONAL"
    assert Unicom360.Balance.email() == "EMAIL"
    assert Unicom360.Balance.whatsapp() == "WHATSAPP"
  end
end
