defmodule LegionWeb.AgentTracker do
  @moduledoc """
  Query interface for a Legion agent activity tracker.

  An AgentTracker implementation provides the dashboard's read model for
  agents and their events. It may be backed by telemetry, a database listener,
  or another source entirely; this behavior deliberately does not prescribe a
  process model, storage mechanism, or ingestion strategy.

  `LegionWeb.Application` supervises the configured implementation. Consumers
  receive the selected tracker module and call this interface directly.
  """

  @type agent_id :: term()
  @type agent :: map()
  @type event :: map()

  @doc "Lists tracked agents, ordered from most recently started to oldest."
  @callback list_agents() :: [agent()]

  @doc "Returns the tracked agent with the given ID, or `nil` when it is absent."
  @callback get_agent(agent_id()) :: agent() | nil

  @doc "Returns an agent's events in chronological order."
  @callback get_events(agent_id()) :: [event()]
end
