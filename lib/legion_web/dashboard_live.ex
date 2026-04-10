defmodule LegionWeb.DashboardLive do
  use LegionWeb, :live_view

  alias LegionWeb.{AgentTracker, HumanHandler, TraceReducer}
  alias LegionWeb.Components.{AgentDetail, AgentsList}

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
     |> assign(:trace, TraceReducer.new())
     |> assign(:trace_items, [])
     |> assign(:system_prompt, nil)
     |> assign(:agent_config, %{})
     |> assign(:show_prompt_modal, false)
     |> assign(:chat_form, to_form(%{"text" => ""}, as: :chat))}
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

    trace =
      if run_id do
        run_id
        |> AgentTracker.get_events()
        |> Enum.reduce(TraceReducer.new(), &TraceReducer.push(&2, &1))
      else
        TraceReducer.new()
      end

    system_prompt = agent && render_markdown(agent.agent_module.system_prompt())

    agent_config =
      if agent do
        app_config = Application.get_env(:legion, :config, %{})
        Map.merge(app_config, agent.agent_module.config())
      else
        %{}
      end

    {:noreply,
     socket
     |> assign(:selected_run_id, run_id)
     |> assign(:selected_agent, agent)
     |> assign(:trace, trace)
     |> assign(:trace_items, TraceReducer.items(trace))
     |> assign(:system_prompt, system_prompt)
     |> assign(:agent_config, agent_config)
     |> assign(:chat_form, to_form(%{"text" => ""}, as: :chat))}
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
     |> assign(:trace, TraceReducer.new())
     |> assign(:trace_items, [])
     |> assign(:system_prompt, nil)
     |> assign(:agent_config, %{})}
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
    trace = TraceReducer.push(socket.assigns.trace, event)
    {:noreply, socket |> assign(:trace, trace) |> assign(:trace_items, TraceReducer.items(trace))}
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
  def handle_event("send_message", %{"chat" => %{"text" => text}}, socket) when text != "" do
    %{selected_agent: agent} = socket.assigns

    if agent && agent.pid && Process.alive?(agent.pid) do
      case HumanHandler.respond(agent.run_id, text) do
        :ok ->
          :ok

        :not_found ->
          Legion.cast(agent.pid, text)
      end
    end

    {:noreply, assign(socket, :chat_form, to_form(%{"text" => ""}, as: :chat))}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("show_prompt", _params, socket) do
    {:noreply, assign(socket, :show_prompt_modal, true)}
  end

  def handle_event("close_prompt", _params, socket) do
    {:noreply, assign(socket, :show_prompt_modal, false)}
  end

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
        trace_items={@trace_items}
        system_prompt={@system_prompt}
        show_prompt_modal={@show_prompt_modal}
        agent_config={@agent_config}
        chat_form={@chat_form}
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

  defp render_markdown(text) do
    text
    |> Earmark.as_html!(code_class_prefix: "language-")
    |> highlight_code_blocks()
    |> Phoenix.HTML.raw()
  end

  @code_block_re ~r/<code class="elixir language-elixir">(.*?)<\/code>/s
  defp highlight_code_blocks(html) do
    Regex.replace(@code_block_re, html, fn _match, code ->
      highlighted =
        code
        |> unescape_html()
        |> Makeup.highlight_inner_html(lexer: Makeup.Lexers.ElixirLexer)

      ~s(<code class="language-elixir highlight">#{highlighted}</code>)
    end)
  end

  defp unescape_html(html) do
    html
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  defp maybe_update_selected_agent(socket, run_id, record) do
    if socket.assigns.selected_run_id == run_id do
      assign(socket, :selected_agent, record)
    else
      socket
    end
  end
end
