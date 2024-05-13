defmodule PlausibleWeb.Live.Verification do
  use PlausibleWeb, :live_view
  use Phoenix.HTML

  alias Plausible.Verification.{Checks, State}
  alias PlausibleWeb.Live.Components.Modal

  @component PlausibleWeb.Live.Components.Verification
  @slowdown_for_frequent_checking :timer.seconds(5)

  def mount(
        _params,
        %{"domain" => domain} = session,
        socket
      ) do
    if connected?(socket) and !session["modal?"] do
      launch_delayed()
    end

    socket =
      assign(socket,
        domain: domain,
        modal?: !!session["modal?"],
        component: @component
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div :if={@modal?}>
      <.live_component module={Modal} id="verification-modal">
        <.live_component
          module={@component}
          domain={@domain}
          id="verification-within-modal"
          modal?={@modal?}
        />
      </.live_component>

      <PlausibleWeb.Components.Generic.button
        id="launch-verification-button"
        x-data
        x-on:click={Modal.JS.open("verification-modal")}
        phx-click="launch-verification"
        class="mt-4"
      >
        Verify
      </PlausibleWeb.Components.Generic.button>
    </div>

    <.live_component :if={!@modal?} module={@component} domain={@domain} id="verification-standalone" />
    """
  end

  def handle_event("launch-verification", _, socket) do
    launch_delayed()
    {:noreply, socket}
  end

  def handle_event("retry", _, socket) do
    launch_delayed()

    update_component(socket,
      message: "Verifying your installation...",
      finished?: false,
      success?: false,
      diagnostics: nil
    )

    {:noreply, socket}
  end

  def handle_event("dismiss", _, %{assigns: %{modal?: true}} = socket) do
    {:noreply, Modal.close(socket, "verification-modal")}
  end

  def handle_info(:start, socket) do
    case Plausible.RateLimit.check_rate(
           "site_verification_#{socket.assigns.domain}",
           :timer.minutes(60),
           3
         ) do
      {:allow, _} -> :ok
      {:deny, _} -> :timer.sleep(@slowdown_for_frequent_checking)
    end

    Checks.run("https://#{socket.assigns.domain}", socket.assigns.domain, report_to: self())
    {:noreply, socket}
  end

  def handle_info({:verification_check_start, {check, _state}}, socket) do
    update_component(socket,
      message: "#{check.friendly_name()}..."
    )

    {:noreply, socket}
  end

  def handle_info({:verification_check_finish, {check, _state}}, socket) do
    update_component(socket,
      message: "#{check.friendly_name()} completed"
    )

    {:noreply, socket}
  end

  def handle_info(
        {:verification_end,
         %State{
           data_domain: _data_domain
         } = state},
        socket
      ) do
    rating = State.interpret_diagnostics(state)

    message =
      cond do
        rating.ok? and socket.assigns.modal? ->
          "Installation verified"

        rating.ok? ->
          "Installation verified. Awaiting your first pageview"

        true ->
          List.first(rating.errors)
      end

    update_component(socket,
      message: message,
      finished?: true,
      success?: rating.ok?,
      rating: rating
    )

    {:noreply, socket}
  end

  defp update_component(socket, updates) do
    send_update(
      @component,
      Keyword.merge(updates,
        id:
          if(socket.assigns.modal?,
            do: "verification-within-modal",
            else: "verification-standalone"
          )
      )
    )
  end

  defp launch_delayed() do
    Process.send_after(self(), :start, 500)
  end
end
