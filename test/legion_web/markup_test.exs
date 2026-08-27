defmodule LegionWeb.MarkupTest do
  use ExUnit.Case, async: true

  alias LegionWeb.Markup

  defp to_html({:safe, iodata}), do: IO.iodata_to_binary(iodata)

  describe "highlight/2" do
    test "highlights elixir via registered lexer" do
      html = Markup.highlight("def hello, do: :world", "elixir") |> to_html()
      assert html =~ "<span"
      assert html =~ "hello"
    end

    test "highlights lua via registered lexer" do
      html = Markup.highlight("local x = 1", "lua") |> to_html()
      assert html =~ "<span"
      assert html =~ "local"
    end

    test "falls back to escaped plaintext for unknown language" do
      html = Markup.highlight("<b>&</b>", "no-such-language") |> to_html()
      assert html == "&lt;b&gt;&amp;&lt;/b&gt;"
    end

    test "falls back to escaped plaintext for nil language" do
      html = Markup.highlight("<b>", nil) |> to_html()
      assert html == "&lt;b&gt;"
    end

    test "always returns a Phoenix.HTML safe tuple" do
      assert {:safe, _} = Markup.highlight("x", "elixir")
      assert {:safe, _} = Markup.highlight("x", "lua")
      assert {:safe, _} = Markup.highlight("x", nil)
    end
  end

  describe "markdown/1" do
    test "highlights lua fenced block" do
      html = Markup.markdown("```lua\nlocal x = 1\n```") |> to_html()
      assert html =~ ~s(<code class="language-lua highlight">)
      assert html =~ "<span"
    end

    test "highlights elixir fenced block" do
      html = Markup.markdown("```elixir\ndef x, do: 1\n```") |> to_html()
      assert html =~ ~s(<code class="language-elixir highlight">)
      assert html =~ "<span"
    end

    test "unescapes markdown entities before lexing" do
      html = Markup.markdown("```elixir\nx <> \"a\"\n```") |> to_html()
      refute html =~ "&amp;lt;"
      assert html =~ "&lt;&gt;"
    end

    test "leaves fenced block with unknown language as plain code" do
      html = Markup.markdown("```text\nhello <world>\n```") |> to_html()
      refute html =~ "<span"
      assert html =~ "hello &lt;world&gt;"
    end

    test "leaves unfenced code block untouched" do
      html = Markup.markdown("```\nplain\n```") |> to_html()
      refute html =~ "highlight"
      assert html =~ "plain"
    end

    test "renders ordinary markdown" do
      html = Markup.markdown("# Title\n\nsome *text*") |> to_html()
      assert html =~ "<h1>"
      assert html =~ "<em>text</em>"
    end
  end
end
