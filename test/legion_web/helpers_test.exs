defmodule LegionWeb.HelpersTest do
  use ExUnit.Case, async: true

  alias LegionWeb.Helpers

  describe "module_name/1" do
    test "extracts last segment of module atom" do
      assert Helpers.module_name(MyApp.Agents.WebResearcher) == "WebResearcher"
    end

    test "works with single-segment module" do
      assert Helpers.module_name(Agent) == "Agent"
    end
  end

  describe "full_module_name/1" do
    test "strips Elixir. prefix" do
      assert Helpers.full_module_name(MyApp.Agents.Worker) == "MyApp.Agents.Worker"
    end

    test "works with single-segment module" do
      assert Helpers.full_module_name(Agent) == "Agent"
    end
  end

  describe "relative_time/1" do
    test "returns dash for nil" do
      assert Helpers.relative_time(nil) == "—"
    end

    test "returns 'just now' for very recent timestamp" do
      now = System.system_time(:millisecond)
      assert Helpers.relative_time(now) == "just now"
    end

    test "returns seconds ago" do
      now = System.system_time(:millisecond)
      assert Helpers.relative_time(now - 5_000) == "5s ago"
    end

    test "returns minutes ago" do
      now = System.system_time(:millisecond)
      assert Helpers.relative_time(now - 120_000) == "2m ago"
    end

    test "returns hours ago" do
      now = System.system_time(:millisecond)
      assert Helpers.relative_time(now - 7_200_000) == "2h ago"
    end
  end

  describe "format_duration/2" do
    test "returns formatted duration for valid timestamps" do
      assert Helpers.format_duration(1000, 2500) == "1.5s"
    end

    test "returns nil when either arg is nil" do
      assert Helpers.format_duration(nil, 1000) == nil
      assert Helpers.format_duration(1000, nil) == nil
    end
  end

  describe "format_ms/1" do
    test "formats milliseconds" do
      assert Helpers.format_ms(500) == "500ms"
    end

    test "formats seconds" do
      assert Helpers.format_ms(1_500) == "1.5s"
    end

    test "formats minutes" do
      assert Helpers.format_ms(90_000) == "1.5m"
    end

    test "formats zero" do
      assert Helpers.format_ms(0) == "0ms"
    end

    test "returns nil for negative" do
      assert Helpers.format_ms(-1) == nil
    end
  end

  describe "status_class/1" do
    test "returns correct classes for known statuses" do
      assert Helpers.status_class(:running) =~ "bg-sol-green"
      assert Helpers.status_class(:idle) =~ "bg-sol-blue"
      assert Helpers.status_class(:waiting_for_human) =~ "bg-sol-yellow"
      assert Helpers.status_class(:done) =~ "bg-sol-cyan"
      assert Helpers.status_class(:error) =~ "bg-sol-red"
      assert Helpers.status_class(:dead) =~ "bg-sol-red"
    end

    test "returns fallback for unknown status" do
      assert Helpers.status_class(:something) =~ "bg-sol-base1"
    end
  end

  describe "status_label/1" do
    test "returns human-readable labels" do
      assert Helpers.status_label(:running) == "running"
      assert Helpers.status_label(:idle) == "idle"
      assert Helpers.status_label(:waiting_for_human) == "waiting"
      assert Helpers.status_label(:done) == "done"
      assert Helpers.status_label(:error) == "error"
      assert Helpers.status_label(:dead) == "failed"
    end

    test "converts unknown status to string" do
      assert Helpers.status_label(:custom) == "custom"
    end
  end

  describe "status_text_class/1" do
    test "returns text color classes for known statuses" do
      assert Helpers.status_text_class(:running) == "text-sol-green"
      assert Helpers.status_text_class(:done) == "text-sol-cyan"
      assert Helpers.status_text_class(:error) == "text-sol-red"
      assert Helpers.status_text_class(:dead) == "text-sol-red"
    end

    test "returns fallback for unknown status" do
      assert Helpers.status_text_class(:unknown) == "text-sol-base1"
    end
  end

  describe "truncate/2" do
    test "returns empty string for nil" do
      assert Helpers.truncate(nil) == ""
    end

    test "returns full string when under limit" do
      assert Helpers.truncate("short", 80) == "short"
    end

    test "truncates with ellipsis when over limit" do
      result = Helpers.truncate("hello world", 5)
      assert result == "hello…"
    end

    test "uses default max_len of 80" do
      short = String.duplicate("a", 80)
      long = String.duplicate("a", 81)
      assert Helpers.truncate(short) == short
      assert String.ends_with?(Helpers.truncate(long), "…")
    end
  end

  describe "inspect_value/2" do
    test "inspects a value with limits" do
      result = Helpers.inspect_value(%{a: 1, b: 2})
      assert is_binary(result)
      assert result =~ "a:"
    end

    test "truncates long output" do
      long_list = Enum.to_list(1..1000)
      result = Helpers.inspect_value(long_list, 50)
      assert String.length(result) <= 50
    end
  end

  describe "highlight_elixir/1" do
    test "returns Phoenix.HTML.safe tuple" do
      result = Helpers.highlight_elixir("def hello, do: :world")
      assert {:safe, _} = result
    end

    test "contains highlighted markup" do
      {:safe, html} = Helpers.highlight_elixir("defmodule Foo do end")
      html_string = IO.iodata_to_binary(html)
      assert html_string =~ "<span"
    end
  end

  describe "encode_run_id/1 and decode_run_id/1" do
    test "roundtrip with atom" do
      run_id = :some_run
      encoded = Helpers.encode_run_id(run_id)
      assert is_binary(encoded)
      assert Helpers.decode_run_id(encoded) == run_id
    end

    test "roundtrip with reference" do
      run_id = make_ref()
      encoded = Helpers.encode_run_id(run_id)
      assert Helpers.decode_run_id(encoded) == run_id
    end

    test "roundtrip with tuple" do
      run_id = {:run, 123}
      encoded = Helpers.encode_run_id(run_id)
      assert Helpers.decode_run_id(encoded) == run_id
    end

    test "decode returns nil for invalid base64" do
      assert Helpers.decode_run_id("not-valid-base64!!!") == nil
    end

    test "decode returns nil for corrupted binary" do
      assert Helpers.decode_run_id(Base.url_encode64(<<0, 1, 2>>, padding: false)) == nil
    end
  end

  describe "agent_topic/1" do
    test "builds topic string" do
      assert Helpers.agent_topic(:my_run) == "legion_web:agent::my_run"
    end

    test "handles reference run_id" do
      ref = make_ref()
      topic = Helpers.agent_topic(ref)
      assert String.starts_with?(topic, "legion_web:agent:")
      assert topic =~ "#Ref"
    end
  end
end
