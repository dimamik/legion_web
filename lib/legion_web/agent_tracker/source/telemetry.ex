defmodule LegionWeb.AgentTracker.Source.Telemetry do
  @moduledoc """
  Telemetry source for tracking agents
  """
  @behaviour LegionWeb.AgentTracker.Source

  @impl true
  def init(_opts) do
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

    send(LegionWeb.AgentTracker, {:agent_started, meta.run_id, record})
  end

  def handle_telemetry([:legion, :agent, :stopped], _measurements, meta, _config) do
    send(LegionWeb.AgentTracker, {:agent_stopped, meta.run_id})
  end

  def handle_telemetry([:legion, :agent, :message, :start], _measurements, meta, _config) do
    task = if is_binary(meta[:message]), do: meta[:message]
    updates = if task, do: %{task: task}, else: %{}
    send(LegionWeb.AgentTracker, {:status_change, meta.run_id, :running, updates})
    send(LegionWeb.AgentTracker, {:event, meta.run_id, :message_start, meta})
  end

  def handle_telemetry([:legion, :agent, :message, :stop], measurements, meta, _config) do
    send(
      LegionWeb.AgentTracker,
      {:status_change, meta.run_id, :idle, %{iterations: meta[:iterations] || 0}}
    )

    send(
      LegionWeb.AgentTracker,
      {:event, meta.run_id, :message_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :agent, :message, :exception], measurements, meta, _config) do
    send(LegionWeb.AgentTracker, {:status_change, meta.run_id, :error, %{}})

    send(
      LegionWeb.AgentTracker,
      {:event, meta.run_id, :message_exception,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )
  end

  def handle_telemetry([:legion, :iteration, :start], _measurements, meta, _config) do
    send(LegionWeb.AgentTracker, {:event, meta.run_id, :iteration_start, meta})
    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :iteration_start, meta})
  end

  def handle_telemetry([:legion, :iteration, :stop], measurements, meta, _config) do
    send(
      LegionWeb.AgentTracker,
      {:event, meta.run_id, :iteration_stop,
       Map.merge(meta, %{duration: measurements[:duration]})}
    )

    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :iteration_stop, meta})
  end

  def handle_telemetry([:legion, :llm, :request, :start], _measurements, meta, _config) do
    send(LegionWeb.AgentTracker, {:event, meta.run_id, :llm_start, meta})
    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :llm_start, meta})
  end

  def handle_telemetry([:legion, :llm, :request, :stop], measurements, meta, _config) do
    send(
      LegionWeb.AgentTracker,
      {:event, meta.run_id, :llm_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )

    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :llm_stop, meta})
  end

  def handle_telemetry([:legion, :sandbox, :eval, :start], _measurements, meta, _config) do
    send(LegionWeb.AgentTracker, {:event, meta.run_id, :eval_start, meta})
    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :eval_start, meta})
  end

  def handle_telemetry([:legion, :sandbox, :eval, :stop], measurements, meta, _config) do
    send(
      LegionWeb.AgentTracker,
      {:event, meta.run_id, :eval_stop, Map.merge(meta, %{duration: measurements[:duration]})}
    )

    send(LegionWeb.AgentTracker, {:forward, meta.run_id, :eval_stop, meta})
  end
end
