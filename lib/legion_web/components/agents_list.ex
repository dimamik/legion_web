defmodule LegionWeb.Components.AgentsList do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.Helpers

  attr :agents, :list, required: true
  attr :selected_run_id, :any, default: nil
  attr :prefix, :string, required: true

  def render(assigns) do
    agents_by_parent = Enum.group_by(assigns.agents, &Map.get(&1, :parent_run_id, nil))
    root_agents = Map.get(agents_by_parent, nil, [])

    assigns =
      assigns
      |> assign(:root_agents, root_agents)
      |> assign(:agents_by_parent, agents_by_parent)

    ~H"""
    <aside class="w-80 shrink-0 border-r border-sol-base2 flex flex-col overflow-hidden bg-sol-base2">
      <div class="px-5 py-4 border-b border-sol-base1/30">
        <div class="flex items-center gap-2.5">
          <div class="w-2 h-2 rounded-full bg-sol-violet soft-pulse"></div>
          <h1 class="text-xs font-semibold text-sol-base01 uppercase tracking-[0.15em]">
            Legion
          </h1>
          <span class="ml-auto text-[10px] text-sol-base00 tabular-nums">
            {length(@agents)} agent(s)
          </span>
        </div>
      </div>
      <div class="flex-1 overflow-y-auto">
        <div :if={@agents == []} class="px-5 py-10 text-center">
          <p class="text-sol-base1 text-sm">No agents yet</p>
          <p class="text-sol-base1/70 text-xs mt-1">Agents will appear here when started</p>
        </div>
        <ul class="py-1">
          <.agent_tree_node
            :for={agent <- @root_agents}
            agent={agent}
            agents_by_parent={@agents_by_parent}
            selected_run_id={@selected_run_id}
            prefix={@prefix}
            depth={0}
          />
        </ul>
      </div>
    </aside>
    """
  end

  attr :agent, :map, required: true
  attr :agents_by_parent, :map, required: true
  attr :selected_run_id, :any, required: true
  attr :prefix, :string, required: true
  attr :depth, :integer, required: true

  def agent_tree_node(assigns) do
    children = Map.get(assigns.agents_by_parent, assigns.agent.run_id, [])
    is_subagent = assigns.agent.parent_run_id != nil
    selected = assigns.selected_run_id == assigns.agent.run_id

    assigns =
      assigns
      |> assign(:children, children)
      |> assign(:is_subagent, is_subagent)
      |> assign(:selected, selected)

    ~H"""
    <li>
      <.link
        patch={"#{@prefix}/#{Helpers.encode_run_id(@agent.run_id)}"}
        class={[
          "block py-3 cursor-pointer transition-all duration-150 border-l-2",
          @selected && "bg-sol-base3 border-l-sol-violet",
          !@selected && "border-l-transparent hover:bg-sol-base3/60"
        ]}
        style={"padding-left: #{max(1.0, @depth * 1.25 + 1.0)}rem; padding-right: 1rem;"}
      >
        <div class="flex items-center gap-2.5 mb-1">
          <span class={["w-2 h-2 rounded-full shrink-0", Helpers.status_class(@agent.status)]}></span>
          <span :if={@is_subagent} class="text-sol-violet/60 text-xs shrink-0">&#8627;</span>
          <span class={[
            "text-sm font-medium truncate",
            if(@selected, do: "text-sol-base02", else: "text-sol-base01")
          ]}>
            {Helpers.module_name(@agent.agent_module)}
          </span>
          <span class={[
            "ml-auto text-[10px] font-medium shrink-0 uppercase tracking-wider",
            Helpers.status_text_class(@agent.status)
          ]}>
            {Helpers.status_label(@agent.status)}
          </span>
        </div>
        <p
          :if={@agent.task}
          class={[
            "text-xs truncate text-sol-base00",
            if(@is_subagent, do: "pl-7", else: "pl-4.5")
          ]}
        >
          {Helpers.truncate(@agent.task, 55)}
        </p>
        <div class={[
          "flex gap-3 mt-1 text-[10px] text-sol-base00",
          if(@is_subagent, do: "pl-7", else: "pl-4.5")
        ]}>
          <span>{Helpers.relative_time(@agent.started_at)}</span>
          <span :if={duration = Helpers.format_duration(@agent.started_at, @agent[:finished_at])}>
            {duration}
          </span>
          <span :if={@agent.iterations > 0}>iter {@agent.iterations}</span>
        </div>
      </.link>
      <ul :if={@children != []}>
        <.agent_tree_node
          :for={child <- @children}
          agent={child}
          agents_by_parent={@agents_by_parent}
          selected_run_id={@selected_run_id}
          prefix={@prefix}
          depth={@depth + 1}
        />
      </ul>
    </li>
    """
  end
end
