defmodule LegionWeb.Router do
  @moduledoc """
  Provides the `legion_dashboard/2` macro for mounting the Legion dashboard
  into a Phoenix router.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import LegionWeb.Router

        scope "/" do
          pipe_through :browser
          legion_dashboard "/legion"
        end
      end

  ## Options

  * `:as` — override the route name; defaults to `:legion_dashboard`

  * `:csp_nonce_assign_key` — CSP nonce keys for authenticating assets.
    May be `nil`, a single atom, or a map of atoms. Defaults to `nil`.

  * `:on_mount` — additional module callbacks invoked when the dashboard mounts

  * `:socket_path` — phoenix socket path for live communication, defaults to `"/live"`

  * `:transport` — phoenix socket transport, `"websocket"` or `"longpoll"`,
    defaults to `"websocket"`
  """

  @default_opts [
    socket_path: "/live",
    transport: "websocket"
  ]

  @transport_values ~w(longpoll websocket)

  @doc """
  Defines a Legion dashboard route.

  It requires a path where to mount the dashboard at and allows options to
  customize routing.
  """
  defmacro legion_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      prefix = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        {session_name, session_opts, route_opts} = LegionWeb.Router.__options__(prefix, opts)

        live_session session_name, session_opts do
          get "/css-:md5", LegionWeb.Assets, :css, as: :legion_web_asset
          get "/js-:md5", LegionWeb.Assets, :js, as: :legion_web_asset

          live "/", LegionWeb.DashboardLive, :index, route_opts
          live "/:run_id", LegionWeb.DashboardLive, :show, route_opts
        end
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias_node, env) do
    Macro.expand(alias_node, %{env | function: {:legion_dashboard, 2}})
  end

  defp expand_alias(other, _env), do: other

  @doc false
  def __options__(prefix, opts) do
    opts = Keyword.merge(@default_opts, opts)

    Enum.each(opts, &validate_opt!/1)

    on_mount = Keyword.get(opts, :on_mount, [])

    session_args = [
      prefix,
      opts[:socket_path],
      opts[:transport],
      opts[:csp_nonce_assign_key]
    ]

    session_opts = [
      on_mount: on_mount,
      session: {__MODULE__, :__session__, session_args},
      root_layout: {LegionWeb.Layouts, :root}
    ]

    session_name = Keyword.get(opts, :as, :legion_dashboard)

    {session_name, session_opts, as: session_name}
  end

  @doc false
  def __session__(conn, prefix, live_path, live_transport, csp_key) do
    csp_keys = expand_csp_nonce_keys(csp_key)

    %{
      "prefix" => prefix,
      "live_path" => live_path,
      "live_transport" => live_transport,
      "csp_nonces" => %{
        img: conn.assigns[csp_keys[:img]],
        style: conn.assigns[csp_keys[:style]],
        script: conn.assigns[csp_keys[:script]]
      }
    }
  end

  defp expand_csp_nonce_keys(nil), do: %{img: nil, style: nil, script: nil}
  defp expand_csp_nonce_keys(key) when is_atom(key), do: %{img: key, style: key, script: key}
  defp expand_csp_nonce_keys(map) when is_map(map), do: map

  defp validate_opt!({:csp_nonce_assign_key, key}) do
    unless is_nil(key) or is_atom(key) or is_map(key) do
      raise ArgumentError, """
      invalid :csp_nonce_assign_key, expected nil, an atom or a map with atom keys,
      got #{inspect(key)}
      """
    end
  end

  defp validate_opt!({:socket_path, path}) do
    unless is_binary(path) and byte_size(path) > 0 do
      raise ArgumentError, """
      invalid :socket_path, expected a binary URL, got: #{inspect(path)}
      """
    end
  end

  defp validate_opt!({:transport, transport}) do
    unless transport in @transport_values do
      raise ArgumentError, """
      invalid :transport, expected one of #{inspect(@transport_values)},
      got #{inspect(transport)}
      """
    end
  end

  defp validate_opt!(_option), do: :ok
end
