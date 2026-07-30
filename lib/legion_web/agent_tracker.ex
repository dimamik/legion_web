defmodule LegionWeb.AgentTracker do
  @moduledoc """
  Query interface for a Legion agent activity tracker.

  An implementation provides the dashboard's read model for agents and their
  events. The configured tracker is supervised by LegionWeb and called directly
  by the dashboard.

  ## Built-in trackers

    - `LegionWeb.AgentTracker.Telemetry` is the default. It keeps recent agents
      and events in memory from Legion telemetry.
    - `LegionWeb.AgentTracker.Postgres` rebuilds the dashboard from a
      PostgreSQL-backed `Legion.Store` and follows changes through database
      notifications.

  The telemetry tracker needs no configuration. To select another tracker,
  configure its module and startup options:

      config :legion_web, :agent_tracker,
        {LegionWeb.AgentTracker.Postgres, store: MyApp.AgentStore}

  A custom tracker must implement this behavior and provide a child
  specification so LegionWeb can supervise it. Implementations may use any
  process model, storage mechanism, or ingestion strategy as long as they
  return the records described by this interface.
  """

  @type agent_id :: term()
  @type timestamp :: integer()
  @type status :: :running | :idle | :waiting_for_human | :done | :error | :dead
  @type agent :: %{
          required(:agent_id) => agent_id(),
          required(:parent_agent_id) => agent_id() | nil,
          required(:agent_module) => module(),
          required(:pid) => pid() | nil,
          required(:status) => status(),
          required(:started_at) => timestamp() | nil,
          optional(:finished_at) => timestamp() | nil,
          required(:task) => String.t() | nil,
          required(:iterations) => non_neg_integer()
        }
  @type event :: %{
          required(:seq) => pos_integer(),
          required(:agent_id) => agent_id(),
          required(:type) => atom(),
          required(:timestamp) => timestamp() | nil,
          required(:data) => map()
        }

  @doc "Lists tracked agents, ordered from most recently started to oldest."
  @callback list_agents() :: [agent()]

  @doc "Returns the tracked agent with the given ID, or `nil` when it is absent."
  @callback get_agent(agent_id()) :: agent() | nil

  @doc "Returns an agent's events in chronological order."
  @callback get_events(agent_id()) :: [event()]
end
