defmodule LegionWeb.Components.Usage do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.UsageAggregator, as: Usage

  attr :usage, :list, required: true

  @cost_note "Estimate from token counts × list prices. May not match the provider invoice."

  @doc "Header summary: input / output tokens and estimated cost for the selected agent."
  def summary(assigns) do
    assigns =
      assigns
      |> assign(:totals, Usage.totals(assigns.usage))
      |> assign(:cost_note, @cost_note)

    ~H"""
    <span :if={@totals.requests > 0} class="flex items-center gap-2 tabular-nums">
      <span
        class="flex items-center gap-2"
        title={"#{@totals.requests} requests · #{@totals.cached} cached · #{@totals.reasoning} reasoning"}
      >
        <span>&uarr; {Usage.format_tokens(@totals.input)}</span>
        <span>&darr; {Usage.format_tokens(@totals.output)}</span>
      </span>
      <span
        :if={cost = Usage.format_cost(@totals.cost)}
        class="note inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-sol-violet/10 text-sol-violet font-medium cursor-help"
        data-note={@cost_note}
        tabindex="0"
      >
        {cost}
        <span
          aria-hidden="true"
          class="inline-flex items-center justify-center w-3 h-3 rounded-full border border-current text-[8px] leading-none font-serif italic font-semibold opacity-75"
        >
          i
        </span>
      </span>
    </span>
    """
  end

  attr :usage, :list, required: true

  @doc "Overlay with totals and one row per LLM request."
  def panel(assigns) do
    assigns = assign(assigns, :totals, Usage.totals(assigns.usage))

    ~H"""
    <div
      class="absolute inset-0 z-10 flex flex-col bg-sol-base3"
      phx-window-keydown="close_usage"
      phx-key="Escape"
    >
      <div class="flex items-center justify-between gap-3 px-6 py-4 border-b border-sol-base2 shrink-0">
        <h3 class="text-sm font-semibold text-sol-base02">Usage</h3>
        <button
          phx-click="close_usage"
          class="w-7 h-7 flex items-center justify-center rounded text-sol-base1 hover:text-sol-base01 hover:bg-sol-base2 transition-colors cursor-pointer"
        >
          &times;
        </button>
      </div>
      <div class="flex-1 overflow-y-auto px-6 py-4">
        <div class="grid grid-cols-6 gap-3 mb-6">
          <.tile label="Requests" value={Integer.to_string(@totals.requests)} />
          <.tile label="Input" value={Usage.format_tokens(@totals.input)} />
          <.tile label="Output" value={Usage.format_tokens(@totals.output)} />
          <.tile label="Cached" value={Usage.format_tokens(@totals.cached)} />
          <.tile label="Reasoning" value={Usage.format_tokens(@totals.reasoning)} />
          <.tile label="Estimated Cost" value={Usage.format_cost(@totals.cost) || "—"} accent />
        </div>
        <table class="w-full font-mono text-xs tabular-nums">
          <thead class="text-[10px] uppercase tracking-wider text-sol-base1">
            <tr>
              <th class="text-left font-medium py-1">#</th>
              <th class="text-left font-medium py-1">Time</th>
              <th class="text-right font-medium py-1">In</th>
              <th class="text-right font-medium py-1">Out</th>
              <th class="text-right font-medium py-1">Cached</th>
              <th class="text-right font-medium py-1">Reason</th>
              <th class="text-right font-medium py-1">Est. Cost</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{entry, i} <- Enum.with_index(@usage, 1)} class="border-t border-sol-base2">
              <td class="py-1.5 text-sol-base1">{i}</td>
              <td class="py-1.5 text-sol-base00">{format_ts(entry["at"])}</td>
              <td class="py-1.5 text-right">{Usage.tokens(entry, "input_tokens")}</td>
              <td class="py-1.5 text-right">{Usage.tokens(entry, "output_tokens")}</td>
              <td class="py-1.5 text-right text-sol-base1">{Usage.tokens(entry, "cached_tokens")}</td>
              <td class="py-1.5 text-right text-sol-base1">
                {Usage.tokens(entry, "reasoning_tokens")}
              </td>
              <td class="py-1.5 text-right text-sol-violet">
                {Usage.format_cost(entry["total_cost"]) || "—"}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :accent, :boolean, default: false

  defp tile(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border px-3 py-2",
      if(@accent,
        do: "border-sol-violet/30 bg-sol-violet/5",
        else: "border-sol-base2 bg-sol-base2/40"
      )
    ]}>
      <div class="text-[10px] uppercase tracking-wider text-sol-base1">{@label}</div>
      <div class={[
        "text-lg font-semibold tabular-nums",
        if(@accent, do: "text-sol-violet", else: "text-sol-base02")
      ]}>
        {@value}
      </div>
    </div>
    """
  end

  defp format_ts(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M:%S")
  end

  defp format_ts(_), do: "--:--:--"
end
