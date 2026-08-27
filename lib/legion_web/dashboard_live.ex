defmodule LegionWeb.DashboardLive do
  use LegionWeb, :live_view

  alias LegionWeb.Components.{AgentDetail, AgentsList}
  alias LegionWeb.{HumanHandler, TraceReducer}

  @page_size 20

  def page_size, do: @page_size

  @impl true
  def mount(_params, session, socket) do
    agent_tracker = session["agent_tracker"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")
    end

    {:ok,
     socket
     |> assign(:usage, [])
     |> assign(:show_usage_modal, false)
     |> assign(:prefix, session["prefix"])
     |> assign(:live_path, session["live_path"])
     |> assign(:live_transport, session["live_transport"])
     |> assign(:csp_nonces, session["csp_nonces"])
     |> assign(:agent_tracker, agent_tracker)
     |> assign(:agents, agent_tracker.list_agents(@page_size))
     |> assign(:list_limit, @page_size)
     |> assign(:selected_agent_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:trace, TraceReducer.new())
     |> assign(:trace_items, [])
     |> assign(:system_prompt, nil)
     |> assign(:agent_config, %{})
     |> assign(:show_prompt_modal, false)
     |> assign(:chat_form, to_form(%{"text" => ""}, as: :chat))}
  end

  @impl true
  def handle_params(%{"agent_id" => encoded_agent_id}, _uri, socket) do
    # A bookmarked URL can reference an agent no longer available from the
    # configured tracker. Treat "decodes but not tracked" as no selection.
    # Treat "decodes but not tracked" as no selection rather than rendering a
    # dangling selected agent (which leaves the list patched into a broken state).
    agent_tracker = socket.assigns.agent_tracker

    decoded_agent_id = decode_agent_id(encoded_agent_id)
    agent = decoded_agent_id && agent_tracker.get_agent(decoded_agent_id)
    agent_id = agent && decoded_agent_id

    socket = update_agent_subscription(socket, agent_id)

    trace =
      if agent_id do
        agent_id
        |> agent_tracker.get_events()
        |> Enum.reduce(TraceReducer.new(), &TraceReducer.push(&2, &1))
      else
        TraceReducer.new()
      end

    agent_config =
      if agent do
        app_config = Application.get_env(:legion, :config, %{})
        Map.merge(app_config, agent.agent_module.config())
      else
        %{}
      end

    system_prompt =
      agent && render_markdown(render_system_prompt(agent.agent_module, agent_config))

    usage = if agent_id, do: agent_tracker.get_usage(agent_id), else: []

    {:noreply,
     socket
     |> assign(:usage, usage)
     |> assign(:show_usage_modal, false)
     |> assign(:show_prompt_modal, false)
     |> assign(:selected_agent_id, agent_id)
     |> assign(:selected_agent, agent)
     |> assign(:trace, trace)
     |> assign(:trace_items, TraceReducer.items(trace))
     |> assign(:system_prompt, system_prompt)
     |> assign(:agent_config, agent_config)
     |> assign(:chat_form, to_form(%{"text" => ""}, as: :chat))}
  end

  def handle_params(_params, _uri, socket) do
    socket = update_agent_subscription(socket, nil)

    {:noreply,
     socket
     |> assign(:usage, [])
     |> assign(:show_usage_modal, false)
     |> assign(:show_prompt_modal, false)
     |> assign(:selected_agent_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:trace, TraceReducer.new())
     |> assign(:trace_items, [])
     |> assign(:system_prompt, nil)
     |> assign(:agent_config, %{})}
  end

  # Agent list updates
  @impl true
  def handle_info({event, agent_id, record}, socket)
      when event in [:started, :stopped, :running, :idle, :done, :error, :waiting, :dead] and
             not is_nil(agent_id) do
    agents = update_agents_list(socket.assigns.agents, agent_id, record)

    socket =
      socket
      |> assign(:agents, agents)
      |> maybe_update_selected_agent(agent_id, record)

    {:noreply, socket}
  end

  # Usage for the selected agent. Snapshots are append-only, so one shorter
  # than what we hold was broadcast before handle_params refetched and is
  # stale; dropping it keeps the panel from rewinding.
  def handle_info({:usage, agent_id, usage}, socket) do
    %{selected_agent_id: selected, usage: current} = socket.assigns

    if agent_id == selected and length(usage) >= length(current) do
      {:noreply, assign(socket, :usage, usage)}
    else
      {:noreply, socket}
    end
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
      case HumanHandler.respond(agent.agent_id, text) do
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

  def handle_event("show_usage", _params, socket) do
    {:noreply, assign(socket, :show_usage_modal, true)}
  end

  def handle_event("close_usage", _params, socket) do
    {:noreply, assign(socket, :show_usage_modal, false)}
  end

  def handle_event("load_more", _params, socket) do
    list_limit = socket.assigns.list_limit + @page_size

    {:noreply,
     socket
     |> assign(:list_limit, list_limit)
     |> assign(:agents, socket.assigns.agent_tracker.list_agents(list_limit))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-sol-base3">
      <AgentsList.render
        agents={@agents}
        selected_agent_id={@selected_agent_id}
        prefix={@prefix}
        has_more={length(@agents) >= @list_limit}
      />
      <AgentDetail.render
        agent={@selected_agent}
        trace_items={@trace_items}
        system_prompt={@system_prompt}
        show_prompt_modal={@show_prompt_modal}
        agent_config={@agent_config}
        chat_form={@chat_form}
        prefix={@prefix}
        usage={@usage}
        show_usage_modal={@show_usage_modal}
      />
    </div>
    """
  end

  # Private helpers

  defp update_agent_subscription(socket, agent_id) do
    if connected?(socket) do
      if prev = socket.assigns.selected_agent_id do
        Phoenix.PubSub.unsubscribe(LegionWeb.PubSub, agent_topic(prev))
      end

      if agent_id do
        Phoenix.PubSub.subscribe(LegionWeb.PubSub, agent_topic(agent_id))
      end
    end

    socket
  end

  defp update_agents_list(agents, agent_id, record) do
    idx = Enum.find_index(agents, &(&1.agent_id == agent_id))

    if idx do
      List.replace_at(agents, idx, record)
    else
      [record | agents]
    end
    |> Enum.sort_by(& &1.started_at, :desc)
  end

  defp render_system_prompt(agent_module, config) do
    # This is a LiveView process, so we can safely
    # put things there.
    # Later on - we should consider global per-tool
    # registry for these things.
    for tool <- agent_module.tools() do
      Vault.unsafe_put(tool, agent_module.tool_config(tool))
    end

    Legion.AgentPrompt.system_prompt(agent_module, config)
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

  defp maybe_update_selected_agent(socket, agent_id, record) do
    if socket.assigns.selected_agent_id == agent_id do
      assign(socket, :selected_agent, record)
    else
      socket
    end
  end
end
