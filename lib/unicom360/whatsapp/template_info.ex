defmodule Unicom360.WhatsApp.TemplateInfo do
  @moduledoc """
  An approved WhatsApp template, as `Unicom360.WhatsApp.templates/2` lists it.

    * `name`, `language`, `category`, `from` (the WhatsApp number it belongs to).
    * `header` - a `Unicom360.WhatsApp.TemplateInfo.Header` (`type`, `variables`) or `nil`.
    * `body` - a `Unicom360.WhatsApp.TemplateInfo.Body` (`text`, `variables`).
    * `footer` - text or `nil`.
    * `buttons` - a list of `Unicom360.WhatsApp.TemplateButtonInfo`.
    * `authentication` - a `Unicom360.WhatsApp.TemplateInfo.Authentication`
      (`otp_type`, `code_expiration_minutes`) or `nil`.
    * `raw`, `extra` - the JSON object, and the members this version does not model.
  """

  alias Unicom360.WhatsApp.TemplateButtonInfo
  alias Unicom360.WhatsApp.TemplateInfo.{Authentication, Body, Header}

  @fields [
    name: :any,
    language: :any,
    category: :any,
    from: :any,
    header: {:model, Header},
    body: {:model, Body},
    footer: :any,
    buttons: {:list, TemplateButtonInfo},
    authentication: {:model, Authentication}
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          language: String.t() | nil,
          category: String.t() | nil,
          from: String.t() | nil,
          header: Header.t() | nil,
          body: Body.t() | nil,
          footer: String.t() | nil,
          buttons: [TemplateButtonInfo.t()] | nil,
          authentication: Authentication.t() | nil,
          raw: map(),
          extra: map()
        }

  defstruct name: nil,
            language: nil,
            category: nil,
            from: nil,
            header: nil,
            body: nil,
            footer: nil,
            buttons: nil,
            authentication: nil,
            raw: %{},
            extra: %{}

  @doc false
  @spec from_map(term()) :: t()
  def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)

  defmodule Header do
    @moduledoc "A template's header: its `type` and the names of its `variables`."
    @fields [type: :any, variables: :any]
    @type t :: %__MODULE__{
            type: String.t() | nil,
            variables: [String.t()] | nil,
            raw: map(),
            extra: map()
          }
    defstruct type: nil, variables: nil, raw: %{}, extra: %{}

    @doc false
    @spec from_map(term()) :: t()
    def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
  end

  defmodule Body do
    @moduledoc "A template's body: its `text` and the names of its `variables`."
    @fields [text: :any, variables: :any]
    @type t :: %__MODULE__{
            text: String.t() | nil,
            variables: [String.t()] | nil,
            raw: map(),
            extra: map()
          }
    defstruct text: nil, variables: nil, raw: %{}, extra: %{}

    @doc false
    @spec from_map(term()) :: t()
    def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
  end

  defmodule Authentication do
    @moduledoc "An authentication template's `otp_type` and `code_expiration_minutes`."
    @fields [otp_type: :any, code_expiration_minutes: :any]
    @type t :: %__MODULE__{
            otp_type: String.t() | nil,
            code_expiration_minutes: integer() | nil,
            raw: map(),
            extra: map()
          }
    defstruct otp_type: nil, code_expiration_minutes: nil, raw: %{}, extra: %{}

    @doc false
    @spec from_map(term()) :: t()
    def from_map(map), do: Unicom360.Model.decode(__MODULE__, @fields, map)
  end
end
