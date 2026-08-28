defmodule LegionWeb.Components.UsageTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LegionWeb.Components.Usage

  @usage [
    %{
      "input_tokens" => 1_800,
      "output_tokens" => 90,
      "cached_tokens" => 0,
      "total_cost" => 0.007,
      "at" => 0
    },
    %{
      "input_tokens" => 6_200,
      "output_tokens" => 1_150,
      "cached_tokens" => 3_300,
      "reasoning_tokens" => 380,
      "at" => 1
    }
  ]

  describe "summary/1" do
    test "renders input, output and cost" do
      html = render_component(&Usage.summary/1, usage: @usage)

      assert html =~ "8.0k"
      assert html =~ "1.2k"
      assert html =~ "$0.007"
      assert html =~ "2 requests"
      assert html =~ "May not match the provider invoice"
    end

    test "renders nothing without usage" do
      assert render_component(&Usage.summary/1, usage: []) |> String.trim() == ""
    end
  end

  describe "panel/1" do
    test "renders totals and one row per request" do
      html = render_component(&Usage.panel/1, usage: @usage)

      assert html =~ "Requests"
      assert html =~ "3.3k"
      assert html =~ "6200"
      assert html =~ "1150"
      assert html =~ "380"
      assert html =~ ~s(phx-click="close_usage")
    end
  end
end
