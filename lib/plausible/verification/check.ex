defmodule Plausible.Verification.Check do
  @type state() :: Plausible.Verification.State.t()
  @callback friendly_name() :: String.t()
  @callback perform(state()) :: state()

  defmacro __using__(_) do
    quote do
      import Plausible.Verification.State

      alias Plausible.Verification.Checks
      alias Plausible.Verification.State
      alias Plausible.Verification.Diagnostics

      @behaviour Plausible.Verification.Check
    end
  end
end
