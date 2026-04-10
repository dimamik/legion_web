defmodule LegionWeb.AssetsTest do
  use ExUnit.Case, async: true

  alias LegionWeb.Assets

  describe "init/1" do
    test "passes through the asset type" do
      assert Assets.init(:css) == :css
      assert Assets.init(:js) == :js
    end
  end

  describe "call/2 for CSS" do
    test "serves CSS with correct content type and cache headers" do
      conn =
        Plug.Test.conn(:get, "/css-abc123")
        |> Assets.call(:css)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/css"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert conn.halted
      assert byte_size(conn.resp_body) > 0
    end
  end

  describe "call/2 for JS" do
    test "serves JS with correct content type and cache headers" do
      conn =
        Plug.Test.conn(:get, "/js-abc123")
        |> Assets.call(:js)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert conn.halted
      assert byte_size(conn.resp_body) > 0
    end
  end

  describe "current_hash/1" do
    test "returns MD5 hash for CSS" do
      hash = Assets.current_hash(:css)
      assert is_binary(hash)
      assert String.length(hash) == 32
      assert String.match?(hash, ~r/^[a-f0-9]+$/)
    end

    test "returns MD5 hash for JS" do
      hash = Assets.current_hash(:js)
      assert is_binary(hash)
      assert String.length(hash) == 32
      assert String.match?(hash, ~r/^[a-f0-9]+$/)
    end

    test "CSS and JS hashes are different" do
      assert Assets.current_hash(:css) != Assets.current_hash(:js)
    end
  end

  describe "CSRF protection" do
    test "skips CSRF protection" do
      conn =
        Plug.Test.conn(:get, "/css-abc123")
        |> Assets.call(:css)

      assert conn.private[:plug_skip_csrf_protection] == true
    end
  end

  defp get_resp_header(conn, key) do
    for {k, v} <- conn.resp_headers, k == key, do: v
  end
end
