defmodule Plausible.Verification.State do
  defstruct url: nil,
            data_domain: nil,
            report_to: nil,
            assigns: %{},
            diagnostics: %Plausible.Verification.Diagnostics{}

  @type t() :: %__MODULE__{}

  def interpret_diagnostics(%__MODULE__{} = state) do
    Plausible.Verification.Diagnostics.rate(state.diagnostics, state.url)
  end

  def assign(%__MODULE__{} = state, [{key, value}]) do
    %{state | assigns: Map.put(state.assigns, key, value)}
  end

  def put_diagnostics(%__MODULE__{} = state, diagnostics) when is_list(diagnostics) do
    %{state | diagnostics: struct!(state.diagnostics, diagnostics)}
  end

  def put_diagnostics(%__MODULE__{} = state, diagnostics) do
    put_diagnostics(state, List.wrap(diagnostics))
  end

  def notify_start(state, check, slowdown \\ 0) do
    if is_pid(state.report_to) do
      if is_integer(slowdown) and slowdown > 0, do: :timer.sleep(slowdown)
      send(state.report_to, {:verification_check_start, {check, state}})
    end

    state
  end

  def notify_verification_end(state, slowdown \\ 0) do
    if is_pid(state.report_to) do
      if is_integer(slowdown) and slowdown > 0, do: :timer.sleep(slowdown)
      send(state.report_to, {:verification_end, state})
    end

    state
  end
end
