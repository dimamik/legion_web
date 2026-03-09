defmodule LegionWeb.DashboardLive do
  use LegionWeb, :live_view

  alias LegionWeb.{AgentTracker, HumanHandler}
  alias LegionWeb.Components.{AgentsList, AgentDetail}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")
    end

    {:ok,
     socket
     |> assign(:prefix, session["prefix"])
     |> assign(:live_path, session["live_path"])
     |> assign(:live_transport, session["live_transport"])
     |> assign(:csp_nonces, session["csp_nonces"])
     |> assign(:agents, AgentTracker.list_agents())
     |> assign(:selected_run_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:events, [])
     |> assign(:chat_pending, false)}
  end

  @impl true
  def handle_params(%{"run_id" => encoded_run_id}, _uri, socket) do
    run_id = decode_run_id(encoded_run_id)

    if connected?(socket) do
      if prev = socket.assigns.selected_run_id do
        Phoenix.PubSub.unsubscribe(LegionWeb.PubSub, agent_topic(prev))
      end

      if run_id do
        Phoenix.PubSub.subscribe(LegionWeb.PubSub, agent_topic(run_id))
      end
    end

    agent = run_id && AgentTracker.get_agent(run_id)
    events = if run_id, do: AgentTracker.get_events(run_id), else: []

    {:noreply,
     socket
     |> assign(:selected_run_id, run_id)
     |> assign(:selected_agent, agent)
     |> assign(:events, events)
     |> assign(:chat_pending, false)}
  end

  def handle_params(_params, _uri, socket) do
    if connected?(socket) do
      if prev = socket.assigns.selected_run_id do
        Phoenix.PubSub.unsubscribe(LegionWeb.PubSub, agent_topic(prev))
      end
    end

    {:noreply,
     socket
     |> assign(:selected_run_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:events, [])}
  end

  # Agent list updates
  @impl true
  def handle_info({event, run_id, record}, socket)
      when event in [:started, :stopped, :running, :idle, :done, :error, :waiting, :dead] do
    agents = update_agents_list(socket.assigns.agents, run_id, record)

    socket =
      socket
      |> assign(:agents, agents)
      |> maybe_update_selected_agent(run_id, record)

    {:noreply, socket}
  end

  # New event for selected agent
  def handle_info({:new_event, event}, socket) do
    {:noreply, assign(socket, :events, socket.assigns.events ++ [event])}
  end

  # Human tool integration
  def handle_info({:human_request, question}, socket) do
    {:noreply, assign(socket, :human_question, question)}
  end

  def handle_info({:human_responded, _text}, socket) do
    {:noreply, assign(socket, :human_question, nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("send_message", %{"text" => text}, socket) when text != "" do
    %{selected_agent: agent} = socket.assigns

    if agent && agent.pid do
      case agent.status do
        :waiting_for_human ->
          HumanHandler.respond(agent.run_id, text)

        status when status in [:idle, :done] ->
          if Process.alive?(agent.pid), do: Legion.cast(agent.pid, text)

        _ ->
          :ok
      end
    end

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-sol-base3">
      <AgentsList.render
        agents={@agents}
        selected_run_id={@selected_run_id}
        prefix={@prefix}
      />
      <AgentDetail.render
        agent={@selected_agent}
        events={@events}
        chat_pending={@chat_pending}
        prefix={@prefix}
      />
    </div>
    """
  end

  # Private helpers

  defp update_agents_list(agents, run_id, record) do
    idx = Enum.find_index(agents, &(&1.run_id == run_id))

    if idx do
      List.replace_at(agents, idx, record)
    else
      [record | agents]
    end
    |> Enum.sort_by(& &1.started_at, :desc)
  end

  defp maybe_update_selected_agent(socket, run_id, record) do
    if socket.assigns.selected_run_id == run_id do
      assign(socket, :selected_agent, record)
    else
      socket
    end
  end
end
