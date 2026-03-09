defmodule LegionWeb.Layouts do
  use LegionWeb, :html

  embed_templates "layouts/*"

  defp asset_path(conn, asset) when asset in [:css, :js] do
    hash = LegionWeb.Assets.current_hash(asset)

    {_dash, _routing, meta} = conn.private.phoenix_live_view

    prefix = get_in(meta, [:extra, :session, Access.elem(2), Access.at(0)])

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      "#{prefix}/#{asset}-#{hash}"
    )
  end
end
