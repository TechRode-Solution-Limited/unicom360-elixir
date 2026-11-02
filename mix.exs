defmodule Unicom360.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/TechRode-Solution-Limited/unicom360-elixir"

  def project do
    [
      app: :unicom360,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Unicom360",
      description: "The official Elixir client for the Unicom360 SMS, email and WhatsApp API.",
      source_url: @source_url,
      homepage_url: "https://unicom360.com",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:plug, :mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        flags: [:error_handling, :extra_return, :missing_return, :underspecs, :unmatched_returns]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  # The examples are compiled (and run) with the tests, so CI proves they still build.
  defp elixirc_paths(:test), do: ["lib", "test/support", "examples"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:plug, "~> 1.14", optional: true},

      # Compile the Phoenix controller example; never runtime dependencies. phoenix_template
      # 1.1 needs Elixir 1.16, so the test-only pin keeps the suite running on Elixir 1.15.
      {:phoenix, "~> 1.7", only: :test},
      {:phoenix_template, "~> 1.0.4", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "API reference" => "https://unicom360.com/docs"
      },
      # An explicit list, so the vendored conformance fixtures, tests and examples never ship.
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Client: [Unicom360, Unicom360.Client, Unicom360.Error, Unicom360.Codes],
        Operations: [Unicom360.SMS, Unicom360.Email, Unicom360.WhatsApp, Unicom360.Balance],
        "WhatsApp builders": [
          Unicom360.WhatsApp.Session,
          Unicom360.WhatsApp.SessionMessage,
          Unicom360.WhatsApp.ReplyButton,
          Unicom360.WhatsApp.ListSection,
          Unicom360.WhatsApp.ListRow,
          Unicom360.WhatsApp.TemplateRecipient,
          Unicom360.WhatsApp.TemplateHeader,
          Unicom360.WhatsApp.TemplateBody,
          Unicom360.WhatsApp.TemplateButton
        ],
        Results: [
          Unicom360.SMS.SendResult,
          Unicom360.SMS.Result,
          Unicom360.Email.SendResult,
          Unicom360.Email.Result,
          Unicom360.WhatsApp.TemplateSendResult,
          Unicom360.WhatsApp.TemplateResult,
          Unicom360.WhatsApp.SessionSendResult,
          Unicom360.WhatsApp.StatusResult,
          Unicom360.WhatsApp.MessageStatus,
          Unicom360.WhatsApp.MessageError,
          Unicom360.WhatsApp.TemplateList,
          Unicom360.WhatsApp.TemplateInfo,
          Unicom360.WhatsApp.TemplateInfo.Header,
          Unicom360.WhatsApp.TemplateInfo.Body,
          Unicom360.WhatsApp.TemplateInfo.Authentication,
          Unicom360.WhatsApp.TemplateButtonInfo,
          Unicom360.Balances,
          Unicom360.Health
        ],
        Webhooks: [
          Unicom360.Webhook,
          Unicom360.Webhook.Plug,
          Unicom360.Webhook.BodyReader,
          Unicom360.Webhook.Handler,
          Unicom360.Webhook.MessageStatusEvent,
          Unicom360.Webhook.MessageStatusData,
          Unicom360.Webhook.MessageReceivedEvent,
          Unicom360.Webhook.InboundMessage,
          Unicom360.Webhook.InboundMedia,
          Unicom360.Webhook.TestEvent,
          Unicom360.Webhook.TestEventData,
          Unicom360.Webhook.UnknownEvent,
          Unicom360.Webhook.SmsDeliveryReport,
          Unicom360.Webhook.EmailDeliveryReport
        ],
        Utilities: [Unicom360.GSM, Unicom360.TransportError]
      ]
    ]
  end
end
