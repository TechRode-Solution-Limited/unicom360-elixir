defmodule Unicom360.TransportError do
  @moduledoc """
  A transport failure that states the two facts the retry rules need.

  The SDK classifies Req's own errors itself (a refused connection or a DNS failure was never
  sent; a timeout or a reset may have been). A custom Req adapter (the `:adapter` entry of the
  client's `:req_options`) that knows better can return this exception instead of a response,
  to say exactly what happened:

    * `sent`: whether any byte of the request may have reached the server. Say `true` when you
      cannot tell.
    * `timeout`: whether the failure was a timeout.

  A failure with `sent: false` is always retried. One with `sent: true` is retried only when the
  call is safe to retry (see the README's Retries section).

      defmodule MyAdapter do
        def run(request) do
          {request, %Unicom360.TransportError{reason: :econnrefused, sent: false, timeout: false}}
        end
      end

      # On Req 0.5 and 0.6, an adapter is a function: adapter: &MyAdapter.run/1
      Unicom360.client(api_key: "...", req_options: [adapter: MyAdapter])
  """

  @type t :: %__MODULE__{reason: term(), sent: boolean(), timeout: boolean()}

  defexception reason: :unknown, sent: true, timeout: false

  @impl true
  def message(%__MODULE__{reason: reason, sent: sent, timeout: timeout}) do
    "transport failure: #{inspect(reason)} (sent: #{sent}, timeout: #{timeout})"
  end
end
