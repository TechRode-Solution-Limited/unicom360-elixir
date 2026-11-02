defmodule Unicom360.Test.Conformance do
  @moduledoc """
  The conformance harness: fixture loading, fakes, the operation mapping and canonical form.

  The fixtures in `test/fixtures/conformance` are vendored from `unicom360-openapi` (see
  `conformance/README.md` there). Every vector of every file runs through the public API; a
  vector this harness does not understand fails rather than being skipped.
  """

  import ExUnit.Assertions

  alias Unicom360.WhatsApp.{
    ListRow,
    ListSection,
    ReplyButton,
    Session,
    TemplateBody,
    TemplateButton,
    TemplateHeader,
    TemplateRecipient
  }

  @fixtures Path.expand("../fixtures/conformance", __DIR__)

  @api_key "test-api-key"

  @operations ~w(sms.send email.send whatsapp.send_template whatsapp.send_session whatsapp.status
                 whatsapp.templates balance.get balance.all health)

  # Every fixture file and the test file that turns each of its vectors into a test.
  @files %{
    "requests.json" => "requests_test.exs",
    "responses.json" => "responses_test.exs",
    "retries.json" => "retries_test.exs",
    "error-codes.json" => "error_codes_test.exs",
    "callbacks.json" => "callbacks_test.exs",
    "gsm7.json" => "gsm7_test.exs",
    "webhooks/signatures.json" => "signatures_test.exs",
    "webhooks/events.json" => "events_test.exs"
  }

  def fixtures_dir, do: @fixtures
  def api_key, do: @api_key
  def operations, do: @operations

  @doc "Every fixture file and the test file that runs all of its vectors."
  def files, do: @files

  def load(name), do: @fixtures |> Path.join(name) |> File.read!() |> Jason.decode!()

  def vectors(name), do: load(name)["vectors"]

  @doc "Fails on a JSON object shape this harness does not understand."
  def check_keys(object, required, optional \\ []) do
    keys = Map.keys(object)
    what = Map.get(object, "id", inspect(object))
    assert required -- keys == [], "#{what}: missing keys #{inspect(required -- keys)}"

    assert keys -- (required ++ optional) == [],
           "#{what}: keys this harness does not understand " <>
             inspect(keys -- (required ++ optional))
  end

  # ---------------------------------------------------------------------------------------
  # Fakes
  # ---------------------------------------------------------------------------------------

  @transport_failures %{
    "connect_refused" => :econnrefused,
    "dns_failure" => :nxdomain,
    "timeout_after_send" => :timeout,
    "reset_after_send" => :closed
  }

  @doc """
  A plug that answers attempt n with `steps[n - 1]` (`{"http": ...}` or `{"transport": kind}`)
  and records every request. Returns `{plug, requests}`, where `requests.()` lists them.
  """
  def fake_plug(steps) do
    {:ok, agent} = Agent.start_link(fn -> %{steps: steps, requests: []} end)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      request = %{
        method: conn.method,
        path: conn.request_path,
        query: conn.query_string,
        headers: conn.req_headers,
        body: body
      }

      respond(conn, Agent.get_and_update(agent, &next_step(&1, request)))
    end

    {plug, fn -> Agent.get(agent, & &1.requests) end}
  end

  defp next_step(state, request) do
    state = %{state | requests: state.requests ++ [request]}

    case state.steps do
      [step | rest] -> {step, %{state | steps: rest}}
      [] -> {:no_step, state}
    end
  end

  defp respond(_conn, :no_step), do: flunk("an attempt the vector has no step for")

  defp respond(conn, %{"http" => http} = step) do
    check_keys(step, ["http"])
    respond_http(conn, http)
  end

  defp respond(conn, %{"transport" => kind} = step) do
    check_keys(step, ["transport"])
    assert Map.has_key?(@transport_failures, kind), "unknown transport failure #{inspect(kind)}"
    Req.Test.transport_error(conn, Map.fetch!(@transport_failures, kind))
  end

  defp respond_http(conn, http) do
    check_keys(http, ["status", "headers", "body_text"])

    http["headers"]
    |> Enum.reduce(conn, fn {name, value}, conn ->
      Plug.Conn.put_resp_header(conn, name, value)
    end)
    |> Plug.Conn.send_resp(http["status"], http["body_text"])
  end

  @doc "A clock that moves only when the sleeper sleeps, by exactly the milliseconds slept."
  def fake_time(now_ms) do
    {:ok, agent} = Agent.start_link(fn -> %{now: now_ms, sleeps: []} end)

    %{
      clock: fn -> Agent.get(agent, & &1.now) end,
      sleeper: fn ms ->
        Agent.update(agent, fn state -> %{now: state.now + ms, sleeps: state.sleeps ++ [ms]} end)
      end,
      sleeps: fn -> Agent.get(agent, & &1.sleeps) end
    }
  end

  @doc "The fixtures' Unix seconds (possibly fractional) in this SDK's unit, milliseconds."
  def to_ms(seconds), do: round(seconds * 1000)

  def client(plug, options) do
    Unicom360.client!([api_key: @api_key, plug: plug] ++ options)
  end

  # ---------------------------------------------------------------------------------------
  # Operations: canonical params (API names) to SDK calls
  # ---------------------------------------------------------------------------------------

  @doc "Call `operation` with `params` (API field names) through the public API."
  def call(client, operation, params)

  def call(client, "sms.send", params) do
    Unicom360.SMS.send(
      client,
      take!(params, ~w(from to message), ~w(user_reference_id callback_url source))
    )
  end

  def call(client, "email.send", params) do
    Unicom360.Email.send(
      client,
      take!(
        params,
        ~w(from to subject email_body),
        ~w(reply_to user_reference_id callback_url source)
      )
    )
  end

  def call(client, "whatsapp.send_template", params) do
    fields = take!(params, ~w(template recipients), ~w(from language callback_url))
    recipients = Enum.map(fields.recipients, &recipient/1)
    Unicom360.WhatsApp.send_template(client, %{fields | recipients: recipients})
  end

  def call(client, "whatsapp.send_session", params) do
    Unicom360.WhatsApp.send_session(client, session_message(params))
  end

  def call(client, "whatsapp.status", params) do
    fields = take!(params, ~w(message_ids), [])
    Unicom360.WhatsApp.status(client, fields.message_ids)
  end

  def call(client, "whatsapp.templates", params) do
    take!(params, [], [])
    Unicom360.WhatsApp.templates(client)
  end

  def call(client, "balance.get", params) do
    case take!(params, [], ~w(bundle_type)) do
      %{bundle_type: bundle} -> Unicom360.Balance.get(client, bundle_type: bundle)
      _none -> Unicom360.Balance.get(client)
    end
  end

  def call(client, "balance.all", params) do
    take!(params, [], [])
    Unicom360.Balance.all(client)
  end

  def call(client, "health", params) do
    take!(params, [], [])
    Unicom360.health(client)
  end

  def call(_client, operation, _params), do: flunk("unknown operation #{inspect(operation)}")

  # Reads API-named params into atom keys, failing on a key the harness does not understand.
  defp take!(params, required, optional) do
    check_keys(params, required, optional)
    Map.new(params, fn {key, value} -> {String.to_atom(key), value} end)
  end

  defp recipient(params) do
    fields = take!(params, ~w(to), ~w(user_reference_id header body buttons otp))

    opts =
      fields
      |> Map.delete(:to)
      |> Enum.map(fn
        {:header, value} -> {:header, header(value)}
        {:body, value} -> {:body, body(value)}
        {:buttons, value} -> {:buttons, Enum.map(value, &button/1)}
        other -> other
      end)

    TemplateRecipient.new(fields.to, opts)
  end

  defp header(value) when is_binary(value), do: TemplateHeader.text(value)

  defp header(%{"type" => "image"} = value) do
    check_keys(value, ~w(type url))
    TemplateHeader.image(value["url"])
  end

  defp header(%{"type" => "video"} = value) do
    check_keys(value, ~w(type url))
    TemplateHeader.video(value["url"])
  end

  defp header(%{"type" => "document"} = value) do
    check_keys(value, ~w(type url), ~w(filename))
    TemplateHeader.document(value["url"], value["filename"])
  end

  defp header(value), do: flunk("unknown template header #{inspect(value)}")

  defp body(value) when is_list(value), do: TemplateBody.of(value)
  defp body(value) when is_map(value), do: TemplateBody.named(value)

  defp button(%{"type" => type, "index" => index, "value" => value} = button) do
    check_keys(button, ~w(type index value))

    case type do
      "url" -> TemplateButton.url(index, value)
      "quick_reply" -> TemplateButton.quick_reply(index, value)
      other -> flunk("unknown template button type #{inspect(other)}")
    end
  end

  defp session_message(%{"type" => "text"} = params) do
    check_session(params, ~w(text), true)
    Session.text(params["to"], params["text"], common(params))
  end

  defp session_message(%{"type" => type} = params)
       when type in ~w(image video document audio sticker) do
    check_session(params, ~w(media), true)
    media = take!(params["media"], ~w(url), ~w(caption filename))
    opts = common(params) ++ Enum.to_list(Map.delete(media, :url))

    case type do
      "image" -> Session.image(params["to"], media.url, opts)
      "video" -> Session.video(params["to"], media.url, opts)
      "document" -> Session.document(params["to"], media.url, opts)
      "audio" -> Session.audio(params["to"], media.url, opts)
      "sticker" -> Session.sticker(params["to"], media.url, opts)
    end
  end

  defp session_message(%{"type" => "interactive"} = params) do
    check_session(params, ~w(interactive), true)
    interactive(params["interactive"], params)
  end

  defp session_message(%{"type" => "location"} = params) do
    check_session(params, ~w(location), true)
    location = take!(params["location"], ~w(latitude longitude), ~w(name address))
    opts = common(params) ++ Enum.to_list(Map.drop(location, [:latitude, :longitude]))
    Session.location(params["to"], location.latitude, location.longitude, opts)
  end

  defp session_message(%{"type" => "contacts"} = params) do
    check_session(params, ~w(contacts), true)
    Session.contacts(params["to"], params["contacts"], common(params))
  end

  defp session_message(%{"type" => "reaction"} = params) do
    check_session(params, ~w(reaction), false)
    reaction = take!(params["reaction"], ~w(message_id emoji), [])
    Session.reaction(params["to"], reaction.message_id, reaction.emoji, common(params))
  end

  defp session_message(params), do: flunk("unknown session message #{inspect(params)}")

  defp interactive(%{"type" => "button"} = interactive, params) do
    fields = take!(interactive, ~w(type body buttons), ~w(header footer))

    buttons =
      Enum.map(fields.buttons, fn button ->
        ReplyButton.new(button["id"], button["title"])
        |> tap(fn _ -> check_keys(button, ~w(id title)) end)
      end)

    opts = common(params) ++ Enum.to_list(Map.take(fields, [:header, :footer]))
    Session.buttons(params["to"], fields.body, buttons, opts)
  end

  defp interactive(%{"type" => "list"} = interactive, params) do
    fields = take!(interactive, ~w(type body button sections), ~w(header footer))
    sections = Enum.map(fields.sections, &section/1)
    opts = common(params) ++ Enum.to_list(Map.take(fields, [:header, :footer]))
    Session.list(params["to"], fields.body, fields.button, sections, opts)
  end

  defp interactive(other, _params), do: flunk("unknown interactive #{inspect(other)}")

  defp section(section) do
    check_keys(section, ~w(rows), ~w(title))

    rows =
      Enum.map(section["rows"], fn row ->
        check_keys(row, ~w(id title), ~w(description))
        ListRow.new(row["id"], row["title"], row["description"])
      end)

    ListSection.new(rows, section["title"])
  end

  defp check_session(params, required, reply_to?) do
    optional =
      ~w(from user_reference_id callback_url) ++ if(reply_to?, do: ~w(reply_to), else: [])

    check_keys(params, ~w(to type) ++ required, optional)
  end

  defp common(params) do
    for key <- ~w(from reply_to user_reference_id callback_url), Map.has_key?(params, key) do
      {String.to_atom(key), params[key]}
    end
  end

  @doc "Valid params for `operation`: those of its first `requests.json` vector."
  def sample_params(operation) do
    vector = Enum.find(vectors("requests.json"), &(&1["operation"] == operation))
    assert vector, "requests.json has no vector for #{inspect(operation)}"
    vector["params"]
  end

  # ---------------------------------------------------------------------------------------
  # Canonical form and comparison (conformance/README.md)
  # ---------------------------------------------------------------------------------------

  @renamed %{accepted_count: "accepted", rejected_count: "rejected"}

  @doc "The canonical JSON of a model: its typed fields under API names, plus its `extra`."
  def canonical(%Decimal{} = value), do: value

  def canonical(%_{} = model) do
    fields =
      model
      |> Map.from_struct()
      |> Map.drop([:raw, :extra])
      |> Map.new(fn {key, value} ->
        {Map.get(@renamed, key, Atom.to_string(key)), canonical(value)}
      end)

    extra = Map.get(model, :extra, %{})
    shadowed = Enum.filter(Map.keys(extra), &Map.has_key?(fields, &1))
    assert shadowed == [], "extra fields shadow modelled fields: #{inspect(shadowed)}"
    Map.merge(fields, canonical(extra))
  end

  def canonical(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, canonical(v)} end)
  def canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  def canonical(value), do: value

  @doc "Removes every object member whose value is null, recursively."
  def drop_nulls(%Decimal{} = value), do: value

  def drop_nulls(value) when is_map(value) do
    for {key, item} <- value, not is_nil(item), into: %{}, do: {key, drop_nulls(item)}
  end

  def drop_nulls(value) when is_list(value), do: Enum.map(value, &drop_nulls/1)
  def drop_nulls(value), do: value

  @doc "Nulls dropped, key order ignored, numbers by value, strings and booleans exact."
  def assert_canonical_equal(expected, actual) do
    case difference(drop_nulls(expected), drop_nulls(actual), "$") do
      nil -> :ok
      problem -> flunk(problem)
    end
  end

  @doc "A JSON value exactly equal to another: nothing dropped, numbers by value."
  def assert_json_equal(expected, actual) do
    case difference(expected, actual, "$") do
      nil -> :ok
      problem -> flunk(problem)
    end
  end

  defp difference(a, b, path) do
    cond do
      number?(a) or number?(b) -> number_difference(a, b, path)
      is_list(a) or is_list(b) -> list_difference(a, b, path)
      is_map(a) or is_map(b) -> map_difference(a, b, path)
      a === b -> nil
      true -> "#{path}: #{inspect(a)} != #{inspect(b)}"
    end
  end

  defp number_difference(a, b, path) do
    if number?(a) and number?(b) and Decimal.equal?(decimal(a), decimal(b)),
      do: nil,
      else: "#{path}: #{inspect(a)} != #{inspect(b)}"
  end

  defp list_difference(a, b, path) when is_list(a) and is_list(b) and length(a) == length(b) do
    [a, b]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.find_value(fn {{x, y}, index} -> difference(x, y, "#{path}[#{index}]") end)
  end

  defp list_difference(a, b, path), do: "#{path}: #{inspect(a)} != #{inspect(b)}"

  defp map_difference(a, b, path) when is_map(a) and is_map(b) do
    if Enum.sort(Map.keys(a)) == Enum.sort(Map.keys(b)) do
      Enum.find_value(a, fn {key, value} -> difference(value, b[key], "#{path}.#{key}") end)
    else
      "#{path}: keys #{inspect(Enum.sort(Map.keys(a)))} != #{inspect(Enum.sort(Map.keys(b)))}"
    end
  end

  defp map_difference(a, b, path), do: "#{path}: #{inspect(a)} != #{inspect(b)}"

  defp number?(%Decimal{}), do: true
  defp number?(value), do: is_number(value)

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)

  @doc "Whether the RFC 6901 `pointer` resolves in `document`."
  def pointer_exists?(document, pointer) do
    pointer
    |> String.split("/")
    |> tl()
    |> Enum.reduce_while({:ok, document}, fn token, {:ok, current} ->
      token = token |> String.replace("~1", "/") |> String.replace("~0", "~")

      case step_into(current, token) do
        {:ok, next} -> {:cont, {:ok, next}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, _value} -> true
      :error -> false
    end
  end

  defp step_into(current, token) when is_map(current), do: Map.fetch(current, token)

  defp step_into(current, token) when is_list(current) do
    case Integer.parse(token) do
      {index, ""} when index >= 0 and index < length(current) -> {:ok, Enum.at(current, index)}
      _ -> :error
    end
  end

  defp step_into(_current, _token), do: :error

  @doc "The expected error, compared with `%Unicom360.Error{}`."
  def assert_error(expected, %Unicom360.Error{} = error) do
    check_keys(
      expected,
      ~w(type class code message api_reference http_status data_present),
      ~w(retry_after)
    )

    assert Atom.to_string(error.type) == expected["type"]
    assert Unicom360.Error.class(error) == expected["class"]
    assert error.code == expected["code"]
    assert error.api_reference == expected["api_reference"]
    assert error.http_status == expected["http_status"]

    if expected["message"] do
      assert error.message == expected["message"]
    else
      assert is_binary(error.message) and error.message != ""
    end

    assert not is_nil(error.data) == expected["data_present"]

    if Map.has_key?(expected, "retry_after") do
      assert error.retry_after == expected["retry_after"] * 1000
    end
  end
end
