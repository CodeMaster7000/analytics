defmodule Plausible.Verification.Checks do
  alias Plausible.Verification.Checks
  alias Plausible.Verification.State

  require Logger

  @checks [
    Checks.FetchBody,
    Checks.CSP,
    Checks.DetectApp,
    Checks.Snippet,
    Checks.SnippetCacheBust,
    Checks.Installation
  ]

  def run(url, data_domain, opts \\ []) do
    checks = Keyword.get(opts, :checks, @checks)
    report_to = Keyword.get(opts, :report_to, self())
    async? = Keyword.get(opts, :async?, true)
    slowdown = Keyword.get(opts, :slowdown, 100)

    if async? do
      Task.start_link(fn -> do_run(url, data_domain, checks, report_to, slowdown) end)
    else
      do_run(url, data_domain, checks, report_to, slowdown)
    end
  end

  defp do_run(url, data_domain, checks, report_to, slowdown) do
    init_state = %State{url: url, data_domain: data_domain, report_to: report_to}

    state =
      Enum.reduce(
        checks,
        init_state,
        fn check, state ->
          state
          |> State.notify_start(check, slowdown)
          |> check.perform_wrapped()
        end
      )

    State.notify_verification_end(state, slowdown)
  end
end
