# Development server for LegionWeb
#
# Run with: mix dev
#
# Starts a Phoenix endpoint at http://localhost:4001 with the Legion dashboard
# mounted at /legion, and spawns the Product Scout demo.
#
# Product Scout - multi-agent system that finds the best product in any category.
#
#   Coordinator (HumanTool + AgentTool + FileOps)
#     |-> asks user clarifying questions while researching in parallel
#     |-> WebResearcher (WebSearch tool) - searches the web for real product data
#     |-> ProductOracle (no tools) - provides LLM opinions and recommendations
#     |-> synthesizes everything into a final Markdown report with pros/cons

# --- Tools ---

defmodule ProductScout.Tools.WebSearch do
  @moduledoc "Searches the web for product information using DuckDuckGo."
  use Legion.Tool

  @doc """
  Searches DuckDuckGo for a query and returns a list of result maps with :title, :url, and :snippet keys.
  Use specific queries like "best running shoes 2025 review" for best results.
  """
  def search(query, max_results \\ 8) when is_binary(query) and is_integer(max_results) do
    {:ok, %{body: body}} =
      Req.get("https://html.duckduckgo.com/html/",
        params: [q: query],
        headers: [{"user-agent", "Mozilla/5.0 (compatible; ProductScout/1.0)"}],
        max_retries: 1,
        receive_timeout: 30_000
      )

    body
    |> Floki.parse_document!()
    |> Floki.find(".result")
    |> Enum.take(max_results)
    |> Enum.map(fn result ->
      title = result |> Floki.find(".result__title") |> Floki.text() |> String.trim()
      snippet = result |> Floki.find(".result__snippet") |> Floki.text() |> String.trim()

      url =
        case Floki.find(result, ".result__url") do
          [] -> ""
          [node | _] -> node |> Floki.text() |> String.trim()
        end

      %{title: title, url: url, snippet: snippet}
    end)
    |> Enum.reject(fn r -> r.title == "" end)
  end

  @doc """
  Fetches a URL and returns the text content (truncated to 3000 chars).
  Useful for reading product review pages.
  """
  def fetch_page(url) when is_binary(url) do
    {:ok, %{body: body}} = Req.get(url, max_retries: 0, receive_timeout: 30_000)
    text = if is_binary(body), do: body, else: inspect(body)
    String.slice(text, 0, 3000)
  end
end

defmodule ProductScout.Tools.ParallelAgents do
  @moduledoc "Runs multiple sub-agents in parallel and returns all results."
  use Legion.Tool

  @doc """
  Runs a list of {agent_module, task} tuples concurrently.
  Returns a list of results in the same order.

  Example:
    ProductScout.Tools.ParallelAgents.run([
      {ProductScout.Agents.WebResearcher, "find best headphones reviews"},
      {ProductScout.Agents.ProductOracle, "what are the best headphones?"}
    ])
    #=> [web_research_result, oracle_opinion_result]
  """
  def run(tasks) when is_list(tasks) do
    allowed = Vault.get(__MODULE__, [])[:agents] || []

    for {agent, _task} <- tasks do
      unless agent in allowed do
        raise ArgumentError, "agent #{inspect(agent)} is not allowed; allowed: #{inspect(allowed)}"
      end
    end

    {:ok, results} = Legion.parallel(tasks)
    results
  end
end

defmodule ProductScout.Tools.FileOps do
  @moduledoc "Writes content to files on disk."
  use Legion.Tool

  @doc "Saves the given content string to a file at the given path. Returns a confirmation message."
  def save(filename, content) when is_binary(filename) and is_binary(content) do
    File.write!(filename, content)
    "Saved #{byte_size(content)} bytes to #{filename}"
  end
end

# --- Agents ---

defmodule ProductScout.Agents.WebResearcher do
  @moduledoc """
  Web researcher that finds real product information from the internet.

  Only report what you find in search results - never fill gaps with your own knowledge.
  If results are thin, say so.

  Process:
  1. Run multiple varied searches (reviews, comparisons, reddit, buyer guides).
  2. Use fetch_page on the most promising results - snippets are often incomplete.
  3. Cross-reference across sources for credibility.

  For each product, report: name/model, price (or "not found"), pros/cons from reviews,
  and which sources mentioned it. Return as a structured list, not prose.
  """
  use Legion.Agent

  def tools, do: [ProductScout.Tools.WebSearch]
  def config, do: %{max_iterations: 100, sandbox_timeout: :infinity}
end

defmodule ProductScout.Agents.ProductOracle do
  @moduledoc """
  Product opinion oracle - shares LLM-based product knowledge.

  Note your knowledge cutoff upfront and flag fast-changing categories (phones, laptops)
  vs stable ones (cookware, tools).

  Be opinionated: rank your top picks, explain trade-offs, mention common pitfalls,
  and include underrated "sleeper picks". Focus on what separates good from bad
  in the category.
  """
  use Legion.Agent

  def config, do: %{max_iterations: 100, sandbox_timeout: :infinity}
end

defmodule ProductScout.Agents.Coordinator do
  @moduledoc """
  Product Scout coordinator - helps users find the best product in any category.

  Sub-agents:
  - ProductScout.Agents.WebResearcher - web search for real product data
  - ProductScout.Agents.ProductOracle - LLM opinions and product knowledge

  Use ParallelAgents.run/1 to launch both at once.

  ## Workflow

  1. Ask the user what they're looking for (HumanTool). Don't research until you know.
  2. Launch WebResearcher + ProductOracle in parallel.
  3. Ask clarifying questions (budget, use case, must-haves) and refine with follow-up searches.
  4. Synthesize into a Markdown report and save with FileOps.

  ## Report format

  For each top pick (at least 3), include: price (with source), pros, cons, sources,
  and LLM opinion. Every product must have both pros and cons - ask the Oracle for
  known drawbacks if web sources don't mention any.

  End with a verdict tailored to the user's needs and a brief methodology section.
  Save to "product_scout_report.md".
  """
  use Legion.Agent

  def tools, do: [ProductScout.Tools.ParallelAgents, Legion.Tools.HumanTool, ProductScout.Tools.FileOps]

  def tool_config(ProductScout.Tools.ParallelAgents) do
    [agents: [ProductScout.Agents.WebResearcher, ProductScout.Agents.ProductOracle]]
  end

  def tool_config(Legion.Tools.HumanTool), do: [handler: LegionWeb.HumanHandler]
  def tool_config(_), do: []

  def config, do: %{max_iterations: 100, sandbox_timeout: :infinity}
end

# --- Demo spawner ---

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
    {:ok, pid} = Legion.start_link(ProductScout.Agents.Coordinator)

    Legion.cast(
      pid,
      "Ask me what product I'm looking for. Do NOT research anything yet - just ask."
    )

    {:noreply, state}
  end
end

# --- Phoenix ---

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

# --- Configuration ---

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

  Product Scout demo started - open the dashboard to interact!

  """)

  Process.sleep(:infinity)
end)
