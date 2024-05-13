defmodule Plausible.Verification.Checks.DetectApp do
  use Plausible.Verification.Check

  defmodule WordPressDetector do
  end

  @impl true
  def friendly_name, do: "Detecting application type"

  @impl true
  def perform(%State{assigns: %{headers: headers, raw_body: body}} = state) do
    put_diagnostics(state, wordpress?: wordpress?(headers, body))
  end

  def perform(state), do: state

  @wordpress_signatures [
    "wp-content",
    "wp-includes",
    "wp-json",
    "WordPress"
  ]

  @wordpress_headers_to_check [
    "x-powered-by",
    "server"
  ]

  defp wordpress?(headers, body) do
    found_in_body? =
      Enum.any?(@wordpress_signatures, fn sig ->
        String.contains?(body, sig)
      end)

    found_in_headers? =
      Enum.any?(@wordpress_headers_to_check, fn hdr ->
        headers
        |> Map.get(hdr, [""])
        |> List.first()
        |> String.contains?("WordPress")
      end)

    found_in_body? or found_in_headers?
  end
end
