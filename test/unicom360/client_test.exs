defmodule Unicom360.ClientTest do
  # Not async: these tests set environment variables and application config.
  use ExUnit.Case, async: false

  alias Unicom360.{Client, Error}

  setup do
    previous = %{
      key: System.get_env("UNICOM360_API_KEY"),
      url: System.get_env("UNICOM360_BASE_URL")
    }

    System.delete_env("UNICOM360_API_KEY")
    System.delete_env("UNICOM360_BASE_URL")

    on_exit(fn ->
      restore("UNICOM360_API_KEY", previous.key)
      restore("UNICOM360_BASE_URL", previous.url)
      Application.delete_env(:unicom360, :api_key)
      Application.delete_env(:unicom360, :base_url)
      Application.delete_env(:unicom360, :timeout)
    end)
  end

  defp restore(name, nil), do: System.delete_env(name)
  defp restore(name, value), do: System.put_env(name, value)

  describe "api_key" do
    test "a missing key is a configuration error" do
      assert {:error, %Error{type: :configuration_error} = error} = Unicom360.client()
      assert Error.class(error) == "ConfigurationError"
    end

    test "client!/1 raises it" do
      assert_raise Error, ~r/no API key/, fn -> Unicom360.client!() end
    end

    test "an explicit argument wins over the environment" do
      System.put_env("UNICOM360_API_KEY", "from-env")
      assert {:ok, %Client{api_key: "explicit"}} = Unicom360.client(api_key: "explicit")
    end

    test "the environment variable is read" do
      System.put_env("UNICOM360_API_KEY", "from-env")
      assert {:ok, %Client{api_key: "from-env"}} = Unicom360.client()
    end

    test "the application environment wins over the environment variable" do
      System.put_env("UNICOM360_API_KEY", "from-env")
      Application.put_env(:unicom360, :api_key, "from-config")
      assert {:ok, %Client{api_key: "from-config"}} = Unicom360.client()
    end

    test "an explicit empty string counts as given and fails" do
      System.put_env("UNICOM360_API_KEY", "from-env")
      assert {:error, %Error{type: :configuration_error}} = Unicom360.client(api_key: "")
      assert {:error, %Error{type: :configuration_error}} = Unicom360.client(api_key: "   ")
    end

    test "nil counts as unset" do
      System.put_env("UNICOM360_API_KEY", "from-env")
      assert {:ok, %Client{api_key: "from-env"}} = Unicom360.client(api_key: nil)
    end

    test "an empty or blank environment variable counts as unset" do
      for value <- ["", "   "] do
        System.put_env("UNICOM360_API_KEY", value)
        assert {:error, %Error{type: :configuration_error}} = Unicom360.client()
      end
    end

    test "a non-string key is refused" do
      assert {:error, %Error{type: :configuration_error}} = Unicom360.client(api_key: :key)
    end
  end

  describe "base_url" do
    test "the default" do
      assert {:ok, %Client{base_url: "https://api.unicom360.com"}} =
               Unicom360.client(api_key: "k")
    end

    test "the environment variable is read, and blank counts as unset" do
      System.put_env("UNICOM360_BASE_URL", "https://proxy.example.com")

      assert {:ok, %Client{base_url: "https://proxy.example.com"}} =
               Unicom360.client(api_key: "k")

      System.put_env("UNICOM360_BASE_URL", " ")

      assert {:ok, %Client{base_url: "https://api.unicom360.com"}} =
               Unicom360.client(api_key: "k")
    end

    test "accepted URLs" do
      for {given, kept} <- [
            {"https://api.unicom360.com", "https://api.unicom360.com"},
            {"https://api.unicom360.com/", "https://api.unicom360.com"},
            {"https://proxy.example.com/unicom360", "https://proxy.example.com/unicom360"},
            {"https://proxy.example.com/unicom360//", "https://proxy.example.com/unicom360"},
            {"https://proxy.example.com:8443", "https://proxy.example.com:8443"},
            {"http://localhost:4010", "http://localhost:4010"},
            {"http://127.0.0.1:4010", "http://127.0.0.1:4010"},
            {"http://127.1.2.3", "http://127.1.2.3"},
            {"http://[::1]:4010/", "http://[::1]:4010"}
          ] do
        assert {:ok, %Client{base_url: ^kept}} = Unicom360.client(api_key: "k", base_url: given)
      end
    end

    test "refused URLs" do
      for url <- [
            "http://api.unicom360.com",
            "http://host.docker.internal:4010",
            "http://128.0.0.1",
            "ftp://api.unicom360.com",
            "api.unicom360.com",
            "//api.unicom360.com",
            "https://",
            "https://api.unicom360.com?x=1",
            "https://api.unicom360.com#fragment",
            "https://user:secret@api.unicom360.com",
            ""
          ] do
        assert {:error, %Error{type: :configuration_error} = error} =
                 Unicom360.client(api_key: "k", base_url: url)

        refute error.message =~ "secret"
      end
    end
  end

  describe "other options" do
    test "the defaults" do
      client = Unicom360.client!(api_key: "k")
      assert client.timeout == 60_000
      assert client.connect_timeout == 10_000
      assert client.max_retries == 2
      assert client.max_retry_wait == 60_000
      assert client.auto_reference_ids == false
    end

    test "the application environment supplies them; an argument wins" do
      Application.put_env(:unicom360, :timeout, 5_000)
      assert Unicom360.client!(api_key: "k").timeout == 5_000
      assert Unicom360.client!(api_key: "k", timeout: 7_000).timeout == 7_000
    end

    test "unusable values are configuration errors" do
      for option <- [
            timeout: 0,
            timeout: 1.5,
            timeout: "60",
            connect_timeout: -1,
            max_retries: -1,
            max_retries: 1.0,
            max_retry_wait: -1,
            auto_reference_ids: "yes",
            app_info: %{version: "1.0"},
            app_info: %{name: "x", unknown: "y"},
            app_info: "x",
            req_options: :nope,
            clock: :nope,
            sleeper: fn -> :ok end,
            random: 0.5,
            unknown_option: 1
          ] do
        assert {:error, %Error{type: :configuration_error}} =
                 Unicom360.client([{:api_key, "k"}, option]),
               "should refuse #{inspect(option)}"
      end
    end

    test "a repeated option is not an unknown one: the first wins, as in Keyword.get/2" do
      assert {:ok, %Client{timeout: 1}} = Unicom360.client(api_key: "k", timeout: 1, timeout: 2)
    end

    test "options must be a keyword list" do
      assert {:error, %Error{type: :configuration_error}} = Unicom360.client(%{api_key: "k"})
      assert {:error, %Error{type: :configuration_error}} = Unicom360.client(["k"])
    end
  end

  describe "the User-Agent" do
    test "names the SDK, the runtime and the platform" do
      agent = Unicom360.client!(api_key: "k").user_agent
      assert agent =~ ~r/^unicom360-elixir\/0\.1\.0 \(elixir [^;]+-otp-\d+; [^;]+; [^)]+\)$/
    end

    test "appends app_info" do
      assert Unicom360.client!(api_key: "k", app_info: [name: "shopsync"]).user_agent =~
               ~r/\) shopsync$/

      assert Unicom360.client!(api_key: "k", app_info: %{name: "shopsync", version: "2.3.0"}).user_agent =~
               ~r/\) shopsync\/2\.3\.0$/

      assert Unicom360.client!(
               api_key: "k",
               app_info: %{name: "shopsync", version: "2.3.0", url: "https://shopsync.example"}
             ).user_agent =~ ~r/\) shopsync\/2\.3\.0 \(\+https:\/\/shopsync\.example\)$/
    end
  end

  describe "put_options/2" do
    test "returns a changed copy and leaves the original alone" do
      client = Unicom360.client!(api_key: "k")
      changed = Client.put_options(client, timeout: 5_000, max_retries: 0)

      assert changed.timeout == 5_000
      assert changed.max_retries == 0
      assert changed.api_key == "k"
      assert client.timeout == 60_000
    end

    test "does not read the environment again" do
      client = Unicom360.client!(api_key: "k")
      System.put_env("UNICOM360_BASE_URL", "https://other.example.com")
      assert Client.put_options(client, timeout: 1).base_url == "https://api.unicom360.com"
    end

    test "recomputes the User-Agent" do
      client = Unicom360.client!(api_key: "k")
      assert Client.put_options(client, app_info: [name: "app"]).user_agent =~ ~r/\) app$/
    end

    test "raises for an unusable option" do
      client = Unicom360.client!(api_key: "k")

      assert_raise Error, fn -> Client.put_options(client, base_url: "http://example.com") end
      assert_raise Error, fn -> Client.put_options(client, nope: 1) end
    end
  end

  describe "redaction" do
    test "inspect/1 never shows the key" do
      client = Unicom360.client!(api_key: "super-secret-key", app_info: [name: "app"])
      shown = inspect(client)

      refute shown =~ "super-secret-key"
      assert shown =~ "api_key: [REDACTED]"
      assert shown =~ "https://api.unicom360.com"
      assert shown =~ "#Unicom360.Client<"
    end

    test "inspect/1 of a structure holding the client never shows the key" do
      client = Unicom360.client!(api_key: "super-secret-key")
      refute inspect([client, %{client: client}]) =~ "super-secret-key"
    end

    test "a configuration error never includes the key" do
      {:error, error} =
        Unicom360.client(api_key: "super-secret-key", base_url: "http://x.example")

      refute Exception.message(error) =~ "super-secret-key"
      refute inspect(error) =~ "super-secret-key"
    end
  end

  test "a client is safe to use from another process" do
    plug = fn conn -> Req.Test.json(conn, %{status: "ok"}) end
    client = Unicom360.client!(api_key: "k", plug: plug)

    assert [{:ok, %Unicom360.Health{status: "ok"}}, {:ok, %Unicom360.Health{}}] =
             [
               Task.async(fn -> Unicom360.health(client) end),
               Task.async(fn -> Unicom360.health(client) end)
             ]
             |> Task.await_many()
  end
end
