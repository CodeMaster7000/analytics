defmodule Plausible.Verification.Checks.SnippetCacheBust do
  use Plausible.Verification.Check

  @impl true
  def friendly_name, do: "Busting cache"

  @impl true
  def perform(
        %State{
          url: url,
          diagnostics: %Diagnostics{
            snippets_found_in_head: 0,
            snippets_found_in_body: 0,
            body_fetched?: true
          }
        } = state
      ) do
    cache_invalidator = abs(:erlang.unique_integer())
    busted_url = update_url(url, cache_invalidator)

    state2 =
      %{state | url: busted_url}
      |> Plausible.Verification.Checks.FetchBody.perform()
      |> Plausible.Verification.Checks.Snippet.perform()

    if state2.diagnostics.snippets_found_in_head > 0 or
         state2.diagnostics.snippets_found_in_body > 0 do
      put_diagnostics(state2, snippet_found_after_busting_cache?: true)
    else
      state
    end
  end

  def perform(state), do: state

  defp update_url(url, invalidator) do
    url
    |> URI.parse()
    |> then(fn uri ->
      updated_query =
        (uri.query || "")
        |> URI.decode_query()
        |> Map.put("plausible_verification", invalidator)
        |> URI.encode_query()

      struct!(uri, query: updated_query)
    end)
    |> to_string()
  end
end
