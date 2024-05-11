defmodule Plausible.Verification.Checks.Installation do
  require EEx
  use Plausible.Verification.Check

  @verification_script_filename "verification/verify_plausible_installed.js.eex"
  @verification_script_path Path.join(:code.priv_dir(:plausible), @verification_script_filename)
  # TODO: external resource

  EEx.function_from_file(
    :def,
    :verify_plausible_installed_js_code,
    @verification_script_path,
    [
      :url
    ]
  )

  @impl true
  def friendly_name, do: "Verifying Plausible snippet installation"

  @impl true
  def perform(%State{url: url} = state) do
    opts = [
      headers: %{content_type: "application/javascript"},
      body: verify_plausible_installed_js_code(url),
      retry: :transient,
      retry_log_level: :warning,
      max_retries: 3
    ]

    extra_opts = Application.get_env(:plausible, __MODULE__)[:req_opts] || []
    opts = Keyword.merge(opts, extra_opts)

    case Req.post(verification_endpoint(), opts) do
      {:ok, %{status: 200, body: %{"data" => %{"plausibleInstalled" => installed?}}}}
      when is_boolean(installed?) ->
        put_diagnostics(state, plausible_installed?: installed?)

      {:ok, %{status: status}} ->
        put_diagnostics(state, plausible_installed?: false, service_error: status)

      {:error, %{reason: reason}} ->
        put_diagnostics(state, plausible_installed?: false, service_error: reason)
    end
  end

  defp verification_endpoint() do
    config = Application.get_env(:plausible, __MODULE__)
    token = Keyword.fetch!(config, :token)
    endpoint = Keyword.fetch!(config, :endpoint)
    Path.join(endpoint, "function?token=#{token}")
  end
end
