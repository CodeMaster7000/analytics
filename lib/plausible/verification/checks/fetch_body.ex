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
          max_redirects: 2,
          connect_options: [timeout: 4_000],
          receive_timeout: 4_000,
          max_retries: 3,
          retry_log_level: :warning
        ],
        fetch_body_opts
      )

    req = Req.new(opts)

    case Req.get(req) do
      {:ok, %{status: status, body: body} = response}
      when is_binary(body) and status in 200..299 ->
        extract_document(state, response)

      _ ->
        state
    end
  end

  defp extract_document(state, response) when byte_size(response.body) <= 500_000 do
    with true <- html?(response),
         {:ok, document} <- Floki.parse_document(response.body) do
      state
      |> assign(raw_body: response.body, document: document, headers: response.headers)
      |> put_diagnostics(body_fetched?: true)
    else
      _ ->
        state
    end
  end

  defp extract_document(state, response) when byte_size(response.body) > 500_000 do
    state
  end

  defp html?(%{headers: headers}) do
    headers
    |> Map.get("content-type", "")
    |> List.wrap()
    |> List.first()
    |> String.contains?("text/html")
  end

  defp html?(_), do: false
end
