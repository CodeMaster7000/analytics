defmodule Plausible.Verification.Diagnostics do
  require Logger

  defstruct snippets_found_in_head: 0,
            snippets_found_in_body: 0,
            plausible_installed?: false,
            snippet_found_after_busting_cache?: false,
            disallowed_via_csp?: false,
            service_error: nil,
            body_fetched?: false,
            scan_findings: [],
            callback_status: -1,
            proxy_likely?: false

  @type t :: %__MODULE__{}

  defmodule Rating do
    defstruct ok?: false, errors: [], recommendations: []
    @type t :: %__MODULE__{}
  end

  @spec rate(t(), String.t()) :: Rating.t()
  def rate(
        %__MODULE__{proxy_likely?: true, plausible_installed?: true, callback_status: 0} =
          diag,
        _url
      ) do
    %Rating{
      ok?: false,
      errors: ["Installation incomplete"],
      recommendations: [
        "In case of proxies, don't forget to setup the /event route"
        | general_recommendations(diag)
      ]
    }
  end

  def rate(%__MODULE__{plausible_installed?: true, disallowed_via_csp?: false} = diag, _url) do
    %Rating{ok?: true, recommendations: general_recommendations(diag)}
  end

  def rate(%__MODULE__{plausible_installed?: installed?, disallowed_via_csp?: true} = diag, _url) do
    %Rating{
      ok?: installed?,
      recommendations: [
        {"Make sure your Content-Security-Policy allows plausible.io",
         "https://plausible.io/docs/troubleshoot-integration"}
        | general_recommendations(diag)
      ]
    }
  end

  def rate(%__MODULE__{plausible_installed?: false, service_error: true}, _url) do
    %Rating{
      ok?: false,
      errors: ["We encountered a temporary problem verifying your website"],
      recommendations: [
        "Please try again in a few minutes",
        "Try visiting your website to help us register pageviews"
      ]
    }
  end

  def rate(%__MODULE__{plausible_installed?: false, body_fetched?: false}, url) do
    %Rating{
      ok?: false,
      errors: ["We could not reach your website. Is it up?"],
      recommendations: [
        "Make sure the website is up and running at #{url}",
        {"Note: if you host elsewhere, we can't verify it",
         "https://plausible.io/docs/subdomain-hostname-filter"}
      ]
    }
  end

  def rate(
        %__MODULE__{
          body_fetched?: true,
          plausible_installed?: false,
          service_error: service_error
        },
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
        %__MODULE__{
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
      recommendations: [
        {"Hint: Place the snippet on your website and deploy it",
         "https://plausible.io/docs/plausible-script"}
      ]
    }
  end

  # TODO: test this
  def rate(%__MODULE__{plausible_installed?: false} = diag, _url) do
    %Rating{
      ok?: false,
      errors: ["We could not verify your installation"],
      recommendations: [
        {"Have you seen our troubleshooting guide?",
         "https://plausible.io/docs/troubleshoot-integration"}
        | general_recommendations(diag)
      ]
    }
  end

  def general_recommendations(%__MODULE__{} = diag) do
    Enum.reduce(
      [
        &recommend_proxy_guide/1,
        &recommend_gtm_docs/1,
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

  defp recommend_proxy_guide(diag) do
    if diag.proxy_likely? do
      {"Using a proxy? Read our guide", "https://plausible.io/docs/proxy/introduction"}
    end
  end

  defp recommend_gtm_docs(diag) do
    if :gtm in diag.scan_findings do
      {"Using Google Tag Manager?", "https://plausible.io/docs/google-tag-manager"}
    end
  end

  defp recommend_one_snippet(diag) do
    if diag.snippets_found_in_body > 1 or diag.snippets_found_in_head > 1 do
      {"Hint: Multiple snippets found on your website. Was that intentional?",
       "https://plausible.io/docs/script-extensions"}
    end
  end

  defp recommend_putting_snippet_in_head(diag) do
    if diag.snippets_found_in_body > 0 do
      "Hint: Place the snippet in <head> rather than <body>"
    end
  end

  defp recommend_busting_cache(diag) do
    if diag.snippet_found_after_busting_cache? do
      "Hint: Purge your site's cache to ensure you're viewing the latest version of your website"
    end
  end
end
