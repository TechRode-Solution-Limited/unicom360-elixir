defmodule Unicom360.AutoReferenceIdsTest do
  use ExUnit.Case, async: true

  alias Unicom360.WhatsApp.{Session, TemplateRecipient}

  @reference ~r/\Au360-[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}\z/

  # Records each request's body; answers with 500 once (a retry of a safe call), then `ok`.
  defp recording(ok, failures \\ 1) do
    {:ok, agent} = Agent.start_link(fn -> %{bodies: [], failures: failures} end)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      failing = Agent.get_and_update(agent, &record(&1, Jason.decode!(body)))
      if failing, do: Plug.Conn.send_resp(conn, 500, ""), else: Req.Test.json(conn, ok)
    end

    client =
      Unicom360.client!(
        api_key: "k",
        plug: plug,
        auto_reference_ids: true,
        sleeper: fn _ms -> :ok end,
        random: fn -> 0.0 end
      )

    {client, fn -> Agent.get(agent, & &1.bodies) end}
  end

  defp record(state, body) do
    state = %{state | bodies: state.bodies ++ [body]}

    if state.failures > 0,
      do: {true, %{state | failures: state.failures - 1}},
      else: {false, state}
  end

  @envelope %{success: true, message: "successful", api_reference: "r", data: []}

  test "sms.send: generated before the first attempt and reused on every retry" do
    {client, bodies} = recording(@envelope)

    assert {:ok, _} = Unicom360.SMS.send(client, %{from: "a", to: "1", message: "m"})

    assert [first, second] = bodies.()
    assert first["user_reference_id"] =~ @reference
    assert first["user_reference_id"] == second["user_reference_id"]
  end

  test "sms.send: a reference you pass is never replaced" do
    {client, bodies} = recording(@envelope, 0)

    assert {:ok, _} =
             Unicom360.SMS.send(client, %{
               from: "a",
               to: "1",
               message: "m",
               user_reference_id: "mine"
             })

    assert [%{"user_reference_id" => "mine"}] = bodies.()
  end

  test "email.send: gets a reference, but is still not retried after a 500" do
    {client, bodies} = recording(@envelope)

    assert {:error, %Unicom360.Error{type: :api_server_error, attempts: 1}} =
             Unicom360.Email.send(client, %{from: "a", to: "b", subject: "s", email_body: "e"})

    assert [%{"user_reference_id" => reference}] = bodies.()
    assert reference =~ @reference
  end

  test "whatsapp.send_session: gets one" do
    {client, bodies} = recording(%{success: true, data: %{}})

    assert {:ok, _} = Unicom360.WhatsApp.send_session(client, Session.text("1", "Hi"))

    assert [first, second] = bodies.()
    assert first["user_reference_id"] =~ @reference
    assert first["user_reference_id"] == second["user_reference_id"]
  end

  test "whatsapp.send_session: a map in API shape gets one under its own key style" do
    {client, bodies} = recording(%{success: true, data: %{}}, 0)

    assert {:ok, _} =
             Unicom360.WhatsApp.send_session(client, %{to: "1", type: "text", text: "Hi"})

    assert [%{"user_reference_id" => reference}] = bodies.()
    assert reference =~ @reference

    assert {:ok, _} =
             Unicom360.WhatsApp.send_session(client, %{
               "to" => "1",
               "type" => "text",
               "text" => "Hi",
               "user_reference_id" => "mine"
             })

    assert [_, %{"user_reference_id" => "mine"}] = bodies.()
  end

  test "whatsapp.send_template: each recipient without one gets its own" do
    {client, bodies} = recording(%{success: true, data: %{accepted: 2, rejected: 0, results: []}})

    assert {:ok, _} =
             Unicom360.WhatsApp.send_template(client, %{
               template: "t",
               recipients: [
                 TemplateRecipient.new("1"),
                 TemplateRecipient.new("2", user_reference_id: "mine"),
                 %{to: "3"}
               ]
             })

    assert [first, second] = bodies.()
    assert first == second
    [one, two, three] = first["recipients"]
    assert one["user_reference_id"] =~ @reference
    assert two["user_reference_id"] == "mine"
    assert three["user_reference_id"] =~ @reference
    assert one["user_reference_id"] != three["user_reference_id"]
  end

  test "off by default: nothing is generated and an unsafe send is not retried" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(agent, &[Jason.decode!(body) | &1])
      Plug.Conn.send_resp(conn, 500, "")
    end

    client = Unicom360.client!(api_key: "k", plug: plug)

    assert {:error, %Unicom360.Error{attempts: 1}} =
             Unicom360.SMS.send(client, %{from: "a", to: "1", message: "m"})

    assert [body] = Agent.get(agent, & &1)
    refute Map.has_key?(body, "user_reference_id")
  end

  test "a blank reference does not make a send retry-safe" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    plug = fn conn ->
      Agent.update(agent, &(&1 + 1))
      Plug.Conn.send_resp(conn, 500, "")
    end

    client = Unicom360.client!(api_key: "k", plug: plug)

    assert {:error, %Unicom360.Error{attempts: 1}} =
             Unicom360.SMS.send(client, %{
               from: "a",
               to: "1",
               message: "m",
               user_reference_id: "  "
             })

    assert Agent.get(agent, & &1) == 1
  end

  test "an empty recipient list is not retry-safe" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    plug = fn conn ->
      Agent.update(agent, &(&1 + 1))
      Plug.Conn.send_resp(conn, 500, "")
    end

    client = Unicom360.client!(api_key: "k", plug: plug)

    assert {:error, %Unicom360.Error{attempts: 1}} =
             Unicom360.WhatsApp.send_template(client, %{template: "t", recipients: []})

    assert Agent.get(agent, & &1) == 1
  end
end
