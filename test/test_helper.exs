# The contract tests need a running Prism mock; see CONTRIBUTING.md.
ExUnit.start(exclude: [:contract], capture_log: true)
