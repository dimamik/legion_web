defmodule LegionWeb.Components.AgentDetailTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias LegionWeb.Components.AgentDetail

  describe "identity_chip/1" do
    test "renders nothing without an identity" do
      assert render_component(&AgentDetail.identity_chip/1, identity: nil) |> String.trim() == ""
      assert render_component(&AgentDetail.identity_chip/1, identity: %{}) |> String.trim() == ""
    end

    test "renders a single pair as a plain chip" do
      html = render_component(&AgentDetail.identity_chip/1, identity: %{"ip" => "203.0.113.42"})

      assert html =~ "ip: 203.0.113.42"
      refute html =~ "+1"
      refute html =~ "data-note"
      refute html =~ "note-left"
      refute html =~ "tabindex"
    end

    test "leads with the first pair and lists the rest in the note" do
      html =
        render_component(&AgentDetail.identity_chip/1,
          identity: %{"tenant" => "acme", "ip" => "203.0.113.42", "roles" => ["admin", "ops"]}
        )

      assert html =~ "ip: 203.0.113.42"
      assert html =~ "+2"
      assert html =~ "note note-left"
      assert html =~ ~s(tabindex="0")
      assert html =~ ~s(data-note="roles: [&quot;admin&quot;, &quot;ops&quot;]\ntenant: acme")
    end
  end
end
