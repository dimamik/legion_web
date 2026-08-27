defmodule LegionWeb.UsageAggregatorTest do
  use ExUnit.Case, async: true

  alias LegionWeb.UsageAggregator, as: Usage

  describe "totals/1" do
    test "sums token counters and cost across entries" do
      usage = [
        %{
          "input_tokens" => 1_000,
          "output_tokens" => 100,
          "cached_tokens" => 400,
          "reasoning_tokens" => 0,
          "total_cost" => 0.01,
          "at" => 1
        },
        %{"input_tokens" => 2_000, "output_tokens" => 50, "reasoning_tokens" => 30, "at" => 2}
      ]

      assert Usage.totals(usage) == %{
               requests: 2,
               input: 3_000,
               output: 150,
               cached: 400,
               reasoning: 30,
               cost: 0.01
             }
    end

    test "reports nil cost when no entry carries one" do
      assert %{requests: 1, cost: nil} = Usage.totals([%{"input_tokens" => 1}])
    end

    test "is empty for no entries" do
      assert Usage.totals([]) == %{
               requests: 0,
               input: 0,
               output: 0,
               cached: 0,
               reasoning: 0,
               cost: nil
             }
    end
  end

  describe "format_tokens/1" do
    test "abbreviates thousands and millions" do
      assert Usage.format_tokens(842) == "842"
      assert Usage.format_tokens(12_345) == "12.3k"
      assert Usage.format_tokens(1_250_000) == "1.25M"
    end
  end

  describe "format_cost/1" do
    test "formats dollars to three decimals" do
      assert Usage.format_cost(0.0421) == "$0.042"
      assert Usage.format_cost(0.0002) == "<$0.001"
      assert Usage.format_cost(nil) == nil
    end
  end
end
