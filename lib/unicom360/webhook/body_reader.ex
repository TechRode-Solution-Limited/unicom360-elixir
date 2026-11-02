if Code.ensure_loaded?(Plug.Conn) do
  defmodule Unicom360.Webhook.BodyReader do
    @moduledoc """
    A `Plug.Parsers` body reader that keeps the raw body in `conn.assigns.raw_body`.

    Webhook signatures cover the exact bytes received, which `Plug.Parsers` consumes. Tell it to
    read through this module:

        plug Plug.Parsers,
          parsers: [:urlencoded, :multipart, :json],
          pass: ["*/*"],
          json_decoder: Jason,
          body_reader: {Unicom360.Webhook.BodyReader, :read_body, []}

    Then `conn.assigns.raw_body` holds the bytes for `Unicom360.Webhook.construct_event/4`, and
    `Unicom360.Webhook.Plug` finds them there by itself.

    This keeps a copy of every parsed body in memory for the length of its request. To limit
    that to the webhook route, mount a separate `Plug.Parsers` (or `Unicom360.Webhook.Plug`
    alone) ahead of the general one.
    """

    @doc """
    Reads like `Plug.Conn.read_body/2`, appending what it read to `conn.assigns.raw_body`.
    """
    @spec read_body(Plug.Conn.t(), keyword()) ::
            {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
    def read_body(conn, opts) do
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} -> {:ok, body, keep(conn, body)}
        {:more, body, conn} -> {:more, body, keep(conn, body)}
        {:error, _reason} = error -> error
      end
    end

    defp keep(conn, chunk) do
      Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> chunk)
    end
  end
end
