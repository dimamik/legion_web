defmodule LegionWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    {agent_tracker, agent_tracker_opts} = agent_tracker_config()

    children = [
      {Phoenix.PubSub, name: LegionWeb.PubSub},
      {agent_tracker, agent_tracker_opts},
      LegionWeb.HumanHandler
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LegionWeb.Supervisor)
  end

  @doc false
  def agent_tracker do
    agent_tracker_config() |> elem(0)
  end

  defp agent_tracker_config do
    Application.get_env(:legion_web, :agent_tracker, LegionWeb.AgentTracker.Telemetry)
    |> normalize_agent_tracker()
  end

  defp normalize_agent_tracker(agent_tracker) when is_atom(agent_tracker),
    do: {agent_tracker, []}

  defp normalize_agent_tracker({agent_tracker, opts})
       when is_atom(agent_tracker) and is_list(opts),
       do: {agent_tracker, opts}
end
