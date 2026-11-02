# Unicom360 Elixir SDK

The official Elixir client for the [Unicom360](https://unicom360.com) API: SMS, email and
WhatsApp over one JSON API.

* Elixir 1.15 or later, on Erlang/OTP 25 or later. Built on [Req](https://hexdocs.pm/req).
* Typed result structs, with `@spec` on every public function, checked with Dialyzer.
* Targets **Unicom360 API contract v0.1.0** (`openapi.yaml` 0.1.0 in
  [unicom360-openapi](https://github.com/TechRode-Solution-Limited/unicom360-openapi)), and runs
  that contract's full conformance suite in CI.
* API reference: <https://unicom360.com/docs>. Module docs: <https://hexdocs.pm/unicom360>.

There is no sandbox: every accepted send is real and billed.

## Contents

* [Install](#install)
* [Quick start](#quick-start)
* [Every operation](#every-operation)
* [Results](#results)
* [Errors](#errors)
* [Retries](#retries)
* [auto_reference_ids](#auto_reference_ids)
* [Webhooks](#webhooks)
* [SMS and email delivery reports](#sms-and-email-delivery-reports)
* [GSM-7 helpers](#gsm-7-helpers)
* [Configuration](#configuration)
* [Testing your code](#testing-your-code)
* [Logging](#logging)
* [Known differences from the published docs](#known-differences-from-the-published-docs)
* [Versioning](#versioning)

## Install

Add it to `mix.exs`:

```elixir
def deps do
  [
    {:unicom360, "~> 0.1"},
    # Only for Unicom360.Webhook.Plug and Unicom360.Webhook.BodyReader, if your app has no Plug yet:
    {:plug, "~> 1.14"}
  ]
end
```

## Quick start

```elixir
{:ok, client} = Unicom360.client()  # reads UNICOM360_API_KEY; or Unicom360.client(api_key: "...")

{:ok, result} =
  Unicom360.SMS.send(client, %{
    from: "Unicom360",
    to: ["260971234567", "260961234567"],
    message: "Your verification code is 482193. It expires in 5 minutes."
  })

for recipient <- result.results do
  IO.puts("#{recipient.mobile_number} #{recipient.status} #{recipient.message_id}")
end
```

Every operation takes the client first and returns `{:ok, result}` or
`{:error, %Unicom360.Error{}}`. Each has a `!` variant (`Unicom360.SMS.send!/3`) that returns the
result or raises. Parameters are maps or keyword lists with atom keys, named as in the API.

## Every operation

| Operation | Function | Returns |
|---|---|---|
| Send an SMS | `Unicom360.SMS.send(client, params, opts \\ [])` | `%Unicom360.SMS.SendResult{}` |
| Send an email | `Unicom360.Email.send(client, params, opts \\ [])` | `%Unicom360.Email.SendResult{}` |
| Send a WhatsApp template | `Unicom360.WhatsApp.send_template(client, params, opts \\ [])` | `%Unicom360.WhatsApp.TemplateSendResult{}` |
| Send a WhatsApp session message | `Unicom360.WhatsApp.send_session(client, message, opts \\ [])` | `%Unicom360.WhatsApp.SessionSendResult{}` |
| WhatsApp message status | `Unicom360.WhatsApp.status(client, message_ids, opts \\ [])` | `%Unicom360.WhatsApp.StatusResult{}` |
| WhatsApp templates | `Unicom360.WhatsApp.templates(client, opts \\ [])` | `%Unicom360.WhatsApp.TemplateList{}` |
| One balance | `Unicom360.Balance.get(client, opts \\ [])` | `%Unicom360.Balance{}` |
| Every balance | `Unicom360.Balance.all(client, opts \\ [])` | `%Unicom360.Balances{}` |
| Health | `Unicom360.health(client, opts \\ [])` | `%Unicom360.Health{}` |

`opts` takes `:timeout` (milliseconds per attempt) and `:max_retries`, which override the client's
settings for that call. Durations are integer milliseconds everywhere in this SDK.

A key an operation does not take, or a required key that is missing, raises `ArgumentError`.
Values are never checked: the gateway validates them and answers with an error (see
[Errors](#errors)).

### SMS

```elixir
{:ok, result} =
  Unicom360.SMS.send(client, %{
    from: "Unicom360",                 # a registered sender ID
    to: "260971234567",                # one number, or a list
    message: "Your order ZM4821 is ready.",  # GSM-7, at most 1,200 characters
    user_reference_id: "order-10421",  # optional: makes the send safe to retry
    callback_url: "https://example.com/webhooks/unicom360/sms",  # optional
    source: "crm"                      # optional label for your reporting
  })

recipient = Unicom360.SMS.SendResult.by_number(result, "260971234567")
```

### Email

```elixir
{:ok, result} =
  Unicom360.Email.send(client, %{
    from: "noreply@yourdomain.com",
    to: ["jane@example.com", "john@example.com"],
    subject: "Your order is confirmed",
    email_body: "<p>Thanks for your order. Order ZM4821 is confirmed.</p>",
    reply_to: "support@yourdomain.com",  # optional
    callback_url: "https://example.com/webhooks/unicom360/email"  # optional
  })

jane = Unicom360.Email.SendResult.by_address(result, "jane@example.com")
```

### WhatsApp template

```elixir
alias Unicom360.WhatsApp
alias Unicom360.WhatsApp.{TemplateBody, TemplateButton, TemplateHeader, TemplateRecipient}

{:ok, result} =
  WhatsApp.send_template(client, %{
    template: "order_ready",
    from: "260960123456",  # optional: your WhatsApp number
    language: "en_US",     # optional
    recipients: [
      TemplateRecipient.new("260971234567",
        user_reference_id: "inv-42",
        header: TemplateHeader.image("https://example.com/receipts/ZM-4821.png"),
        body: TemplateBody.of(["Ada", "ZM-4821"]),  # or TemplateBody.named(%{...})
        buttons: [TemplateButton.url(0, "ZM-4821")]  # or TemplateButton.quick_reply(0, ...)
      ),
      %{to: "260961234567", body: ["Joseph", "ZM-4822"]}  # a plain map works too
    ]
  })

IO.inspect({result.accepted_count, result.rejected_count})

for rejected <- WhatsApp.TemplateSendResult.rejected(result) do
  IO.inspect({rejected.to, rejected.reason})
end
```

Headers: `TemplateHeader.text(value)` (or a plain string), `.image(url)`, `.video(url)`,
`.document(url, filename \\ nil)`. An `AUTHENTICATION` template takes the code as
`TemplateRecipient.new(to, otp: "482193")`.

A rejected recipient is not an error. When **every** recipient is rejected the call fails with
`%Unicom360.Error{code: "NO_VALID_RECIPIENTS"}`, whose `results` say why.

### WhatsApp session message

Inside the 24-hour customer service window, build a message with `Unicom360.WhatsApp.Session`:

```elixir
alias Unicom360.WhatsApp.{ListRow, ListSection, Session}

{:ok, sent} =
  WhatsApp.send_session(client, Session.text("260971234567", "Your order is ready.", reply_to: inbound_wamid))

{:ok, _sent} =
  WhatsApp.send_session(
    client,
    Session.buttons("260971234567", "Collect today or deliver?", [
      {"collect", "Collect"},
      {"deliver", "Deliver"}
    ])
  )
```

| Builder | Sends |
|---|---|
| `Session.text(to, text, opts \\ [])` | text |
| `Session.image(to, url, opts \\ [])` | image; `:caption` |
| `Session.video(to, url, opts \\ [])` | video; `:caption` |
| `Session.document(to, url, opts \\ [])` | document; `:caption`, `:filename` |
| `Session.audio(to, url, opts \\ [])` | audio |
| `Session.sticker(to, url, opts \\ [])` | sticker |
| `Session.buttons(to, body, buttons, opts \\ [])` | up to 3 reply buttons, each `{id, title}`, `ReplyButton.new(id, title)` or a map; `:header`, `:footer` |
| `Session.list(to, body, button, sections, opts \\ [])` | a list of `ListSection.new(rows, title \\ nil)` with `ListRow.new(id, title, description \\ nil)`, or maps; `:header`, `:footer` |
| `Session.location(to, latitude, longitude, opts \\ [])` | a location pin; `:name`, `:address` |
| `Session.contacts(to, contacts, opts \\ [])` | contact cards in Meta's shape (maps) |
| `Session.reaction(to, message_id, emoji, opts \\ [])` | a reaction; `emoji` `""` removes yours |

Every builder takes the options `:from`, `:user_reference_id`, `:callback_url` and (all but
`reaction`) `:reply_to`. `:reply_to` and a reaction's `message_id` take either a `message_id` a
send returned or the `wamid.` id of an inbound message, exactly as a `message.received` webhook
delivers it. `send_session/3` also takes a map in the API's shape. Outside the window the call
fails with `%Unicom360.Error{code: "SESSION_WINDOW_CLOSED"}`: send a template instead.

### WhatsApp status and templates

```elixir
{:ok, status} = WhatsApp.status(client, ["7c1f3a2e-5b64-4d2f-9a8e-0f1b2c3d4e5f"])  # 1 to 100 ids
entry = WhatsApp.StatusResult.by_id(status, "7c1f3a2e-5b64-4d2f-9a8e-0f1b2c3d4e5f")
entry && entry.status  # ACCEPTED, SENT, DELIVERED, READ, FAILED, REJECTED, NOT_FOUND

{:ok, templates} = WhatsApp.templates(client)
order_ready = WhatsApp.TemplateList.by_name(templates, "order_ready", "en_US")
```

### Balance and health

```elixir
{:ok, sms} = Unicom360.Balance.get(client)  # the SMS bundle
sms.balance  # Decimal.new("1250")

# bundle_type: SMS, SMS_INTERNATIONAL, EMAIL, WHATSAPP
{:ok, whatsapp} = Unicom360.Balance.get(client, bundle_type: "WHATSAPP")

{:ok, all} = Unicom360.Balance.all(client)
all.balances  # %{"SMS" => Decimal.new("1250"), ...}

{:ok, health} = Unicom360.health(client)  # sends no API key
health.status  # "ok"
```

Balances are `Decimal`s, exactly as the gateway sent them.

Runnable versions of all of these are in [`examples/`](https://github.com/TechRode-Solution-Limited/unicom360-elixir/tree/main/examples).

## Results

Every result is a plain struct:

* fields named as in the API, `nil` when absent or null;
* `raw`: the JSON object it was parsed from, unmodified (a map with string keys);
* `extra`: every field the gateway sent that this version does not model, so a field added
  tomorrow is readable today.

Statuses, categories and reasons are plain strings: a value this version does not know passes
through. `message_id` is always a string. Timestamps stay the ISO 8601 strings received.

**SMS and email results are not in request order past the tenth recipient.** The SDK keeps the
response's order; find a recipient with the helpers:

| Result | Helpers |
|---|---|
| `Unicom360.SMS.SendResult` | `accepted/1`, `invalid/1`, `by_number/2` |
| `Unicom360.Email.SendResult` | `accepted/1`, `invalid/1`, `by_address/2` |
| `Unicom360.WhatsApp.TemplateSendResult` | `accepted/1`, `rejected/1`, `by_number/2`; counts in `accepted_count`, `rejected_count` |
| `Unicom360.WhatsApp.StatusResult` | `by_id/2` |
| `Unicom360.WhatsApp.TemplateList` | `by_name/3` |

`by_number/2` compares digits only (`"+260 97 123 4567"` finds `"260971234567"`); it does not
expand local formats, so pass the international form. `by_address/2` ignores case and surrounding
spaces.

A partial success (an `Invalid mobile number` among the results, rejected template recipients) is
a result, never an error.

## Errors

Every failure is one struct, `%Unicom360.Error{}`, and `!` variants raise it. Its `type` says what
went wrong:

| `type` | `Unicom360.Error.class/1` | When |
|---|---|---|
| `:configuration_error` | `ConfigurationError` | no API key, an unusable option |
| `:connection_error` | `APIConnectionError` | no complete response (`cause` holds the exception) |
| `:timeout_error` | `APITimeoutError` | the connection or the response timed out |
| `:api_status_error` | `APIStatusError` | any other non-2xx, or a 2xx that is not an envelope |
| `:authentication_error` | `AuthenticationError` | 401 |
| `:rate_limit_error` | `RateLimitError` | 429 (`retry_after`, in ms) |
| `:invalid_request_error` | `InvalidRequestError` | 400: the request's shape is wrong |
| `:api_server_error` | `APIServerError` | 5xx |
| `:api_error` | `APIError` | HTTP 200 with `success: false`: a business refusal |
| `:api_error` | `InsufficientBundleError` | code `INSUFFICIENT_BUNDLE` |
| `:api_error` | `DuplicateReferenceError` | code `DUPLICATE_REFERENCE` (`original_message_id`) |
| `:api_error` | `NoValidRecipientsError` | code `NO_VALID_RECIPIENTS` (`results`) |
| `:api_error` | `SessionWindowClosedError` | code `SESSION_WINDOW_CLOSED` |
| `:signature_verification_error` | `SignatureVerificationError` | a webhook failed verification (`reason`) |
| `:unicom360_error` | `Unicom360Error` | a webhook or callback body that is not a JSON object |

HTTP 200 is not success: a refusal such as an unknown sender ID arrives as HTTP 200 with
`success: false` and is an `:api_error`. Every error from an operation has `message`, `http_status`,
`api_reference` (quote it to support), `raw_body` and `attempts`. API errors add `code`, `data` and
`headers`.

```elixir
case Unicom360.SMS.send(client, %{from: "Unicom360", to: "260971234567", message: "Hello"}) do
  {:ok, result} ->
    result

  {:error, %Unicom360.Error{code: "INSUFFICIENT_BUNDLE"}} ->
    :top_up

  {:error, %Unicom360.Error{type: :rate_limit_error, retry_after: ms}} ->
    {:retry_in_ms, ms}

  {:error, %Unicom360.Error{type: :api_error} = error} ->
    Logger.error("refused: #{error.code} #{error.message} #{error.api_reference}")
    :refused
end
```

`code` is normalised from the gateway's message (`Unicom360.Codes.normalize/1`), so sentences and
codes compare the same way: `Invalid From Sender ID` and `Invalid Sender` are both
`INVALID_SENDER_ID`, `duplicate user reference id` and `DUPLICATE_MSG_REF` are both
`DUPLICATE_REFERENCE`, and anything unrecognised is `UNKNOWN`. A code this version does not know
passes through. The documented codes are `INVALID_SENDER_ID`, `SENDER_ID_NOT_ALLOWED`,
`INVALID_RECIPIENT_LIMIT`, `INSUFFICIENT_BUNDLE`, `DUPLICATE_REFERENCE`, `INVALID_PARAMETERS`,
`SENDER_REQUIRED`, `TEMPLATE_NOT_FOUND`, `TEMPLATE_NOT_APPROVED`, `LANGUAGE_REQUIRED`,
`TEMPLATE_SENDER_MISMATCH`, `NO_VALID_RECIPIENTS`, `SEND_FAILED`, `SESSION_WINDOW_CLOSED`,
`REPLY_TO_NOT_FOUND`, `REACTION_TARGET_NOT_FOUND`, `INVALID_NUMBER`, `INVALID_USER_REFERENCE_ID`,
`MEDIA_URL_INVALID`, `CLIENT_NOT_FOUND`, `MISSING_API_KEY`, `INVALID_AUTHORIZATION`,
`AUTHENTICATION_FAILED`, `CREDENTIAL_DISABLED`, `CLIENT_DISABLED`, `CREDENTIAL_EXPIRED`,
`IP_NOT_ALLOWED` and `RATE_LIMIT_EXCEEDED`; each has a function too
(`Unicom360.Codes.insufficient_bundle/0`).

**A `DuplicateReferenceError` with `attempts` greater than 1 means an earlier attempt of the same
call very probably succeeded**: the retry was refused because that attempt had already used the
reference. Treat it as sent, and look it up rather than sending again.

## Retries

The client retries what is safe to retry, so a retry never sends a message twice:

| Outcome | Retried |
|---|---|
| HTTP 429 | always (it is answered before any processing) |
| No connection made (DNS, refused, TLS) | always |
| A failure after the request was sent, an HTTP 5xx, or `SEND_FAILED` | only if the call is retry-safe |
| HTTP 400, 401, any other 4xx, any other refusal | never |

Retry-safe calls: every read (`status`, `templates`, `balance`, `health`); an SMS or WhatsApp
session send with a `user_reference_id`; a template send where every recipient has one. **Email is
never retry-safe**, even with a reference: the gateway's duplicate check for email is not atomic,
so it is retried only after a 429 or a failure to connect.

Waits: after a 429, until the next UTC minute plus up to a second of jitter (the limit is a fixed
UTC-minute window and the gateway sends no `Retry-After`); otherwise full-jitter exponential
backoff (`random() * min(8_000, 500 * 2^attempt)` ms). `:max_retries` (default 2) bounds the
retries and `:max_retry_wait` (default `60_000` ms) any single wait; a 429 wait longer than
`:max_retry_wait` returns the error at once. The returned error is the last attempt's, with
`attempts` set. These calls block the calling process while they wait.

```elixir
{:ok, client} = Unicom360.client(max_retries: 4)
Unicom360.Balance.get(client, max_retries: 0)  # per call
```

Req's own retries and redirects are always off; a 3xx is an error, so the API key is never sent to
another host.

## auto_reference_ids

```elixir
{:ok, client} = Unicom360.client(auto_reference_ids: true)
```

Off by default. When on, every send without a `user_reference_id` gets one before the first
attempt (`u360-` followed by 32 hex characters), reused on every retry, and each template recipient
without one gets its own. That makes SMS and WhatsApp sends retry-safe. A reference you pass is
never replaced. The generated values are in the request, in the debug log line of the request, and
in the result's `raw` where the API echoes them (template and session results). For email the
reference still lets the gateway refuse a later repeat of the same send, but it does not make email
retry-safe (see above).

## Webhooks

WhatsApp events (`message.status`, `message.received`, `webhook.test`) are signed. Verify and parse
a delivery with `Unicom360.Webhook.construct_event/4`, passing the **raw body**, the request headers
and your webhook secret (the 43-character string from the portal, used as it is: never
base64-decode it):

```elixir
alias Unicom360.Webhook

case Webhook.construct_event(raw_body, conn.req_headers, secret) do
  {:ok, %Webhook.MessageStatusEvent{data: data}} ->
    IO.inspect({data.message_id, data.status})  # sent, delivered, read, failed

  {:ok, %Webhook.MessageReceivedEvent{data: message}} ->
    IO.inspect({message.from, message.type, message.text})

  {:ok, %Webhook.TestEvent{data: data}} ->
    IO.inspect(data.message)

  # An event this version does not know; never an error.
  {:ok, %Webhook.UnknownEvent{event: event, data: data}} ->
    IO.inspect({event, data})

  {:error, %Unicom360.Error{type: :signature_verification_error, reason: reason}} ->
    IO.inspect(reason)  # answer 401; :signature_mismatch, :timestamp_out_of_tolerance, ...
end
```

`Webhook.verify(raw_body, headers, secret, opts \\ [])` only verifies, returning `:ok` or the error.
Headers can be a list of pairs (`conn.req_headers`) or a map; names are matched without regard to
case. `opts` takes `:tolerance` (milliseconds, default `300_000`) and `:now` (Unix milliseconds).

### With the Plug adapter

`Unicom360.Webhook.Plug` verifies, parses and calls your handler. It answers 401 on a verification
failure, 200 after the handler returns `:ok`, and 500 otherwise:

```elixir
defmodule MyApp.WhatsAppEvents do
  @behaviour Unicom360.Webhook.Handler

  @impl true
  def handle_event(%Unicom360.Webhook.MessageStatusEvent{data: data}, _conn) do
    MyApp.Messages.update_status(data.message_id, data.status)
    :ok
  end

  def handle_event(_event, _conn), do: :ok
end

# In a Phoenix router or a Plug.Router:
forward "/webhooks/unicom360/whatsapp", Unicom360.Webhook.Plug,
  secret: {MyApp.Config, :unicom360_webhook_secret, []},  # or a string
  handler: MyApp.WhatsAppEvents
```

### The raw body

The signature covers the exact bytes received, which `Plug.Parsers` consumes. In a Phoenix endpoint
(where the parsers run before the router), keep them with the body reader:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library(),
  body_reader: {Unicom360.Webhook.BodyReader, :read_body, []}
```

The bytes are then in `conn.assigns.raw_body`, where `Unicom360.Webhook.Plug` finds them. A Phoenix
controller without the plug:

```elixir
def whatsapp(conn, _params) do
  case Unicom360.Webhook.construct_event(conn.assigns.raw_body, conn.req_headers, secret()) do
    {:ok, event} ->
      MyApp.WhatsAppEvents.handle_event(event, conn)
      send_resp(conn, 200, "")

    {:error, %Unicom360.Error{type: :signature_verification_error, reason: reason}} ->
      send_resp(conn, 401, Atom.to_string(reason))

    {:error, %Unicom360.Error{}} ->
      send_resp(conn, 400, "not a webhook event")
  end
end
```

Mounted ahead of `Plug.Parsers` (a plain `Plug.Router`), `Unicom360.Webhook.Plug` reads the body by
itself. Full versions: [`examples/phoenix_webhook_controller.ex`](https://github.com/TechRode-Solution-Limited/unicom360-elixir/blob/main/examples/phoenix_webhook_controller.ex),
[`examples/plug_webhook_router.ex`](https://github.com/TechRode-Solution-Limited/unicom360-elixir/blob/main/examples/plug_webhook_router.ex).

Good to know:

* Deliveries are retried on any non-2xx (after 30 s, 2 min, 10 min, 30 min, 1 h, 3 h, 6 h and 12 h).
  Answer 2xx quickly and drop repeats by `event.delivery_id`.
* `verify` rejects a timestamp more than `:tolerance` (five minutes by default) from your clock, in
  either direction.
* In `message.received`: a media caption arrives in `text`, not in `media`; `payload` is set only
  for location, contacts (`%{"contacts" => [...]}`), reaction, sticker and unsupported messages; an
  interactive or button reply has the chosen title in `text`, `payload` is `nil`, and `reply_to` is
  the `wamid.` id of your interactive message (the button or row id is not passed on).

## SMS and email delivery reports

The reports posted to an SMS or email `callback_url` are **unsigned and never retried**, so anyone
can post one: treat them as hints, and confirm anything that matters another way.

```elixir
{:ok, report} = Unicom360.Webhook.parse_sms_callback(raw_body)    # message_id, status, mobile_number
{:ok, report} = Unicom360.Webhook.parse_email_callback(raw_body)  # message_id, status, email_address, message
```

Both return an error of type `:unicom360_error` for a body that is not a JSON object. The email
report's numeric `message_id` becomes the string the send returned.

## GSM-7 helpers

The gateway accepts only GSM-7 text (the basic set plus `^{}\[~]|€`, no form feed), at most 1,200
characters, and bills `max(1, ceil(length / 160))` units per recipient (a CR LF pair counts as one
character). The SDK never checks this itself; these opt-in helpers give the gateway's answers
before you send:

```elixir
alias Unicom360.GSM

GSM.gsm7?("Hello €")           # true
GSM.length("Hi\r\nthere")      # 8
GSM.units(String.duplicate("a", 161))  # 2
GSM.non_gsm_characters("It’s")  # [{"’", 2}]
GSM.validate_sms("It’s ready")  # [:non_gsm]; also :empty and :too_long
```

`GSM.charset/0`, `GSM.max_length/0` and `GSM.unit_length/0` are the gateway's values.

## Configuration

```elixir
Unicom360.client(
  api_key: "...",            # default: the app env, then UNICOM360_API_KEY
  base_url: "...",           # default: the app env, then UNICOM360_BASE_URL, then https://api.unicom360.com
  timeout: 60_000,           # ms to wait for the response on each attempt
  connect_timeout: 10_000,   # ms to connect, TLS included
  max_retries: 2,
  max_retry_wait: 60_000,    # ms
  auto_reference_ids: false,
  app_info: %{name: "shopsync", version: "2.3.0", url: "https://shopsync.example"},
  req_options: []            # extra options for Req: :finch, :connect_options, a custom :adapter...
)
```

All of these can also come from the application environment:

```elixir
# config/runtime.exs
config :unicom360, api_key: System.get_env("UNICOM360_API_KEY")
```

* An option you pass wins over the application environment, which wins over the environment
  variables, which win over the defaults. `nil`, and an environment variable that is empty or blank,
  count as unset.
* A missing or blank API key is a `:configuration_error` when the client is built. An explicit
  `api_key: ""` does not fall back to the environment. `Unicom360.client!/1` raises instead.
* `base_url` must be `https`; plain `http` is allowed only for `localhost`, `127.0.0.0/8` and `::1`
  (for a local mock). A path prefix is kept, trailing slashes are dropped, and a query string or
  fragment is refused.
* A client is an immutable struct, safe to share between processes.
  `Unicom360.Client.put_options(client, timeout: 5_000)` returns a copy with other options.
* `app_info` is appended to the User-Agent
  (`unicom360-elixir/0.1.0 (elixir 1.19.4-otp-28; linux; x86_64) shopsync/2.3.0 (+https://shopsync.example)`).
* The API key never appears in `inspect/2`, in errors or in logs: `inspect(client)` shows
  `api_key: [REDACTED]`.

**Transport.** Requests go through [Req](https://hexdocs.pm/req) (0.5 or later) with
`retry: false` and `redirect: false`. `:req_options` passes anything else through, such as your own Finch pool
(`req_options: [finch: MyApp.Finch]`). A custom adapter can return `Unicom360.TransportError` to
state whether the request may have reached the server (`sent`) and whether it timed out, which is
what the retry rules go by. Without it, the SDK classifies Req's errors: a refused connection or a
DNS failure was never sent; a timeout or a reset may have been.

The `:timeout` is Req's `:receive_timeout`: the wait for data from the socket. A response that
keeps trickling can take longer overall; the gateway's responses are small enough that this makes
no practical difference.

## Testing your code

Pass a `Req.Test` plug as `:plug`, and no request reaches the network:

```elixir
client = Unicom360.client!(api_key: "test", plug: {Req.Test, MyApp.Unicom360})

Req.Test.stub(MyApp.Unicom360, fn conn ->
  Req.Test.json(conn, %{
    success: true,
    message: "successful",
    api_reference: "1",
    data: [%{message_id: "m-1", status: "ACKNOWLEDGED", mobile_number: "260971234567"}]
  })
end)
```

`:clock`, `:sleeper` and `:random` replace the time source, the waits between retries and the jitter.

## Logging

The SDK logs through `Logger`, with the fields in the message and as metadata:

* `:debug`: one line per attempt with the method, path, status (or the transport failure),
  `api_reference`, attempt number and duration, plus any `generated_user_reference_ids`.
* `:info`: one line per scheduled retry with the attempt, the wait (`wait_ms`) and the cause.

Nothing else is logged: never a body, a header, a parameter, a phone number, an address, the API key
or a webhook secret.

## Known differences from the published docs

This SDK follows the gateway's actual behaviour (as written down in `openapi.yaml`). Where the API
reference at unicom360.com/docs says otherwise:

1. **Request-shape errors can carry several messages.** A 400 from the SMS or email endpoint can
   list one message per problem; the error's `message` joins them with `"; "`.
2. **WhatsApp balances are whole numbers today.** The docs say they can be fractional (`37.5`); the
   gateway currently rounds them. Balances are `Decimal`s, so fractional values will work unchanged
   when the gateway sends them.
3. **Local number formats.** Only local numbers starting `095`, `096`, `097` and `076` are
   normalised; another local form (for example `077...`) comes back `Invalid mobile number`. Send
   international numbers (`2609...`).
4. **The SMS and email `callback_url` is not validated** by the gateway (the WhatsApp one is).
5. **The WhatsApp `callback_url` limit of 300 is in bytes**, so a non-ASCII URL reaches it sooner.
6. **A session `text` that is only whitespace is refused**, like an empty one.
7. **The health `timestamp` has microseconds** (`...30.412345Z`), not milliseconds.
8. **A session `DuplicateReferenceError` can have `original_message_id: nil`** when two requests
   race for the same reference.
9. **Rejected template recipients echo the request's values**, which can be numbers; the SDK always
   gives `to` and `user_reference_id` as strings.
10. **The balance endpoints can refuse with `CLIENT_NOT_FOUND`** (HTTP 200, `status: false`, no
    `api_reference`), returned as an `:api_error`.
11. **An email `user_reference_id` does not stop two overlapping requests** from both being accepted
    (a sequential repeat is refused). That is why email is never retried after the request may have
    reached the gateway.

## Versioning

The SDK follows [Semantic Versioning](https://semver.org/) and starts at 0.1.0; 1.0.0 follows once
live use shows no differences from the spec. Changes are listed in [CHANGELOG.md](CHANGELOG.md).
Security reports: see [SECURITY.md](https://github.com/TechRode-Solution-Limited/unicom360-elixir/blob/main/SECURITY.md). Contributing: see
[CONTRIBUTING.md](https://github.com/TechRode-Solution-Limited/unicom360-elixir/blob/main/CONTRIBUTING.md).

## Licence

MIT, see [LICENSE](https://github.com/TechRode-Solution-Limited/unicom360-elixir/blob/main/LICENSE). Copyright (c) 2026 Techrode Solutions Limited.
