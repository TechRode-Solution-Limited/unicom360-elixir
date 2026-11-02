if Code.ensure_loaded?(Plug.Conn) do
  defmodule Unicom360.Webhook.Plug do
    @moduledoc """
    A plug that receives Unicom360 webhooks: it verifies the signature, parses the event and
    calls your handler.

        # In a Phoenix router (or a Plug.Router):
        forward "/webhooks/unicom360/whatsapp", Unicom360.Webhook.Plug,
          secret: {MyApp.Config, :unicom360_webhook_secret, []},
          handler: MyApp.WhatsAppEvents

    Options:

      * `:secret` (required) - the 43-character string from the portal, or `{module, function,
        args}` called on each request. Prefer the tuple, so the secret is not compiled into your
        router.
      * `:handler` (required) - a module implementing `Unicom360.Webhook.Handler`.
      * `:tolerance` - the largest clock skew accepted, in milliseconds. Default `300_000`.

    It answers:

      * 200 when the handler returns `:ok`;
      * 401 with the failure's reason as the body, when verification fails;
      * 400 when the body cannot be read, or a verified body is not a JSON object with an event;
      * 413 when the body is over 1 MiB (only when this plug reads the body itself);
      * 500 when the handler returns anything else.

    ## The raw body

    Signatures cover the exact bytes received. Mount this plug ahead of `Plug.Parsers` and it
    reads the body itself. Behind `Plug.Parsers`, add `Unicom360.Webhook.BodyReader` as the
    parsers' `:body_reader`, and this plug uses `conn.assigns.raw_body`.
    """

    @behaviour Plug

    import Plug.Conn

    alias Unicom360.{Error, Webhook}

    require Logger

    @max_body 1_048_576

    @enforce_keys [:secret, :handler, :tolerance]
    defstruct [:secret, :handler, :tolerance]

    @typep t :: %__MODULE__{
             secret: String.t() | {module(), atom(), [term()]},
             handler: module(),
             tolerance: non_neg_integer()
           }

    @impl true
    @spec init(keyword()) :: t()
    def init(opts) do
      opts = validate_keys!(opts)

      if not valid_secret?(opts[:secret]) do
        raise ArgumentError,
              "Unicom360.Webhook.Plug needs :secret, a string or a {module, function, args} tuple"
      end

      if not (is_atom(opts[:handler]) and not is_nil(opts[:handler])) do
        raise ArgumentError, "Unicom360.Webhook.Plug needs :handler, a module"
      end

      if not (is_integer(opts[:tolerance]) and opts[:tolerance] >= 0) do
        raise ArgumentError, "Unicom360.Webhook.Plug: :tolerance must be milliseconds"
      end

      struct!(__MODULE__, opts)
    end

    # Not Keyword.validate!/2: its message prints the options, and so the secret.
    defp validate_keys!(opts) do
      case Keyword.validate(opts, [:secret, :handler, tolerance: 300_000]) do
        {:ok, opts} -> opts
        {:error, keys} -> raise ArgumentError, "Unicom360.Webhook.Plug: unknown #{inspect(keys)}"
      end
    end

    @impl true
    @spec call(Plug.Conn.t(), t()) :: Plug.Conn.t()
    def call(conn, %__MODULE__{} = opts) do
      case raw_body(conn) do
        {:ok, body, conn} -> receive_event(conn, body, opts)
        {:too_large, conn} -> answer(conn, 413, "body too large")
        :unreadable -> answer(conn, 400, "could not read the body")
      end
    end

    defp receive_event(conn, body, opts) do
      secret = secret(opts.secret)

      case Webhook.construct_event(body, conn.req_headers, secret, tolerance: opts.tolerance) do
        {:ok, event} ->
          case opts.handler.handle_event(event, conn) do
            :ok -> answer(conn, 200, "")
            _other -> answer(conn, 500, "")
          end

        {:error, %Error{type: :signature_verification_error, reason: reason}} ->
          answer(conn, 401, Atom.to_string(reason))

        {:error, %Error{}} ->
          answer(conn, 400, "not a webhook event")
      end
    end

    defp answer(conn, status, body), do: conn |> send_resp(status, body) |> halt()

    defp raw_body(%Plug.Conn{assigns: %{raw_body: body}} = conn) when is_binary(body),
      do: {:ok, body, conn}

    defp raw_body(conn) do
      case read_body(conn, length: @max_body) do
        {:ok, body, conn} ->
          warn_if_consumed(conn, body)
          {:ok, body, conn}

        {:more, _partial, conn} ->
          {:too_large, conn}

        {:error, _reason} ->
          :unreadable
      end
    end

    defp warn_if_consumed(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}, _body), do: :ok

    defp warn_if_consumed(_conn, "") do
      Logger.warning(
        "Unicom360.Webhook.Plug found no body: Plug.Parsers already read it. Add " <>
          "body_reader: {Unicom360.Webhook.BodyReader, :read_body, []} to Plug.Parsers"
      )
    end

    defp warn_if_consumed(_conn, _body), do: :ok

    defp secret({module, function, args}), do: apply(module, function, args)
    defp secret(secret), do: secret

    defp valid_secret?(secret) when is_binary(secret), do: secret != ""

    defp valid_secret?({module, function, args}),
      do: is_atom(module) and is_atom(function) and is_list(args)

    defp valid_secret?(_secret), do: false

    defimpl Inspect do
      def inspect(plug, _opts) do
        "#Unicom360.Webhook.Plug<secret: [REDACTED], handler: #{Kernel.inspect(plug.handler)}, " <>
          "tolerance: #{plug.tolerance}>"
      end
    end
  end
end
