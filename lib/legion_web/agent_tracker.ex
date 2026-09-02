defmodule LegionWeb.AgentTracker.LegionAgent do
  @moduledoc "The dashboard projection of a tracked Legion agent."

  @enforce_keys [:agent_id, :status]
  defstruct [
    :agent_id,
    :parent_agent_id,
    :agent_module,
    :pid,
    :status,
    :identity,
    :started_at,
    :finished_at,
    :task,
    iterations: 0
  ]

  @type t :: %__MODULE__{
          agent_id: Legion.Store.agent_id(),
          parent_agent_id: Legion.Store.agent_id() | nil,
          agent_module: module() | nil,
          pid: pid() | nil,
          status: :running | :idle | :waiting_for_human | :done | :error | :dead,
          identity: map() | nil,
          started_at: integer() | nil,
          finished_at: integer() | nil,
          task: String.t() | nil,
          iterations: non_neg_integer()
        }
end

defmodule LegionWeb.AgentTracker.LegionEvent do
  @moduledoc "A dashboard event emitted for a tracked Legion agent."

  @enforce_keys [:seq, :agent_id, :type]
  defstruct [:seq, :agent_id, :type, :timestamp, data: %{}]

  @type t :: %__MODULE__{
          seq: pos_integer(),
          agent_id: Legion.Store.agent_id(),
          type: atom(),
          timestamp: integer() | nil,
          data: map()
        }
end

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

  alias LegionWeb.AgentTracker.{LegionAgent, LegionEvent}

  @type agent_id :: Legion.Store.agent_id()
  @type timestamp :: integer()
  @type status :: :running | :idle | :waiting_for_human | :done | :error | :dead
  @type agent :: LegionAgent.t()
  @type event :: LegionEvent.t()
  @type usage :: map()

  @doc "Lists up to `limit` tracked agents, newest first."
  @callback list_agents(pos_integer()) :: [agent()]

  @doc "Returns the tracked agent with the given ID, or `nil` when it is absent."
  @callback get_agent(agent_id()) :: agent() | nil

  @doc "Returns an agent's events in chronological order."
  @callback get_events(agent_id()) :: [event()]

  @doc """
  Returns an agent's LLM usage entries in request order.

  Each entry is the string-keyed usage map Legion records for one LLM request,
  including its `"at"` timestamp in milliseconds. Only the agent's own requests
  are included; a sub-agent's usage is tracked under the sub-agent.
  """
  @callback get_usage(agent_id()) :: [usage()]
end
