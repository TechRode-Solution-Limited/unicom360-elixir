%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "examples/", "mix.exs"],
        excluded: ["test/fixtures/"]
      },
      strict: true,
      checks: %{
        disabled: [
          # For applications: a library's users choose their own Logger metadata.
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []}
        ]
      }
    }
  ]
}
