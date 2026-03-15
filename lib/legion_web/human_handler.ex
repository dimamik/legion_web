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

  def respond(run_id, text) do
    GenServer.call(__MODULE__, {:respond, run_id, text})
  end

  @impl true
  def init(_opts), do: {:ok, %{pending: %{}}}

  @impl true
  def handle_info({:human_request, ref, from_pid, question, meta}, state) do
    run_id = meta[:run_id]

    state = put_in(state.pending[run_id], {ref, from_pid})

    send(LegionWeb.AgentTracker, {:waiting_for_human, run_id})

    Phoenix.PubSub.broadcast(
      LegionWeb.PubSub,
      "legion_web:agent:#{inspect(run_id)}",
      {:human_request, question}
    )

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:respond, run_id, text}, _from, state) do
    case Map.pop(state.pending, run_id) do
      {nil, _} ->
        {:reply, :not_found, state}

      {{ref, from_pid}, pending} ->
        send(from_pid, {:human_response, ref, text})
        send(LegionWeb.AgentTracker, {:event, run_id, :human_response, %{text: text}})
        send(LegionWeb.AgentTracker, {:status_change, run_id, :running, %{}})

        Phoenix.PubSub.broadcast(
          LegionWeb.PubSub,
          "legion_web:agent:#{inspect(run_id)}",
          {:human_responded, text}
        )

        {:reply, :ok, %{state | pending: pending}}
    end
  end
end
