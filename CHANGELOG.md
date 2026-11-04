# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-04

First release, targeting the Unicom360 API contract v0.1.0.

### Added

- `Unicom360.client/1` and an immutable `%Unicom360.Client{}`, with options from the keyword
  list, the application environment and the environment variables.
- Every operation of the public API, each returning `{:ok, result}` or
  `{:error, %Unicom360.Error{}}` with a `!` variant: `Unicom360.SMS.send/3`,
  `Unicom360.Email.send/3`, `Unicom360.WhatsApp.send_template/3`,
  `Unicom360.WhatsApp.send_session/3`, `Unicom360.WhatsApp.status/3`,
  `Unicom360.WhatsApp.templates/2`, `Unicom360.Balance.get/2`, `Unicom360.Balance.all/2` and
  `Unicom360.health/2`.
- Typed result structs that keep unknown fields (`extra`) and the parsed JSON (`raw`), with lookup
  helpers (`by_number`, `by_address`, `by_id`, `by_name`, `accepted`, `invalid`, `rejected`).
  Balances are `Decimal`s.
- Builders for template parameters (`TemplateHeader`, `TemplateBody`, `TemplateButton`,
  `TemplateRecipient`) and session messages (`Unicom360.WhatsApp.Session`).
- One error struct, `%Unicom360.Error{}`, with `Unicom360.Error.class/1` naming the canonical error
  classes, and codes normalised from the gateway's messages (`Unicom360.Codes`).
- Safe automatic retries (429, failures before sending, and 5xx, failures after sending and
  `SEND_FAILED` on retry-safe calls only), with UTC-minute waits after a 429 and full-jitter
  backoff otherwise; the `auto_reference_ids` option.
- Webhook verification and parsing (`Unicom360.Webhook.verify/4`, `construct_event/4`), the unsigned
  SMS and email delivery reports (`parse_sms_callback/1`, `parse_email_callback/1`), and the
  optional Plug adapter (`Unicom360.Webhook.Plug`, `Unicom360.Webhook.BodyReader`). A secret that is
  `nil`, empty or only whitespace is a `:configuration_error` before any other check, because anyone
  can forge a signature with an empty key; the plug raises in `init/1` for a string, and answers 500
  without calling the handler for an `{m, f, a}`.
- Opt-in GSM-7 helpers (`Unicom360.GSM`).
- Requests through Req with its retries and redirects off, a transport seam through `:plug` and
  `:req_options`, and `Unicom360.TransportError` for custom adapters.
- Logging through `Logger`, with the API key and webhook secrets redacted everywhere.
- The contract's conformance suite (v0.1.0), a Prism contract test, examples for every operation
  and webhook receivers for Phoenix and plain Plug.

[0.1.0]: https://github.com/TechRode-Solution-Limited/unicom360-elixir/releases/tag/v0.1.0
