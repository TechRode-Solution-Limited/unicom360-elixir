defmodule Unicom360.ContractTest do
  @moduledoc """
  The contract test: every call in `requests.json` against a Prism mock of `openapi.yaml`.

  Not part of the default run. Start Prism, then run the `:contract` tag:

      docker run --rm -p 4014:4010 -v "$OPENAPI_DIR":/spec:ro stoplight/prism:5 \\
        mock --multiprocess=false --errors -h 0.0.0.0 /spec/openapi.yaml
      UNICOM360_CONTRACT_BASE_URL=http://127.0.0.1:4014 mix test --only contract

  With `--errors`, Prism answers a request it rejects with an error status, and it reports every
  problem in an `sl-violations` header. Either one fails the test. Requests go through the real
  transport (Req and Finch), and the example Prism answers with must parse into a result.
  """
  use ExUnit.Case, async: false

  @moduletag :contract

  alias Unicom360.Test.Conformance
  alias Unicom360.WhatsApp.Session

  @base_url System.get_env("UNICOM360_CONTRACT_BASE_URL", "http://127.0.0.1:4014")

  # Finch's own telemetry shows the response headers of real requests; the SDK's result does not.
  setup do
    test_pid = self()
    handler = "unicom360-contract-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:finch, :recv, :stop],
        fn _event, _measurements, metadata, _config ->
          if self() == test_pid do
            send(test_pid, {:response, metadata[:status], metadata[:headers]})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp client(options \\ []) do
    Unicom360.client!(
      [api_key: "contract-test-key", base_url: @base_url, max_retries: 0] ++ options
    )
  end

  defp assert_conforms do
    assert_received {:response, status, headers}
    assert status in 200..299, "HTTP #{status}"
    refute List.keymember?(headers, "sl-violations", 0), inspect(headers)
  end

  test "Prism is reachable" do
    assert {:ok, %Unicom360.Health{status: status}} = Unicom360.health(client())
    assert is_binary(status)
    assert_conforms()
  end

  for vector <- Conformance.vectors("requests.json") do
    @vector vector
    test "#{vector["id"]}" do
      vector = @vector
      result = Conformance.call(client(), vector["operation"], vector["params"])
      assert {:ok, parsed} = result
      assert is_map(parsed.raw)
      assert_conforms()
    end
  end

  test "an invalid request fails, so these tests can tell the difference" do
    # No `to`: Prism answers with the spec's error, not an example.
    assert {:error, %Unicom360.Error{http_status: status}} =
             Unicom360.WhatsApp.send_session(client(), %{"type" => "text", "text" => "Hi"})

    assert status not in 200..299
  end

  test "every operation is covered" do
    covered = Conformance.vectors("requests.json") |> Enum.map(& &1["operation"]) |> Enum.uniq()
    assert Enum.sort(covered) == Enum.sort(Conformance.operations())
  end

  test "generated references conform" do
    client = client(auto_reference_ids: true)

    assert {:ok, _} =
             Unicom360.SMS.send(client, %{
               from: "Unicom360",
               to: "260971234567",
               message: "Your order is ready."
             })

    assert_conforms()

    assert {:ok, _} =
             Unicom360.Email.send(client, %{
               from: "noreply@example.com",
               to: "jane@example.com",
               subject: "Hi",
               email_body: "<p>Hi</p>"
             })

    assert_conforms()

    assert {:ok, _} =
             Unicom360.WhatsApp.send_session(
               client,
               Session.text("260971234567", "Your order is ready.")
             )

    assert_conforms()
  end
end
