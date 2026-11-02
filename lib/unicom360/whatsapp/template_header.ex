defmodule Unicom360.WhatsApp.TemplateHeader do
  @moduledoc """
  A template recipient's header parameter.

      TemplateHeader.text("Ada")
      TemplateHeader.image("https://example.com/receipts/ZM-4821.png")
      TemplateHeader.video("https://example.com/promo.mp4")
      TemplateHeader.document("https://example.com/invoices/4821.pdf", "invoice-4821.pdf")

  A text header is sent as a JSON string, a media header as `{"type", "url", "filename"?}`. A
  recipient may also give a plain string or a map in that shape.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          value: String.t() | nil,
          url: String.t() | nil,
          filename: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :value, :url, :filename]

  @doc "A text header (the template's `{{1}}` in its header)."
  @spec text(String.t()) :: t()
  def text(value), do: %__MODULE__{type: "text", value: value}

  @doc "An image header."
  @spec image(String.t()) :: t()
  def image(url), do: %__MODULE__{type: "image", url: url}

  @doc "A video header."
  @spec video(String.t()) :: t()
  def video(url), do: %__MODULE__{type: "video", url: url}

  @doc "A document header, with an optional file name shown to the recipient."
  @spec document(String.t(), String.t() | nil) :: t()
  def document(url, filename \\ nil),
    do: %__MODULE__{type: "document", url: url, filename: filename}

  @doc false
  @spec to_api(t() | String.t() | map()) :: String.t() | map()
  def to_api(%__MODULE__{type: "text", value: value}), do: value

  def to_api(%__MODULE__{type: type, url: url, filename: filename}),
    do: Unicom360.Params.compact(type: type, url: url, filename: filename)

  def to_api(value) when is_binary(value), do: value
  def to_api(value) when is_map(value), do: Unicom360.Params.compact(value)
end
