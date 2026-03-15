# Development server for LegionWeb
#
# Run with: mix dev
#
# Starts a Phoenix endpoint at http://localhost:4001 with the Legion dashboard
# mounted at /legion, and spawns a demo agent to populate the UI.

# Demo Tools

defmodule DevTools.WebTool do
  @moduledoc "Fetches content from the web."
  use Legion.Tool

  @doc "Searches Hacker News for stories matching a query. Returns a list of maps with title, url, points, and author fields."
  def hacker_news_search(query, count \\ 10) when is_binary(query) and is_integer(count) and count > 0 do
    {:ok, %{body: %{"hits" => hits}}} =
      Req.get("https://hn.algolia.com/api/v1/search",
        params: [query: query, tags: "story", hitsPerPage: count]
      )

    Enum.map(hits, &Map.take(&1, ["title", "url", "points", "author"]))
  end

  @doc "Fetches a URL and returns the response body as text (truncated to 2000 chars)."
  def fetch(url) when is_binary(url) do
    {:ok, %{body: body}} = Req.get(url, max_retries: 0, receive_timeout: 10_000)

    text = if is_binary(body), do: body, else: inspect(body)
    String.slice(text, 0, 2000)
  end
end

# Demo Agents

defmodule DevAgents.HackerNewsAgent do
  @moduledoc """
  Searches Hacker News for stories matching a topic and returns the results.
  You MUST always call hacker_news_search before returning a response.
  """
  use Legion.Agent

  def tools, do: [DevTools.WebTool]
  def config, do: %{max_iterations: 5}
end

defmodule DevAgents.WebResearchAgent do
  @moduledoc """
  Fetches and summarizes content from URLs.
  Given a list of URLs, fetches each page and extracts key information.
  """
  use Legion.Agent

  def tools, do: [DevTools.WebTool]
  def config, do: %{max_iterations: 8}
end

defmodule DevAgents.LeadAgent do
  @moduledoc """
  Research team lead that asks the human what topic to research,
  delegates to HackerNewsAgent to find relevant stories, then to WebResearchAgent
  to fetch and summarize the most interesting ones.
  Your final summary must NOT contain any links or URLs. Instead, visit all relevant
  links yourself via WebResearchAgent and formulate your own informed opinion based
  on the actual content.
  """
  use Legion.Agent

  def tools, do: [Legion.Tools.AgentTool, Legion.Tools.HumanTool]

  def tool_config(Legion.Tools.AgentTool) do
    [agents: [DevAgents.HackerNewsAgent, DevAgents.WebResearchAgent]]
  end

  def tool_config(Legion.Tools.HumanTool), do: [handler: LegionWeb.HumanHandler]
  def config, do: %{max_iterations: 15}
end

# Demo agent spawner
defmodule DevAgents.Generator do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    Process.send_after(self(), :spawn_demo, 1_000)
    {:ok, []}
  end

  @impl true
  def handle_info(:spawn_demo, state) do
    {:ok, pid} = Legion.start_link(DevAgents.LeadAgent)

    Legion.cast(
      pid,
      "Ask the human what topic they'd like researched, then use DevAgents.HackerNewsAgent to find relevant stories and DevAgents.WebResearchAgent to fetch and summarize the most interesting ones. Return a final synthesis."
    )

    {:noreply, state}
  end
end

# Phoenix

defmodule DevWeb.Router.RedirectController do
  use Phoenix.Controller, formats: [:html]
  def index(conn, _), do: redirect(conn, to: "/legion")
end

defmodule DevWeb.Router do
  use Phoenix.Router, helpers: false

  import Phoenix.LiveView.Router
  import LegionWeb.Router

  pipeline :browser do
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :browser
    get "/", DevWeb.Router.RedirectController, :index
    legion_dashboard "/legion"
  end
end

defmodule DevWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :legion_web

  socket "/live", Phoenix.LiveView.Socket
  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader

  plug Plug.Session,
    store: :cookie,
    key: "_legion_web_dev_key",
    signing_salt: "legion_dev_salt"

  plug DevWeb.Router
end

defmodule DevWeb.ErrorHTML do
  use Phoenix.Component
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

# Configuration

port = System.get_env("PORT", "4001") |> String.to_integer()

Application.put_env(:legion_web, DevWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  debug_errors: true,
  http: [port: port],
  live_view: [signing_salt: "legion_dev_lv_salt_00000000000000"],
  pubsub_server: LegionWeb.PubSub,
  render_errors: [formats: [html: DevWeb.ErrorHTML], layout: false],
  secret_key_base: "i+JDM3QJHGABlqo/resaYVrHkWWVf30feIP8ZQeV0iMsNP52volhWE480W69ib2g",
  url: [host: "localhost"],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css)$",
      ~r"lib/legion_web/.*(ex|heex)$"
    ]
  ]
)

Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:phoenix, :persistent, true)

Task.async(fn ->
  children = [
    DevWeb.Endpoint,
    DevAgents.Generator
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

  IO.puts("""

  Legion Web dev server running at http://localhost:#{port}/legion

  """)

  Process.sleep(:infinity)
end)
