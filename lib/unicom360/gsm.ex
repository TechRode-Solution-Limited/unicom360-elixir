defmodule Unicom360.GSM do
  @moduledoc """
  Opt-in GSM-7 helpers: the gateway's own answers about an SMS text, before you send it.

  The gateway accepts only GSM-7 text (the GSM basic set plus `^{}\\[~]|€`, with no form feed),
  at most 1,200 characters, and bills `max(1, ceil(length / 160))` units per recipient, where a
  CR LF pair counts as one character. The SDK never checks this when sending; these helpers do
  it when you ask:

      iex> Unicom360.GSM.gsm7?("Hello €")
      true
      iex> Unicom360.GSM.length("Hi\\r\\nthere")
      8
      iex> Unicom360.GSM.units(String.duplicate("a", 161))
      2
      iex> Unicom360.GSM.non_gsm_characters("It’s")
      [{"’", 2}]
      iex> Unicom360.GSM.validate_sms("It’s ready")
      [:non_gsm]

  Characters are Unicode code points (an emoji is one), not bytes.
  """

  import Kernel, except: [length: 1]

  # sms_part_counter 0.1.7's set, verbatim from the contract's gsm7.json.
  @charset "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà^{}\\[~]|€"

  @max_length 1200
  @unit_length 160

  @typedoc "A problem `validate_sms/1` reports: `:empty`, `:too_long` or `:non_gsm`."
  @type issue :: :empty | :too_long | :non_gsm

  @doc "The gateway's GSM-7 character set, as one string."
  @spec charset() :: String.t()
  def charset, do: @charset

  @doc "The longest text the gateway accepts, in characters (`1200`)."
  @spec max_length() :: 1200
  def max_length, do: @max_length

  @doc "The characters per billing unit (`160`)."
  @spec unit_length() :: 160
  def unit_length, do: @unit_length

  @doc """
  Whether every character of `text` is in the gateway's GSM-7 set. `""` is GSM-7.
  """
  @spec gsm7?(String.t()) :: boolean()
  def gsm7?(text) when is_binary(text), do: text |> String.to_charlist() |> Enum.all?(&gsm?/1)

  @doc """
  The length the gateway counts: code points, with each CR LF pair (`"\\r\\n"`) counted once.
  """
  @spec length(String.t()) :: non_neg_integer()
  def length(text) when is_binary(text), do: count(String.to_charlist(text), 0)

  defp count([?\r, ?\n | rest], acc), do: count(rest, acc + 1)
  defp count([_char | rest], acc), do: count(rest, acc + 1)
  defp count([], acc), do: acc

  @doc """
  The billing units per recipient: `max(1, ceil(length / 160))`. These are not GSM segments.
  """
  @spec units(String.t()) :: pos_integer()
  def units(text) when is_binary(text),
    do: max(1, div(length(text) + @unit_length - 1, @unit_length))

  @doc """
  Every character outside the GSM-7 set, in order, as `{character, index}` with `index` the
  0-based code point position (here a CR LF pair counts as two).
  """
  @spec non_gsm_characters(String.t()) :: [{String.t(), non_neg_integer()}]
  def non_gsm_characters(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.with_index()
    |> Enum.reject(fn {char, _index} -> gsm?(char) end)
    |> Enum.map(fn {char, index} -> {<<char::utf8>>, index} end)
  end

  @doc """
  The problems the gateway would refuse `text` for, in this order: `:empty` (empty, or only
  spaces, tabs, CR and LF), `:too_long` (more than 1,200 characters), `:non_gsm`. An empty list
  means the gateway would accept the text.
  """
  @spec validate_sms(String.t()) :: [issue()]
  def validate_sms(text) when is_binary(text) do
    [
      {:empty, blank?(text)},
      {:too_long, length(text) > @max_length},
      {:non_gsm, not gsm7?(text)}
    ]
    |> Enum.filter(fn {_issue, found} -> found end)
    |> Enum.map(fn {issue, _found} -> issue end)
  end

  defp blank?(<<char, rest::binary>>) when char in [?\s, ?\t, ?\r, ?\n], do: blank?(rest)
  defp blank?(<<>>), do: true
  defp blank?(_text), do: false

  for char <- Enum.uniq(String.to_charlist(@charset)) do
    defp gsm?(unquote(char)), do: true
  end

  defp gsm?(_char), do: false
end
