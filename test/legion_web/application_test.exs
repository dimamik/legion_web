defmodule LegionWeb.ApplicationTest do
  use ExUnit.Case, async: true

  test "registers the syntect Elixir lexer, which makeup_syntect leaves disabled by default" do
    assert {MakeupSyntect.Lexer, [language: "Elixir"]} =
             Makeup.Registry.get_lexer_by_name("elixir")

    assert {MakeupSyntect.Lexer, [language: "Elixir"]} =
             Makeup.Registry.get_lexer_by_extension("exs")
  end
end
