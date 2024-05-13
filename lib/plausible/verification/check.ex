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

      require Logger

      @behaviour Plausible.Verification.Check

      def perform_wrapped(state) do
        try do
          perform(state)
        rescue
          e ->
            Logger.error("Error running check #{friendly_name()} on #{state.url}: #{inspect(e)}")

            put_diagnostics(state, service_error: true)
        catch
          e ->
            Logger.error("Error running check #{friendly_name()} on #{state.url}: #{inspect(e)}")

            put_diagnostics(state, service_error: true)
        end
      end
    end
  end
end
