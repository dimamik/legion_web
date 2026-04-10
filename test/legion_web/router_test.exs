defmodule LegionWeb.RouterTest do
  use ExUnit.Case, async: true

  alias LegionWeb.Router

  describe "__options__/2" do
    test "returns session name, opts, and route opts with defaults" do
      {session_name, session_opts, route_opts} = Router.__options__("/legion", [])

      assert session_name == :legion_dashboard
      assert route_opts == [as: :legion_dashboard]
      assert Keyword.get(session_opts, :root_layout) == {LegionWeb.Layouts, :root}
      assert Keyword.get(session_opts, :on_mount) == []
    end

    test "respects custom :as option" do
      {session_name, _session_opts, route_opts} =
        Router.__options__("/legion", as: :my_dashboard)

      assert session_name == :my_dashboard
      assert route_opts == [as: :my_dashboard]
    end

    test "passes on_mount through" do
      {_name, session_opts, _route_opts} =
        Router.__options__("/legion", on_mount: [SomeHook])

      assert Keyword.get(session_opts, :on_mount) == [SomeHook]
    end

    test "stores session function with correct args" do
      {_name, session_opts, _route_opts} =
        Router.__options__("/my-prefix", socket_path: "/ws", transport: "longpoll")

      {module, function, args} = Keyword.get(session_opts, :session)
      assert module == LegionWeb.Router
      assert function == :__session__
      assert ["/my-prefix", "/ws", "longpoll", nil] = args
    end
  end

  describe "__session__/5" do
    test "builds session map with prefix and transport config" do
      conn = %Plug.Conn{assigns: %{}}

      session = Router.__session__(conn, "/legion", "/live", "websocket", nil)

      assert session["prefix"] == "/legion"
      assert session["live_path"] == "/live"
      assert session["live_transport"] == "websocket"
      assert session["csp_nonces"] == %{img: nil, style: nil, script: nil}
    end

    test "extracts CSP nonces from conn assigns with atom key" do
      conn = %Plug.Conn{assigns: %{csp_nonce: "abc123"}}

      session = Router.__session__(conn, "/legion", "/live", "websocket", :csp_nonce)

      assert session["csp_nonces"] == %{img: "abc123", style: "abc123", script: "abc123"}
    end

    test "extracts CSP nonces from conn assigns with map keys" do
      conn = %Plug.Conn{
        assigns: %{img_nonce: "img1", style_nonce: "style1", script_nonce: "script1"}
      }

      csp_keys = %{img: :img_nonce, style: :style_nonce, script: :script_nonce}
      session = Router.__session__(conn, "/legion", "/live", "websocket", csp_keys)

      assert session["csp_nonces"] == %{img: "img1", style: "style1", script: "script1"}
    end
  end

  describe "option validation" do
    test "raises on invalid transport" do
      assert_raise ArgumentError, ~r/invalid :transport/, fn ->
        Router.__options__("/legion", transport: "invalid")
      end
    end

    test "raises on empty socket_path" do
      assert_raise ArgumentError, ~r/invalid :socket_path/, fn ->
        Router.__options__("/legion", socket_path: "")
      end
    end

    test "raises on non-binary socket_path" do
      assert_raise ArgumentError, ~r/invalid :socket_path/, fn ->
        Router.__options__("/legion", socket_path: 123)
      end
    end

    test "raises on invalid csp_nonce_assign_key" do
      assert_raise ArgumentError, ~r/invalid :csp_nonce_assign_key/, fn ->
        Router.__options__("/legion", csp_nonce_assign_key: "string")
      end
    end

    test "accepts valid csp_nonce_assign_key as atom" do
      {_name, _opts, _route_opts} =
        Router.__options__("/legion", csp_nonce_assign_key: :my_nonce)
    end

    test "accepts valid csp_nonce_assign_key as nil" do
      {_name, _opts, _route_opts} =
        Router.__options__("/legion", csp_nonce_assign_key: nil)
    end

    test "accepts valid csp_nonce_assign_key as map" do
      {_name, _opts, _route_opts} =
        Router.__options__("/legion",
          csp_nonce_assign_key: %{img: :img_nonce, style: :style_nonce, script: :script_nonce}
        )
    end

    test "accepts valid transport values" do
      for transport <- ~w(websocket longpoll) do
        {_name, _opts, _route_opts} =
          Router.__options__("/legion", transport: transport)
      end
    end
  end
end
