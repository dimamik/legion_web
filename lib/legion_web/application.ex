defmodule LegionWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: LegionWeb.PubSub},
      LegionWeb.AgentTracker,
      LegionWeb.HumanHandler
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LegionWeb.Supervisor)
  end
end
