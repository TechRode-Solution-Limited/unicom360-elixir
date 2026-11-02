defmodule Unicom360.LoggingTest do
  # Not async: capture_log sees the whole node, and the level is global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    previous = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous) end)
  end

  @secret_key "super-secret-api-key"
  @number "260971234567"
  @text "Your code is 482193"

  defp client(plug, options \\ []) do
    Unicom360.client!(
      [
        api_key: @secret_key,
        plug: plug,
        sleeper: fn _ms -> :ok end,
        random: fn -> 0.0 end
      ] ++ options
    )
  end

  test "one debug line per attempt, with the safe fields only" do
    body =
      ~s({"success":true,"api_reference":"ref-1","message":"ok","data":[{"mobile_number":"#{@number}"}]})

    plug = fn conn -> Plug.Conn.send_resp(conn, 200, body) end

    log =
      capture_log([level: :debug], fn ->
        assert {:ok, _} =
                 Unicom360.SMS.send(client(plug), %{
                   from: "Unicom360",
                   to: @number,
                   message: @text
                 })
      end)

    assert log =~ "POST /api/v1/json/bulk/sms"
    assert log =~ "status=200"
    assert log =~ "api_reference=ref-1"
    assert log =~ "attempt=1"
    assert log =~ "duration_ms="

    refute log =~ @secret_key
    refute log =~ @number
    refute log =~ @text
    refute log =~ "Unicom360\""
  end

  test "generated references are on the debug line, so a caller can find them" do
    plug = fn conn -> Req.Test.json(conn, %{success: true, data: []}) end

    log =
      capture_log([level: :debug], fn ->
        assert {:ok, _} =
                 Unicom360.SMS.send(client(plug, auto_reference_ids: true), %{
                   from: "a",
                   to: "1",
                   message: "m"
                 })
      end)

    assert log =~ ~r/generated_user_reference_ids=u360-[0-9a-f]{32}/
  end

  test "a transport failure is logged by its reason" do
    plug = fn conn -> Req.Test.transport_error(conn, :econnrefused) end

    log =
      capture_log([level: :debug], fn ->
        assert {:error, _} = Unicom360.health(client(plug, max_retries: 0))
      end)

    assert log =~ "GET /health"
    assert log =~ "transport_error=:econnrefused"
  end

  test "one info line per scheduled retry, with the attempt, the wait and the cause" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 500, "") end

    log =
      capture_log([level: :info], fn ->
        assert {:error, _} = Unicom360.Balance.get(client(plug, max_retries: 1))
      end)

    assert log =~ "retrying POST /api/v1/json/balance after attempt=1"
    assert log =~ "wait_ms=0"
    assert log =~ "cause=api_server_error UNKNOWN"
    refute log =~ @secret_key
  end

  test "an API error's message never contains the key" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 401, ~s({"message":"AUTHENTICATION_FAILED"})) end

    assert {:error, error} = Unicom360.Balance.get(client(plug))
    refute Exception.message(error) =~ @secret_key
    refute inspect(error) =~ @secret_key
  end
end
