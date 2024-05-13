defmodule Plausible.Verification.Checks.FetchBody do
  use Plausible.Verification.Check

  @impl true
  def friendly_name, do: "Fetching website contents"

  @impl true
  def perform(%State{url: "https://" <> _ = url} = state) do
    fetch_body_opts = Application.get_env(:plausible, __MODULE__)[:req_opts] || []

    opts =
      Keyword.merge(
        [
          base_url: url,
          max_redirects: 1
        ],
        fetch_body_opts
      )

    req = Req.new(opts)

    case Req.get(req) do
      {:ok, %{status: status, body: body} = response}
      when is_binary(body) and status in 200..299 ->
        extract_document(state, response)

      {:ok, _response} ->
        put_diagnostics(state, body_fetched?: false)

      {:error, _exception} ->
        put_diagnostics(state, body_fetched?: false)
    end
  end

  defp extract_document(state, response) do
    case Floki.parse_document(response.body) do
      {:ok, document} ->
        state
        |> assign(document: document, headers: response.headers)
        |> put_diagnostics(body_fetched?: true)

      {:error, _reason} ->
        put_diagnostics(state, body_fetched?: false)
    end
  end
end
