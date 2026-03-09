defmodule LegionWeb.AgentTracker do
  @moduledoc """
  Tracks Legion agent invocations and their telemetry events.

  Maintains two ETS tables:
  - `:legion_web_agents` — one record per agent run, keyed by run_id
  - `:legion_web_events` — ordered event log per agent, keyed by {run_id, seq}

  Attaches to all Legion telemetry events on startup. Broadcasts changes via
  `LegionWeb.PubSub` so LiveView subscribers receive real-time updates.
  """

  use GenServer

  @agents_table :legion_web_agents
  @events_table :legion_web_events
  @max_agents 100
  @max_events_per_agent 500

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list_agents do
    @agents_table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.started_at, :desc)
  end

  def get_agent(run_id) do
    case :ets.lookup(@agents_table, run_id) do
      [{^run_id, record}] -> record
      [] -> nil
    end
  end

  def get_events(run_id) do
    :ets.select(@events_table, [
      {{{run_id, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    :ets.new(@agents_table, [:named_table, :public, :set])
    :ets.new(@events_table, [:named_table, :public, :ordered_set])

    attach_telemetry_handlers()

    {:ok, %{seq: 0, monitors: %{}}}
  end

  @impl true
  def handle_info({:agent_started, run_id, record}, state) do
    evict_if_over_limit()

    if pid = record.pid do
      ref = Process.monitor(pid)
      state = put_in(state.monitors[ref], run_id)
      broadcast_agent_update(run_id, :started, record)
      {:noreply, state}
    else
      broadcast_agent_update(run_id, :started, record)
      {:noreply, state}
    end
  end

  def handle_info({:waiting_for_human, run_id}, state) do
    update_agent(run_id, %{status: :waiting_for_human})
    broadcast_agent_update(run_id, :waiting, get_agent(run_id))
    {:noreply, state}
  end

  def handle_info({:agent_stopped, run_id}, state) do
    update_agent(run_id, %{status: :done, finished_at: System.system_time(:millisecond)})
    broadcast_agent_update(run_id, :stopped, get_agent(run_id))
    {:noreply, state}
  end

  def handle_info({:status_change, run_id, status, extra}, state) do
    update_agent(run_id, Map.put(extra, :status, status))
    broadcast_agent_update(run_id, status, get_agent(run_id))
    {:noreply, state}
  end

  def handle_info({:event, run_id, type, data}, state) do
    seq = state.seq + 1

    event = %{
      seq: seq,
      run_id: run_id,
      type: type,
      timestamp: System.system_time(:millisecond),
      data: data
    }

    if count_events(run_id) < @max_events_per_agent do
      :ets.insert(@events_table, {{run_id, seq}, event})
    end

    broadcast_event(run_id, event)
    {:noreply, %{state | seq: seq}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {run_id, monitors} ->
        case get_agent(run_id) do
          %{status: status} when status in [:done, :error] ->
            :ok

          _ ->
            update_agent(run_id, %{status: :dead, finished_at: System.system_time(:millisecond)})
            broadcast_agent_update(run_id, :dead, get_agent(run_id))
        end

        {:noreply, %{state | monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Telemetry handler attachment

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
        [:legion, :sandbox, :eval, :stop]
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  # Telemetry handler — runs in the calling process, must be fast

  def handle_telemetry([:legion, :agent, :started], _measurements, meta, _config) do
    record = %{
      run_id: meta.run_id,
      parent_run_id: meta[:parent_run_id],
      agent_module: meta.agent,
      pid: self(),
      status: :running,
      started_at: System.system_time(:millisecond),
      finished_at: nil,
      task: nil,
      iterations: 0
    }

    :ets.insert(@agents_table, {meta.run_id, record})
    send(__MODULE__, {:agent_started, meta.run_id, record})
  end

  def handle_telemetry([:legion, :agent, :stopped], _measurements, meta, _config) do
    send(__MODULE__, {:agent_stopped, meta.run_id})
  end

  def handle_telemetry([:legion, :agent, :message, :start], _measurements, meta, _config) do
    task = if is_binary(meta[:message]), do: meta[:message]
    updates = if task, do: %{task: task}, else: %{}
    send(__MODULE__, {:status_change, meta.run_id, :running, updates})
    send(__MODULE__, {:event, meta.run_id, :message_start, meta})
  end

  def handle_telemetry([:legion, :agent, :message, :stop], measurements, meta, _config) do
    send(
      __MODULE__,
      {:status_change, meta.run_id, :idle, %{iterations: meta[:iterations] || 0}}
    )

    send(
      __MODULE__,
      {:event, meta.run_id, :message_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :agent, :message, :exception], measurements, meta, _config) do
    send(__MODULE__, {:status_change, meta.run_id, :error, %{}})

    send(
      __MODULE__,
      {:event, meta.run_id, :message_exception,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :iteration, :start], _measurements, meta, _config) do
    send(__MODULE__, {:event, meta.run_id, :iteration_start, meta})
    forward_to_parent(meta.run_id, :iteration_start, meta)
  end

  def handle_telemetry([:legion, :iteration, :stop], measurements, meta, _config) do
    send(
      __MODULE__,
      {:event, meta.run_id, :iteration_stop,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )

    forward_to_parent(meta.run_id, :iteration_stop, meta)
  end

  def handle_telemetry([:legion, :llm, :request, :start], _measurements, meta, _config) do
    send(__MODULE__, {:event, meta.run_id, :llm_start, meta})
    forward_to_parent(meta.run_id, :llm_start, meta)
  end

  def handle_telemetry([:legion, :llm, :request, :stop], measurements, meta, _config) do
    send(
      __MODULE__,
      {:event, meta.run_id, :llm_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )

    forward_to_parent(meta.run_id, :llm_stop, meta)
  end

  def handle_telemetry([:legion, :sandbox, :eval, :start], _measurements, meta, _config) do
    send(__MODULE__, {:event, meta.run_id, :eval_start, meta})
    forward_to_parent(meta.run_id, :eval_start, meta)
  end

  def handle_telemetry([:legion, :sandbox, :eval, :stop], measurements, meta, _config) do
    send(
      __MODULE__,
      {:event, meta.run_id, :eval_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )

    forward_to_parent(meta.run_id, :eval_stop, meta)
  end

  # Private helpers

  defp update_agent(run_id, updates) do
    case :ets.lookup(@agents_table, run_id) do
      [{^run_id, record}] ->
        :ets.insert(@agents_table, {run_id, Map.merge(record, updates)})

      [] ->
        :ok
    end
  end

  defp count_events(run_id) do
    :ets.select_count(@events_table, [{{{run_id, :_}, :_}, [], [true]}])
  end

  defp evict_if_over_limit do
    count = :ets.info(@agents_table, :size)

    if count > @max_agents do
      @agents_table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(&1.status not in [:running, :waiting_for_human]))
      |> Enum.sort_by(& &1.started_at)
      |> List.first()
      |> case do
        nil -> :ok
        oldest -> delete_agent(oldest.run_id)
      end
    end
  end

  defp delete_agent(run_id) do
    :ets.delete(@agents_table, run_id)
    :ets.select_delete(@events_table, [{{{run_id, :_}, :_}, [], [true]}])
  end

  defp broadcast_agent_update(run_id, event, record) do
    Phoenix.PubSub.broadcast(LegionWeb.PubSub, "legion_web:agents", {event, run_id, record})
  end

  defp broadcast_event(run_id, event) do
    Phoenix.PubSub.broadcast(
      LegionWeb.PubSub,
      "legion_web:agent:#{inspect(run_id)}",
      {:new_event, event}
    )
  end

  defp forward_to_parent(run_id, type, data) do
    case :ets.lookup(@agents_table, run_id) do
      [{^run_id, %{parent_run_id: parent_run_id}}] when not is_nil(parent_run_id) ->
        send(__MODULE__, {:event, parent_run_id, type, data})

      _ ->
        :ok
    end
  end
end
