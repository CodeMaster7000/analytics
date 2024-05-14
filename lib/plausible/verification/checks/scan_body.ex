defmodule Plausible.Verification.Checks.ScanBody do
  use Plausible.Verification.Check

  @impl true
  def friendly_name, do: "Scanning"

  @impl true
  def perform(%State{assigns: %{raw_body: body}} = state) do
    if String.contains?(body, "gtm.js") or String.contains?(body, "googletagmanager.com") do
      put_diagnostics(state, scan_findings: [:gtm | state.diagnostics.scan_findings])
    else
      state
    end
  end

  def perform(state), do: state
end
