defmodule LegionWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    source =
      Application.get_env(:legion_web, :source) || LegionWeb.AgentTracker.Source.Telemetry

    children = [
      {Phoenix.PubSub, name: LegionWeb.PubSub},
      {LegionWeb.AgentTracker, [{:source, source}]},
      LegionWeb.HumanHandler
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LegionWeb.Supervisor)
  end
end
