defmodule Plausible.Verification.Diagnostics do
  require Logger

  defstruct snippets_found_in_head: 0,
            snippets_found_in_body: 0,
            plausible_installed?: false,
            snippet_found_after_busting_cache: false,
            document_content_type: "",
            service_error: nil,
            body_fetched?: false,
            url: nil

  @type t :: %__MODULE__{}

  defmodule Interpretation do
    defstruct confidence: 0, errors: [], recommendations: []
    @type t :: %__MODULE__{}
  end

  # @spec interpret(t()) :: Interpretation.t()
  # def interpret(%__MODULE__{} = diagnostics) do
  #   case diagnostics do
  #     %__MODULE__{
  #       plausible_installed?: true,
  #       could_not_fetch_body: false,
  #       snippets_found_in_head: 1
  #     } ->
  #       %Interpretation{confidence: 100, errors: [], recommendations: []}

  #     %__MODULE__{could_not_fetch_body: true, plausible_installed?: false, url: url} ->
  #       %Interpretation{
  #         confidence: 100,
  #         errors: ["We could not reach your website. Is it up?"],
  #         recommendations: [
  #           "Make sure your website is publicly available at #{url}. Note that the integration may still work if your website is hosted under a different address."
  #         ]
  #       }
  #   end
  # end

  def diagnostics_to_user_feedback(%__MODULE__{body_fetched?: false, service_error: e2})
      when not is_nil(e2) do
    {:error, "We could not reach your website. Is it up?"}
  end

  def diagnostics_to_user_feedback(%__MODULE__{body_fetched?: true, service_error: e})
      when not is_nil(e) do
    Logger.error("Verification Agent error: #{inspect(e)}")
    {:error, "Your website is up but we are unable to verify it. Please try again later."}
  end

  def diagnostics_to_user_feedback(%__MODULE__{service_error: e}) when not is_nil(e) do
    Logger.error("Verification Agent error: #{inspect(e)}")
    {:error, "We are currently unable to verify your site. Please try again later."}
  end

  def diagnostics_to_user_feedback(%__MODULE__{
        snippets_found_in_head: 0,
        snippets_found_in_body: 0,
        plausible_installed?: false
      }) do
    {:error, "We could not find the Plausible snippet on your website"}
  end

  def diagnostics_to_user_feedback(%__MODULE__{plausible_installed?: false}) do
    {:error, "We could not verify your Plausible snippet working"}
  end
end
