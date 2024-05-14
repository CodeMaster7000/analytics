defmodule PlausibleWeb.Live.Components.Verification do
  use Phoenix.LiveComponent

  import PlausibleWeb.Components.Generic

  def update(assigns, socket) do
    socket =
      socket
      |> assign_new(:domain, fn -> assigns.domain end)
      |> assign_new(:modal?, fn -> assigns[:modal?] end)
      |> assign(
        message: assigns[:message] || "Verifying your installation",
        finished?: assigns[:finished?] || false,
        success?: assigns[:success?] || false,
        rating: assigns[:rating]
      )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class={[
      "bg-white dark:bg-gray-800 text-center h-96 flex flex-col",
      if(!@modal?, do: "shadow-md rounded px-8 pt-6 pb-4 mb-4 mt-16")
    ]}>
      <h2 class="text-xl font-bold dark:text-gray-100">Verifying your installation</h2>
      <h2 class="text-xl font-bold dark:text-gray-100 text-xs">on <%= @domain %></h2>
      <div :if={!@finished? || @success?} class="flex justify-center w-full h-12 mt-8">
        <div class={["block pulsating-circle", if(@modal? && @finished?, do: "hidden")]}></div>
        <Heroicons.check_circle
          :if={@modal? && @finished? && @success?}
          solid
          class="w-5 h-5 text-green-500"
        />
      </div>

      <div :if={@finished? && !@success?} class="flex justify-center pt-3 h-14 mb-4">
        <.shuttle width={50} height={50} />
      </div>
      <div
        id="progress"
        class={[
          "mt-2",
          if(!@finished?, do: "animate-pulse text-xs", else: "font-bold text-sm"),
          if(@finished? && !@success?, do: "text-red-500")
        ]}
      >
        <%= @message %>
      </div>

      <div :if={@finished?}>
        <div :if={@rating} class="text-xs mt-4">
          <.recommendations rating={@rating} />
        </div>

        <div class="flex justify-center gap-x-4 mt-4">
          <.button_link :if={!@success?} href="#" phx-click="retry" class="text-xs">
            Retry
          </.button_link>

          <.button_link :if={@finished? && @modal?} href="#" class="text-xs" phx-click="dismiss">
            Dismiss
          </.button_link>
        </div>
      </div>

      <div class="mt-auto pb-2 text-gray-600 dark:text-gray-400 text-xs w-full text-center leading-normal">
        <%= if !@modal? do %>
          Need to see the snippet again?
          <.styled_link href={"/#{URI.encode_www_form(@domain)}/snippet"}>
            Click here
          </.styled_link>
          <br /> Run verification later and go to Site Settings?
          <.styled_link href={"/#{URI.encode_www_form(@domain)}/settings/general"}>
            Click here
          </.styled_link>
          <br />
        <% end %>
        Skip to the dashboard?
        <.styled_link href={"/#{URI.encode_www_form(@domain)}?skip_to_dashboard=true"}>
          Click here
        </.styled_link>
      </div>
    </div>
    """
  end

  def recommendations(assigns) do
    ~H"""
    <p class="leading-normal">
      <span :for={recommendation <- @rating.recommendations}>
        <span :if={is_binary(recommendation)}><%= recommendation %></span>
        <span :if={is_tuple(recommendation)}><%= elem(recommendation, 0) %> -</span>
        <.styled_link :if={is_tuple(recommendation)} href={elem(recommendation, 1)}>
          Learn more
        </.styled_link>
        <br />
      </span>
    </p>
    """
  end
end
