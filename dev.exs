# Development server for LegionWeb
#
# Run with: mix dev
#
# Starts a Phoenix endpoint at http://localhost:4001 with the Legion dashboard
# mounted at /legion, and spawns a demo agent to populate the UI.

# Load .env from parent legion directory
for env_path <- ["../legion/.env", "../.env"] do
  path = Path.expand(env_path, __DIR__)

  if File.exists?(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> System.put_env(String.trim(key), String.trim(value))
        _ -> :ok
      end
    end)
  end
end

# Demo Tools

defmodule DevTools.MathTool do
  @moduledoc "A simple math helper tool for demo purposes."
  use Legion.Tool

  @doc "Adds two numbers together."
  def add(a, b) when is_number(a) and is_number(b), do: a + b

  @doc "Multiplies two numbers."
  def multiply(a, b) when is_number(a) and is_number(b), do: a * b

  @doc "Computes factorial of n."
  def factorial(n) when is_integer(n) and n >= 0 do
    if n <= 1, do: 1, else: n * factorial(n - 1)
  end
end

defmodule DevTools.TextTool do
  @moduledoc "A text processing tool for demo purposes."
  use Legion.Tool

  @doc "Counts the number of words in a string."
  def word_count(text) when is_binary(text) do
    text |> String.split(~r/\s+/, trim: true) |> length()
  end

  @doc "Reverses a string."
  def reverse(text) when is_binary(text), do: String.reverse(text)

  @doc "Converts text to uppercase."
  def upcase(text) when is_binary(text), do: String.upcase(text)
end

# Demo Agents

defmodule DevAgents.MathAgent do
  @moduledoc "Solves math problems step by step using available tools."
  use Legion.Agent

  def tools, do: [DevTools.MathTool]
  def config, do: %{max_iterations: 5}
end

defmodule DevAgents.TextAgent do
  @moduledoc "Processes and analyzes text using available tools."
  use Legion.Agent

  def tools, do: [DevTools.TextTool]
  def config, do: %{max_iterations: 5}
end

defmodule DevAgents.CoordinatorAgent do
  @moduledoc """
  Coordinates tasks between specialized sub-agents.
  Can delegate math tasks and text tasks to respective agents.
  Ask the human if you need clarification on what to do.
  """
  use Legion.Agent

  def tools, do: [Legion.Tools.AgentTool, Legion.Tools.HumanTool]

  def tool_config(Legion.Tools.AgentTool) do
    [agents: [DevAgents.MathAgent, DevAgents.TextAgent]]
  end

  def tool_config(Legion.Tools.HumanTool), do: [handler: LegionWeb.HumanHandler]
  def config, do: %{max_iterations: 15}
end

# Demo agent spawner — starts long-lived agents so the dashboard can interact
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
    {:ok, pid} = Legion.start_link(DevAgents.CoordinatorAgent)

    Legion.cast(
      pid,
      "Ask the human what they'd like to do, then demonstrate both math and text capabilities."
    )

    {:noreply, state}
  end
end

# Phoenix

defmodule DevWeb.Router.RedirectController do
  use Phoenix.Controller
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
