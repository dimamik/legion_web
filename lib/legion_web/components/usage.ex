defmodule LegionWeb.Components.Usage do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.Usage

  attr :usage, :list, required: true

  @doc "Header summary: input / output tokens and cost for the selected agent."
  def summary(assigns) do
    assigns = assign(assigns, :totals, Usage.totals(assigns.usage))

    ~H"""
    <span
      :if={@totals.requests > 0}
      class="flex items-center gap-2 tabular-nums"
      title={"#{@totals.requests} requests · #{@totals.cached} cached · #{@totals.reasoning} reasoning"}
    >
      <span>&uarr; {Usage.format_tokens(@totals.input)}</span>
      <span>&darr; {Usage.format_tokens(@totals.output)}</span>
      <span
        :if={cost = Usage.format_cost(@totals.cost)}
        class="px-1.5 py-0.5 rounded bg-sol-violet/10 text-sol-violet font-medium"
      >
        {cost}
      </span>
    </span>
    """
  end

  attr :usage, :list, required: true

  @doc "Overlay with totals and one row per LLM request."
  def panel(assigns) do
    totals = Usage.totals(assigns.usage)

    max_tokens =
      assigns.usage
      |> Enum.map(&(Usage.tokens(&1, "input_tokens") + Usage.tokens(&1, "output_tokens")))
      |> Enum.max(fn -> 1 end)
      |> max(1)

    assigns = assigns |> assign(:totals, totals) |> assign(:max_tokens, max_tokens)

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
          <.tile label="Cost" value={Usage.format_cost(@totals.cost) || "—"} accent />
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
              <th class="text-right font-medium py-1">Cost</th>
              <th class="w-1/3 py-1"></th>
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
              <td class="py-1.5 pl-3">
                <div class="flex h-2 rounded overflow-hidden bg-sol-base2">
                  <div
                    class="bg-sol-blue/60"
                    style={"width: #{pct(Usage.tokens(entry, "input_tokens"), @max_tokens)}%"}
                  >
                  </div>
                  <div
                    class="bg-sol-green/60"
                    style={"width: #{pct(Usage.tokens(entry, "output_tokens"), @max_tokens)}%"}
                  >
                  </div>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <p class="mt-3 text-[10px] text-sol-base1">
          <span class="inline-block w-2 h-2 rounded-sm bg-sol-blue/60 align-middle"></span>
          input
          <span class="inline-block w-2 h-2 rounded-sm bg-sol-green/60 align-middle ml-3"></span>
          output
        </p>
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

  defp pct(n, max), do: Float.round(n / max * 100, 1)

  defp format_ts(ms) when is_integer(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M:%S")
  end

  defp format_ts(_), do: "--:--:--"
end
