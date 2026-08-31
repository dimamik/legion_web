defmodule LegionWeb.HumanHandler do
  @moduledoc """
  Built-in HumanTool handler for the Legion dashboard.

  Receives `{:human_request, ref, from_pid, question, meta}` from HumanTool,
  broadcasts the question to the dashboard via PubSub, and waits for the user
  to respond through the UI.

  ## Usage

  Configure your agent to use this handler:

      def tool_config(Legion.Tools.HumanTool) do
        [handler: LegionWeb.HumanHandler]
      end
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def respond(agent_id, text) do
    GenServer.call(__MODULE__, {:respond, agent_id, text})
  end

  @impl true
  def init(_opts), do: {:ok, %{pending: %{}}}

  @impl true
  def handle_info({:human_request, ref, from_pid, question, meta}, state) do
    agent_id = meta[:agent_id]

    # Monitor the asker so a request whose eval timed out or crashed does not
    # linger in pending forever. A repeat request from the same agent replaces
    # the previous one - HumanTool blocks the agent, so the old asker is gone.
    case state.pending[agent_id] do
      {_ref, _from_pid, monitor_ref} -> Process.demonitor(monitor_ref, [:flush])
      nil -> :ok
    end

    monitor_ref = Process.monitor(from_pid)
    state = put_in(state.pending[agent_id], {ref, from_pid, monitor_ref})

    :telemetry.execute(
      [:legion_web, :agent, :waiting_for_human],
      %{},
      %{agent_id: agent_id}
    )

    Phoenix.PubSub.broadcast(
      LegionWeb.PubSub,
      "legion_web:agent:#{inspect(agent_id)}",
      {:human_request, question}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    pending =
      state.pending
      |> Enum.reject(fn {_agent_id, {_ref, _from_pid, pending_monitor_ref}} ->
        pending_monitor_ref == monitor_ref
      end)
      |> Map.new()

    {:noreply, %{state | pending: pending}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:respond, agent_id, text}, _from, state) do
    case Map.pop(state.pending, agent_id) do
      {nil, _} ->
        {:reply, :not_found, state}

      {{ref, from_pid, monitor_ref}, pending} ->
        Process.demonitor(monitor_ref, [:flush])
        send(from_pid, {:human_response, ref, text})

        :telemetry.execute(
          [:legion_web, :agent, :human_response],
          %{},
          %{agent_id: agent_id, text: text}
        )

        Phoenix.PubSub.broadcast(
          LegionWeb.PubSub,
          "legion_web:agent:#{inspect(agent_id)}",
          {:human_responded, text}
        )

        {:reply, :ok, %{state | pending: pending}}
    end
  end
end
