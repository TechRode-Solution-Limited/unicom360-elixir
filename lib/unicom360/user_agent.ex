defmodule Unicom360.UserAgent do
  @moduledoc false
  # `unicom360-elixir/<version> (elixir <version>-otp-<release>; <os>; <arch>)[ <app>[/<version>][ (+<url>)]]`

  @spec build(Unicom360.Client.app_info() | nil) :: String.t()
  def build(app_info) do
    base =
      "unicom360-elixir/#{Unicom360.version()} " <>
        "(elixir #{System.version()}-otp-#{System.otp_release()}; #{os()}; #{arch()})"

    base <> suffix(app_info)
  end

  defp suffix(nil), do: ""

  defp suffix(%{name: name, version: version, url: url}) do
    " " <>
      name <> if(version, do: "/" <> version, else: "") <> if(url, do: " (+#{url})", else: "")
  end

  defp os do
    case :os.type() do
      {:unix, name} -> Atom.to_string(name)
      {:win32, _name} -> "windows"
    end
  end

  defp arch do
    :erlang.system_info(:system_architecture)
    |> List.to_string()
    |> String.split("-", parts: 2)
    |> hd()
  end
end
