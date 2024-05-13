defmodule Plausible.Verification.Diagnostics do
  require Logger

  defstruct snippets_found_in_head: 0,
            snippets_found_in_body: 0,
            plausible_installed?: false,
            snippet_found_after_busting_cache?: false,
            disallowed_via_csp?: false,
            service_error: nil,
            body_fetched?: false,
            url: nil

  @type t :: %__MODULE__{}

  alias __MODULE__, as: D

  defmodule Rating do
    defstruct ok?: false, errors: [], recommendations: []
    @type t :: %__MODULE__{}
  end

  @spec rate(t(), String.t()) :: Rating.t()
  def rate(%D{plausible_installed?: true, disallowed_via_csp?: false} = diag, _url) do
    %Rating{ok?: true, recommendations: general_recommendations(diag)}
  end

  def rate(%D{plausible_installed?: installed?, disallowed_via_csp?: true} = diag, _url) do
    %Rating{
      ok?: installed?,
      recommendations: [
        "Make sure your Content-Security-Policy allows plausible.io"
        | general_recommendations(diag)
      ]
    }
  end

  def rate(%D{plausible_installed?: false, service_error: true}, _url) do
    %Rating{
      ok?: false,
      errors: ["We encountered a temporary problem verifying your website"],
      recommendations: [
        "Please try again in a few minutes",
        "Try visiting your website to help us register pageviews"
      ]
    }
  end

  def rate(%D{plausible_installed?: false, body_fetched?: false}, url) do
    %Rating{
      ok?: false,
      errors: ["We could not reach your webiste. Is it up?"],
      recommendations: [
        "Make sure the website is up and running at #{url}",
        "Note: you can run the site elsewhere, in which case we can't verify it"
      ]
    }
  end

  def rate(
        %D{body_fetched?: true, plausible_installed?: false, service_error: service_error},
        _url
      )
      when not is_nil(service_error) do
    %Rating{
      ok?: false,
      errors: ["Your website is up, but we couldn't verify it"],
      recommendations: [
        "Please try again in a few minutes",
        "Try visiting your website to help us register pageviews"
      ]
    }
  end

  def rate(
        %D{
          body_fetched?: true,
          plausible_installed?: false,
          snippets_found_in_body: 0,
          snippets_found_in_head: 0,
          service_error: nil
        },
        _url
      ) do
    %Rating{
      ok?: false,
      errors: ["We found no snippet installed on your website"],
      recommendations: ["Hint: Place the snippet on your website and deploy it"]
    }
  end

  def rate(%D{plausible_installed?: false} = diag, _url) do
    %Rating{
      ok?: true,
      errors: ["We could not verify your installation"],
      recommendations: general_recommendations(diag)
    }
  end

  def general_recommendations(%D{} = diag) do
    Enum.reduce(
      [
        &recommend_one_snippet/1,
        &recommend_putting_snippet_in_head/1,
        &recommend_busting_cache/1
      ],
      [],
      fn f, acc ->
        recommendation = f.(diag)

        if recommendation do
          [recommendation | acc]
        else
          acc
        end
      end
    )
  end

  defp recommend_one_snippet(diag) do
    if diag.snippets_found_in_body > 1 or diag.snippets_found_in_head > 1 do
      "Hint: Multiple snippets found on your website. Was that intentional?"
    end
  end

  defp recommend_putting_snippet_in_head(diag) do
    if diag.snippets_found_in_body > 0 do
      "Hint: Place the snippet in <head> rather than <body>"
    end
  end

  defp recommend_busting_cache(diag) do
    if diag.snippet_found_after_busting_cache? do
      "Hint: Purge your site's cache to ensure you're viewing the lastes version of your webiste"
    end
  end
end
