defmodule Plausible.Verification.Checks.CSP do
  use Plausible.Verification.Check

  @impl true
  def friendly_name, do: "Checking security headers"

  @impl true
  def perform(%State{assigns: %{headers: headers}} = state) do
    case headers["content-security-policy"] do
      [policy] ->
        directives = String.split(policy, ";")

        allowed? =
          Enum.any?(directives, fn directive ->
            String.contains?(directive, "plausible.io")
          end)

        if allowed? do
          state
        else
          put_diagnostics(state, disallowed_via_csp?: true)
        end

      _ ->
        state
    end
  end

  def perform(state), do: state
end
