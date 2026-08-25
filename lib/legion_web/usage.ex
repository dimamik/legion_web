defmodule LegionWeb.Usage do
  @moduledoc """
  Aggregates and formats the per-request LLM usage entries returned by
  `LegionWeb.AgentTracker.get_usage/1`.

  Entries are the string-keyed maps Legion records for each LLM request
  (`"input_tokens"`, `"output_tokens"`, `"cached_tokens"`, `"reasoning_tokens"`,
  `"total_cost"`, `"at"`, ...). Missing counters count as zero; cost is `nil`
  until at least one entry reports `"total_cost"`.
  """

  @type totals :: %{
          requests: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cached: non_neg_integer(),
          reasoning: non_neg_integer(),
          cost: number() | nil
        }

  @empty %{requests: 0, input: 0, output: 0, cached: 0, reasoning: 0, cost: nil}

  @doc "Sums token counters and cost across usage entries."
  @spec totals([map()]) :: totals()
  def totals(usage) when is_list(usage) do
    Enum.reduce(usage, @empty, fn entry, acc ->
      %{
        requests: acc.requests + 1,
        input: acc.input + tokens(entry, "input_tokens"),
        output: acc.output + tokens(entry, "output_tokens"),
        cached: acc.cached + tokens(entry, "cached_tokens"),
        reasoning: acc.reasoning + tokens(entry, "reasoning_tokens"),
        cost: add_cost(acc.cost, entry["total_cost"])
      }
    end)
  end

  @doc "Reads one token counter from an entry, treating missing values as zero."
  @spec tokens(map(), String.t()) :: non_neg_integer()
  def tokens(entry, key) do
    case entry[key] do
      value when is_integer(value) -> value
      _ -> 0
    end
  end

  @doc ~S|Abbreviates a token count: `842`, `12.3k`, `1.25M`.|
  @spec format_tokens(integer()) :: String.t()
  def format_tokens(n) when is_integer(n) and n < 1_000, do: Integer.to_string(n)
  def format_tokens(n) when is_integer(n) and n < 1_000_000, do: "#{Float.round(n / 1_000, 1)}k"
  def format_tokens(n) when is_integer(n), do: "#{Float.round(n / 1_000_000, 2)}M"

  @doc "Formats a dollar cost to three decimals, or `nil` when unknown."
  @spec format_cost(number() | nil) :: String.t() | nil
  def format_cost(nil), do: nil
  def format_cost(cost) when cost < 0.001, do: "<$0.001"
  def format_cost(cost), do: "$#{:erlang.float_to_binary(cost / 1, decimals: 3)}"

  defp add_cost(acc, cost) when is_number(cost), do: (acc || 0) + cost
  defp add_cost(acc, _), do: acc
end
