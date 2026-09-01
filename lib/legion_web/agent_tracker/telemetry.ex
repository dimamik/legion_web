defmodule LegionWeb.AgentTracker.Telemetry do
  @moduledoc """
  Tracks Legion agent invocations and their telemetry events.

  Maintains three ETS tables:
  - `:legion_web_agents` — one record per tracked agent, keyed by agent_id
  - `:legion_web_events` — ordered event log per agent, keyed by {agent_id, seq}
  - `:legion_web_usage` — ordered LLM usage entries per agent, keyed by {agent_id, seq}

  Attaches to Legion and dashboard telemetry events on startup. Broadcasts
  changes via `LegionWeb.PubSub` so LiveView subscribers receive real-time
  updates.

  Usage is recorded only while `config :legion, :track_usage` is enabled (the
  default), matching what Legion itself persists.
  """

  use GenServer

  @behaviour LegionWeb.AgentTracker

  alias LegionWeb.AgentTracker.{LegionAgent, LegionEvent}

  @agents_table :legion_web_agents
  @events_table :legion_web_events
  @usage_table :legion_web_usage
  @max_agents 100
  @max_events_per_agent 500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def list_agents(limit) do
    @agents_table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.started_at, :desc)
    |> Enum.take(limit)
  end

  @impl true
  def get_agent(agent_id) do
    case :ets.lookup(@agents_table, agent_id) do
      [{^agent_id, record}] -> record
      [] -> nil
    end
  end

  @impl true
  def get_events(agent_id) do
    :ets.select(@events_table, [
      {{{agent_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @impl true
  def get_usage(agent_id) do
    :ets.select(@usage_table, [
      {{{agent_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @impl true
  def init(_opts) do
    :ets.new(@agents_table, [:named_table, :public, :set])
    :ets.new(@events_table, [:named_table, :public, :ordered_set])
    :ets.new(@usage_table, [:named_table, :public, :ordered_set])

    attach_telemetry_handlers()

    {:ok, %{seq: 0, monitors: %{}}}
  end

  @impl true
  def handle_info({:agent_started, agent_id, record}, state) do
    evict_if_over_limit()

    if pid = record.pid do
      ref = Process.monitor(pid)
      state = put_in(state.monitors[ref], agent_id)
      broadcast_agent_update(agent_id, :started, record)
      {:noreply, state}
    else
      broadcast_agent_update(agent_id, :started, record)
      {:noreply, state}
    end
  end

  def handle_info({:waiting_for_human, agent_id}, state) do
    update_agent(agent_id, %{status: :waiting_for_human})
    broadcast_agent_update(agent_id, :waiting, get_agent(agent_id))
    {:noreply, state}
  end

  def handle_info({:agent_stopped, agent_id}, state) do
    update_agent(agent_id, %{status: :done, finished_at: System.system_time(:millisecond)})
    broadcast_agent_update(agent_id, :stopped, get_agent(agent_id))
    {:noreply, state}
  end

  def handle_info({:status_change, agent_id, status, extra}, state) do
    update_agent(agent_id, Map.put(extra, :status, status))
    broadcast_agent_update(agent_id, status, get_agent(agent_id))
    {:noreply, state}
  end

  def handle_info({:event, agent_id, type, data}, state) do
    seq = state.seq + 1

    event = %LegionEvent{
      seq: seq,
      agent_id: agent_id,
      type: type,
      timestamp: System.system_time(:millisecond),
      data: data
    }

    if count_events(agent_id) >= @max_events_per_agent do
      evict_oldest_event(agent_id)
    end

    :ets.insert(@events_table, {{agent_id, seq}, event})

    broadcast_event(agent_id, event)
    record_usage(agent_id, type, data, seq)
    {:noreply, %{state | seq: seq}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {agent_id, monitors} ->
        case get_agent(agent_id) do
          %{status: status} when status in [:done, :error] ->
            :ok

          _ ->
            update_agent(agent_id, %{status: :dead, finished_at: System.system_time(:millisecond)})

            broadcast_agent_update(agent_id, :dead, get_agent(agent_id))
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def handle_telemetry([:legion, :agent, :started], _measurements, meta, _config) do
    record = %LegionAgent{
      agent_id: meta.agent_id,
      parent_agent_id: meta[:parent_agent_id],
      agent_module: meta.agent,
      pid: self(),
      status: :running,
      started_at: System.system_time(:millisecond),
      finished_at: nil,
      task: nil,
      iterations: 0
    }

    :ets.insert(@agents_table, {meta.agent_id, record})
    notify_tracker({:agent_started, meta.agent_id, record})
  end

  def handle_telemetry([:legion, :agent, :stopped], _measurements, meta, _config) do
    notify_tracker({:agent_stopped, meta.agent_id})
  end

  def handle_telemetry([:legion, :agent, :message, :start], _measurements, meta, _config) do
    task = if is_binary(meta[:message]), do: meta[:message]
    updates = if task, do: %{task: task}, else: %{}

    notify_tracker({:status_change, meta.agent_id, :running, updates})
    notify_tracker({:event, meta.agent_id, :message_start, meta})
  end

  def handle_telemetry([:legion, :agent, :message, :stop], measurements, meta, _config) do
    notify_tracker({:status_change, meta.agent_id, :idle, %{iterations: meta[:iterations] || 0}})

    notify_tracker(
      {:event, meta.agent_id, :message_stop,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :agent, :message, :exception], measurements, meta, _config) do
    notify_tracker({:status_change, meta.agent_id, :error, %{}})

    notify_tracker(
      {:event, meta.agent_id, :message_exception,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :iteration, :start], _measurements, meta, _config) do
    track_and_forward(meta.agent_id, :iteration_start, meta)
  end

  def handle_telemetry([:legion, :iteration, :stop], measurements, meta, _config) do
    track_and_forward(
      meta.agent_id,
      :iteration_stop,
      Map.merge(meta, %{duration: measurements[:duration]})
    )
  end

  def handle_telemetry([:legion, :llm, :request, :start], _measurements, meta, _config) do
    track_and_forward(meta.agent_id, :llm_start, meta)
  end

  def handle_telemetry([:legion, :llm, :request, :stop], measurements, meta, _config) do
    track_and_forward(
      meta.agent_id,
      :llm_stop,
      Map.merge(meta, %{duration: measurements[:duration]})
    )
  end

  def handle_telemetry([:legion, :sandbox, :eval, :start], _measurements, meta, _config) do
    track_and_forward(meta.agent_id, :eval_start, meta)
  end

  def handle_telemetry([:legion, :sandbox, :eval, :stop], measurements, meta, _config) do
    track_and_forward(
      meta.agent_id,
      :eval_stop,
      Map.merge(meta, %{duration: measurements[:duration]})
    )
  end

  def handle_telemetry([:legion_web, :agent, :waiting_for_human], _measurements, meta, _config) do
    notify_tracker({:waiting_for_human, meta.agent_id})
  end

  def handle_telemetry([:legion_web, :agent, :human_response], _measurements, meta, _config) do
    notify_tracker({:event, meta.agent_id, :human_response, %{text: meta.text}})
    notify_tracker({:status_change, meta.agent_id, :running, %{}})
  end

  defp attach_telemetry_handlers do
    :telemetry.attach_many(
      "legion_web_tracker",
      [
        [:legion, :agent, :started],
        [:legion, :agent, :stopped],
        [:legion, :agent, :message, :start],
        [:legion, :agent, :message, :stop],
        [:legion, :agent, :message, :exception],
        [:legion, :iteration, :start],
        [:legion, :iteration, :stop],
        [:legion, :llm, :request, :start],
        [:legion, :llm, :request, :stop],
        [:legion, :sandbox, :eval, :start],
        [:legion, :sandbox, :eval, :stop],
        [:legion_web, :agent, :waiting_for_human],
        [:legion_web, :agent, :human_response]
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  defp track_and_forward(agent_id, type, data) do
    notify_tracker({:event, agent_id, type, data})
    forward_to_parent(agent_id, type, data)
  end

  # Telemetry handlers run in the emitting process. A bare send to the
  # registered name raises while the tracker restarts, and telemetry
  # permanently detaches a handler that raises - so drop the message instead.
  defp notify_tracker(message) do
    if pid = Process.whereis(__MODULE__), do: send(pid, message)
    :ok
  end

  defp update_agent(agent_id, updates) do
    case :ets.lookup(@agents_table, agent_id) do
      [{^agent_id, record}] ->
        :ets.insert(@agents_table, {agent_id, struct(record, updates)})

      [] ->
        :ok
    end
  end

  # Usage is recorded only for the agent's own LLM requests. A sub-agent's
  # llm_stop is also forwarded to its parent, but that copy still carries the
  # sub-agent's agent_id in its data and is skipped here.
  #
  # ponytail: rebroadcasts the full usage list per request (quadratic over a
  # conversation); broadcast deltas if very long conversations show up.
  defp record_usage(agent_id, :llm_stop, %{agent_id: agent_id, usage: usage}, seq)
       when is_map(usage) do
    if track_usage?() do
      :ets.insert(@usage_table, {{agent_id, seq}, usage})
      broadcast_usage(agent_id, get_usage(agent_id))
    end

    :ok
  end

  defp record_usage(_agent_id, _type, _data, _seq), do: :ok

  # Same key Legion reads when an agent starts.
  defp track_usage?, do: Application.get_env(:legion, :track_usage, true)

  defp count_events(agent_id) do
    :ets.select_count(@events_table, [{{{agent_id, :_}, :_}, [], [true]}])
  end

  # The events table is an ordered_set keyed by {agent_id, seq}, so the next
  # key after {agent_id, 0} is the agent's oldest event.
  defp evict_oldest_event(agent_id) do
    case :ets.next(@events_table, {agent_id, 0}) do
      {^agent_id, _seq} = oldest_key -> :ets.delete(@events_table, oldest_key)
      _ -> :ok
    end
  end

  # ponytail: evicts at most one finished agent per start, so with more than
  # @max_agents concurrently active agents the table grows past the cap;
  # evict in a loop if that ever becomes a real workload.
  defp evict_if_over_limit do
    if :ets.info(@agents_table, :size) > @max_agents do
      @agents_table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1.status not in [:running, :waiting_for_human]))
      |> Enum.sort_by(& &1.started_at)
      |> List.first()
      |> case do
        nil -> :ok
        oldest -> delete_agent(oldest.agent_id)
      end
    end
  end

  defp delete_agent(agent_id) do
    :ets.delete(@agents_table, agent_id)
    :ets.select_delete(@events_table, [{{{agent_id, :_}, :_}, [], [true]}])
    :ets.select_delete(@usage_table, [{{{agent_id, :_}, :_}, [], [true]}])
  end

  defp broadcast_agent_update(agent_id, event, record) do
    Phoenix.PubSub.broadcast(LegionWeb.PubSub, "legion_web:agents", {event, agent_id, record})
  end

  defp broadcast_usage(agent_id, usage) do
    Phoenix.PubSub.broadcast(
      LegionWeb.PubSub,
      "legion_web:agent:#{inspect(agent_id)}",
      {:usage, agent_id, usage}
    )
  end

  defp broadcast_event(agent_id, event) do
    Phoenix.PubSub.broadcast(
      LegionWeb.PubSub,
      "legion_web:agent:#{inspect(agent_id)}",
      {:new_event, event}
    )
  end

  defp forward_to_parent(agent_id, type, data) do
    case :ets.lookup(@agents_table, agent_id) do
      [{^agent_id, %{parent_agent_id: parent_agent_id}}] when not is_nil(parent_agent_id) ->
        notify_tracker({:event, parent_agent_id, type, data})

      _ ->
        :ok
    end
  end
end
