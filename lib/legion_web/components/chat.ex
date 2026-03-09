defmodule LegionWeb.Components.Chat do
  use LegionWeb, :html

  attr :status, :atom, required: true
  attr :pending, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div class="border-t border-sol-base2 px-6 py-4 shrink-0 bg-sol-base2/50">
      <p class="text-xs mb-2.5">
        {cond do
          @status == :waiting_for_human ->
            "Agent is waiting for your response"

          @status == :running ->
            "Agent is running\u2026"

          @status == :idle ->
            "Agent is ready for your message"

          true ->
            "Send a message to the agent"
        end
        |> then(fn text ->
          cond do
            @status == :waiting_for_human ->
              assigns |> assign(:text, text) |> render_status_text("text-sol-yellow font-medium")

            @status == :idle ->
              assigns |> assign(:text, text) |> render_status_text("text-sol-blue")

            true ->
              assigns |> assign(:text, text) |> render_status_text("text-sol-base00")
          end
        end)}
      </p>
      <form phx-submit="send_message" class="flex gap-2.5">
        <input
          type="text"
          name="text"
          autofocus
          autocomplete="off"
          disabled={@pending || @status == :running}
          placeholder={
            if @status == :waiting_for_human,
              do: "Type your response\u2026",
              else: "Type a message\u2026"
          }
          class="flex-1 bg-sol-base3 border border-sol-base1/30 rounded-lg px-4 py-2.5 text-sm text-sol-base02 placeholder-sol-base00 focus:outline-none focus:border-sol-blue/50 focus:ring-1 focus:ring-sol-blue/25 disabled:opacity-40 transition-all"
        />
        <button
          type="submit"
          disabled={@pending || @status == :running}
          class="px-5 py-2.5 bg-sol-violet hover:bg-sol-violet/85 disabled:opacity-40 disabled:hover:bg-sol-violet text-white text-sm font-medium rounded-lg transition-all"
        >
          {if @pending, do: "\u2026", else: "Send"}
        </button>
      </form>
    </div>
    """
  end

  defp render_status_text(assigns, class) do
    assigns = assign(assigns, :class, class)

    ~H"""
    <span class={@class}>{@text}</span>
    """
  end
end
