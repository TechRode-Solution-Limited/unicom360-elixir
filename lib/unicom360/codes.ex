defmodule Unicom360.Codes do
  @moduledoc """
  The normalised error codes, and the function that derives them from the gateway's messages.

  The gateway answers a refusal with a message that is sometimes a code
  (`"INSUFFICIENT_BUNDLE"`) and sometimes a sentence (`"Invalid From Sender ID"`).
  `normalize/1` turns both into one code, so `%Unicom360.Error{code: code}` compares the same way
  whichever form the gateway used:

      iex> Unicom360.Codes.normalize("Invalid From Sender ID")
      "INVALID_SENDER_ID"
      iex> Unicom360.Codes.normalize("DUPLICATE_MSG_REF")
      "DUPLICATE_REFERENCE"
      iex> Unicom360.Codes.normalize("INSUFFICIENT_BUNDLE: no international SMS bundle")
      "INSUFFICIENT_BUNDLE"
      iex> Unicom360.Codes.normalize("SOME_FUTURE_CODE")
      "SOME_FUTURE_CODE"
      iex> Unicom360.Codes.normalize("Missing required keys: [\\"message\\"]")
      "UNKNOWN"

  Codes are plain strings, so a code this version does not know passes through unchanged. Each
  known code also has a function returning it (`Unicom360.Codes.insufficient_bundle/0` returns
  `"INSUFFICIENT_BUNDLE"`), and `known/0` lists them all. In a pattern, match the string itself:

      case Unicom360.SMS.send(client, params) do
        {:ok, result} -> result
        {:error, %Unicom360.Error{code: "INSUFFICIENT_BUNDLE"}} -> top_up()
      end
  """

  @aliases %{
    "Invalid From Sender ID" => "INVALID_SENDER_ID",
    "Invalid Sender" => "INVALID_SENDER_ID",
    "From Sender ID not allowed" => "SENDER_ID_NOT_ALLOWED",
    "Sender not allowed" => "SENDER_ID_NOT_ALLOWED",
    "Recipient list size is invalid" => "INVALID_RECIPIENT_LIMIT",
    "Invalid Recipient Limit" => "INVALID_RECIPIENT_LIMIT",
    "INSUFFICIENT_BUNDLE: no international SMS bundle" => "INSUFFICIENT_BUNDLE",
    "Insufficient bundle" => "INSUFFICIENT_BUNDLE",
    "INSUFFICIENT_BUNDLE_LIMIT" => "INSUFFICIENT_BUNDLE",
    "duplicate user reference id" => "DUPLICATE_REFERENCE",
    "DUPLICATE_MSG_REF" => "DUPLICATE_REFERENCE",
    "Invalid parameters provided" => "INVALID_PARAMETERS",
    "Missing API key. Provide X-API-Key header or Authorization: Bearer <api_key>" =>
      "MISSING_API_KEY",
    "Invalid authorization format. Use 'Bearer <api_key>' or 'Basic <base64>'" =>
      "INVALID_AUTHORIZATION",
    "Invalid Basic auth format. Use api_key as username" => "INVALID_AUTHORIZATION",
    "Invalid Base64 encoding in Basic auth" => "INVALID_AUTHORIZATION"
  }

  @known ~w(
    INVALID_SENDER_ID SENDER_ID_NOT_ALLOWED INVALID_RECIPIENT_LIMIT INSUFFICIENT_BUNDLE
    DUPLICATE_REFERENCE INVALID_PARAMETERS SENDER_REQUIRED TEMPLATE_NOT_FOUND
    TEMPLATE_NOT_APPROVED LANGUAGE_REQUIRED TEMPLATE_SENDER_MISMATCH NO_VALID_RECIPIENTS
    SEND_FAILED SESSION_WINDOW_CLOSED REPLY_TO_NOT_FOUND REACTION_TARGET_NOT_FOUND INVALID_NUMBER
    INVALID_USER_REFERENCE_ID MEDIA_URL_INVALID CLIENT_NOT_FOUND MISSING_API_KEY
    INVALID_AUTHORIZATION AUTHENTICATION_FAILED CREDENTIAL_DISABLED CLIENT_DISABLED
    CREDENTIAL_EXPIRED IP_NOT_ALLOWED RATE_LIMIT_EXCEEDED UNKNOWN
  )

  # The white space JavaScript's `\s` matches, which the contract's reference implementation uses.
  @white_space [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F] ++
                 [0x205F, 0x3000, 0xFEFF] ++ Enum.to_list(0x2000..0x200A)

  @doc """
  Normalises a gateway message to an error code.

  The first matching rule wins: an exact match in the alias table; a message that is itself a
  code (`^[A-Z][A-Z0-9_]*$`, aliased when the table has it); a message that starts with a code
  followed by a colon and white space (the code, aliased when the table has it); otherwise
  `"UNKNOWN"`. Matching is exact and case-sensitive. Anything that is not a string is
  `"UNKNOWN"`.
  """
  @spec normalize(term()) :: String.t()
  def normalize(message) when is_binary(message) do
    cond do
      Map.has_key?(@aliases, message) ->
        Map.fetch!(@aliases, message)

      code?(message) ->
        message

      code = prefix_code(message) ->
        Map.get(@aliases, code, code)

      true ->
        "UNKNOWN"
    end
  end

  def normalize(_message), do: "UNKNOWN"

  # `^[A-Z][A-Z0-9_]*$`
  defp code?(<<first, rest::binary>>) when first in ?A..?Z, do: code_tail?(rest)
  defp code?(_text), do: false

  defp code_tail?(<<>>), do: true

  defp code_tail?(<<c, rest::binary>>) when c in ?A..?Z or c in ?0..?9 or c == ?_,
    do: code_tail?(rest)

  defp code_tail?(_text), do: false

  # `^([A-Z][A-Z0-9_]*):\s`: the code before the first colon, when white space follows it.
  defp prefix_code(message) do
    with [code, <<space::utf8, _rest::binary>>] <- :binary.split(message, ":"),
         true <- space in @white_space,
         true <- code?(code) do
      code
    else
      _ -> nil
    end
  end

  @doc """
  Every code this version documents, as strings.
  """
  @spec known() :: [String.t()]
  def known, do: @known

  for code <- @known do
    @doc "Returns `#{inspect(code)}`."
    @spec unquote(code |> String.downcase() |> String.to_atom())() :: String.t()
    def unquote(code |> String.downcase() |> String.to_atom())(), do: unquote(code)
  end
end
