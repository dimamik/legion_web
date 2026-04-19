defmodule LegionWeb.DashboardLiveTest do
  use ExUnit.Case, async: false

  alias LegionWeb.{DashboardLive, TraceReducer}
  alias Phoenix.LiveView.Socket

  defmodule FakeTool do
    def name, do: :fake
  end

  defmodule OtherTool do
    def name, do: :other
  end

  defmodule FakeAgent do
    def system_prompt, do: "# Agent\n\nhello"
    def tools, do: [FakeTool, OtherTool]
    def tool_config(FakeTool), do: [timeout: 5_000]
    def tool_config(OtherTool), do: [retries: 3]
    def config, do: %{max_iterations: 7}
  end

  setup do
    :ets.delete_all_objects(:legion_web_agents)
    :ets.delete_all_objects(:legion_web_events)
    Process.delete(:"$vault")
    Application.delete_env(:legion, :config)
    :ok
  end

  defp agent_record(run_id, overrides \\ %{}) do
    Map.merge(
      %{
        run_id: run_id,
        parent_run_id: nil,
        agent_module: FakeAgent,
        pid: nil,
        status: :running,
        started_at: System.system_time(:millisecond),
        finished_at: nil,
        task: nil,
        iterations: 0
      },
      overrides
    )
  end

  defp empty_socket, do: %Socket{assigns: %{__changed__: %{}, flash: %{}}}

  defp mounted_socket(extra \\ %{}) do
    {:ok, socket} = DashboardLive.mount(%{}, %{}, empty_socket())
    %{socket | assigns: Map.merge(socket.assigns, extra)}
  end

  describe "mount/3" do
    test "initializes empty state from session" do
      session = %{
        "prefix" => "/dashboard",
        "live_path" => "/live",
        "live_transport" => "longpoll",
        "csp_nonces" => %{img: "i", style: "s", script: "sc"}
      }

      {:ok, socket} = DashboardLive.mount(%{}, session, empty_socket())

      assert socket.assigns.prefix == "/dashboard"
      assert socket.assigns.live_path == "/live"
      assert socket.assigns.live_transport == "longpoll"
      assert socket.assigns.csp_nonces == %{img: "i", style: "s", script: "sc"}
      assert socket.assigns.agents == []
      assert socket.assigns.selected_run_id == nil
      assert socket.assigns.selected_agent == nil
      assert %TraceReducer{} = socket.assigns.trace
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
      assert socket.assigns.agent_config == %{}
      assert socket.assigns.show_prompt_modal == false
    end

    test "includes agents already tracked" do
      :ets.insert(:legion_web_agents, {:run1, agent_record(:run1, %{started_at: 100})})
      :ets.insert(:legion_web_agents, {:run2, agent_record(:run2, %{started_at: 200})})

      {:ok, socket} = DashboardLive.mount(%{}, %{}, empty_socket())

      assert [%{run_id: :run2}, %{run_id: :run1}] = socket.assigns.agents
    end
  end

  describe "handle_params/3 without a run_id" do
    test "clears selected agent state" do
      socket =
        mounted_socket(%{
          selected_run_id: :old,
          selected_agent: agent_record(:old),
          trace_items: [{:message, %{text: "x"}}],
          system_prompt: "some prompt",
          agent_config: %{foo: :bar}
        })

      {:noreply, socket} = DashboardLive.handle_params(%{}, "/legion", socket)

      assert socket.assigns.selected_run_id == nil
      assert socket.assigns.selected_agent == nil
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
      assert socket.assigns.agent_config == %{}
    end
  end

  describe "handle_params/3 with a run_id" do
    test "loads agent, replays events, and populates system_prompt/config" do
      run_id = :demo
      :ets.insert(:legion_web_agents, {run_id, agent_record(run_id)})

      :ets.insert(
        :legion_web_events,
        {{run_id, 1},
         %{
           seq: 1,
           run_id: run_id,
           type: :message_start,
           timestamp: 1,
           data: %{run_id: run_id, message: "hello"}
         }}
      )

      Application.put_env(:legion, :config, %{env: :test})

      encoded = LegionWeb.Helpers.encode_run_id(run_id)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"run_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.selected_run_id == run_id
      assert socket.assigns.selected_agent.run_id == run_id
      assert [{:message, %{text: "hello"}}] = socket.assigns.trace_items
      assert socket.assigns.agent_config == %{env: :test, max_iterations: 7}
      assert socket.assigns.system_prompt != nil
    end

    test "populates Vault with every tool's config before rendering the prompt" do
      run_id = :vault_demo
      :ets.insert(:legion_web_agents, {run_id, agent_record(run_id)})

      encoded = LegionWeb.Helpers.encode_run_id(run_id)

      {:noreply, _socket} =
        DashboardLive.handle_params(%{"run_id" => encoded}, "/legion", mounted_socket())

      assert Vault.get(FakeTool) == [timeout: 5_000]
      assert Vault.get(OtherTool) == [retries: 3]
    end

    test "clears state when run_id is unknown" do
      encoded = LegionWeb.Helpers.encode_run_id(:missing)

      {:noreply, socket} =
        DashboardLive.handle_params(%{"run_id" => encoded}, "/legion", mounted_socket())

      assert socket.assigns.selected_run_id == :missing
      assert socket.assigns.selected_agent == nil
      assert socket.assigns.trace_items == []
      assert socket.assigns.system_prompt == nil
    end

    test "treats an invalid encoded run_id as nil" do
      {:noreply, socket} =
        DashboardLive.handle_params(%{"run_id" => "not-base64"}, "/legion", mounted_socket())

      assert socket.assigns.selected_run_id == nil
      assert socket.assigns.selected_agent == nil
    end
  end

  describe "handle_info/2 - agent lifecycle" do
    test "adds a new agent on :started" do
      record = agent_record(:run1, %{started_at: 100})
      {:noreply, socket} = DashboardLive.handle_info({:started, :run1, record}, mounted_socket())
      assert [%{run_id: :run1}] = socket.assigns.agents
    end

    test "replaces existing agent with same run_id" do
      existing = agent_record(:run1, %{started_at: 100, status: :running})
      socket = mounted_socket(%{agents: [existing]})

      updated = %{existing | status: :done}
      {:noreply, socket} = DashboardLive.handle_info({:stopped, :run1, updated}, socket)

      assert [%{run_id: :run1, status: :done}] = socket.assigns.agents
    end

    test "sorts the list by started_at descending" do
      old = agent_record(:old, %{started_at: 100})
      new = agent_record(:new, %{started_at: 500})
      socket = mounted_socket(%{agents: [old]})

      {:noreply, socket} = DashboardLive.handle_info({:started, :new, new}, socket)

      assert [%{run_id: :new}, %{run_id: :old}] = socket.assigns.agents
    end

    test "updates selected_agent when the broadcast matches the current selection" do
      record = agent_record(:run1, %{status: :running})

      socket =
        mounted_socket(%{
          selected_run_id: :run1,
          selected_agent: record,
          agents: [record]
        })

      updated = %{record | status: :done}
      {:noreply, socket} = DashboardLive.handle_info({:stopped, :run1, updated}, socket)

      assert socket.assigns.selected_agent.status == :done
    end

    test "leaves selected_agent untouched for a different run_id" do
      selected = agent_record(:run1)
      other = agent_record(:run2)

      socket =
        mounted_socket(%{
          selected_run_id: :run1,
          selected_agent: selected,
          agents: [selected]
        })

      {:noreply, socket} = DashboardLive.handle_info({:started, :run2, other}, socket)

      assert socket.assigns.selected_agent.run_id == :run1
    end
  end

  describe "handle_info/2 - trace events" do
    test ":new_event pushes through the reducer and updates trace_items" do
      event = %{
        seq: 1,
        run_id: :main,
        type: :message_start,
        timestamp: 1,
        data: %{run_id: :main, message: "hi"}
      }

      {:noreply, socket} = DashboardLive.handle_info({:new_event, event}, mounted_socket())

      assert [{:message, %{text: "hi"}}] = socket.assigns.trace_items
    end
  end

  describe "handle_info/2 - human tool messages" do
    test ":human_request sets :human_question" do
      {:noreply, socket} =
        DashboardLive.handle_info({:human_request, "sure?"}, mounted_socket())

      assert socket.assigns.human_question == "sure?"
    end

    test ":human_responded clears :human_question" do
      socket = mounted_socket(%{human_question: "old"})
      {:noreply, socket} = DashboardLive.handle_info({:human_responded, "yes"}, socket)
      assert socket.assigns.human_question == nil
    end

    test "unrecognized messages are ignored" do
      socket = mounted_socket()
      assert {:noreply, ^socket} = DashboardLive.handle_info(:anything, socket)
    end
  end

  describe "handle_event/3 - prompt modal" do
    test "show_prompt opens the modal" do
      {:noreply, socket} = DashboardLive.handle_event("show_prompt", %{}, mounted_socket())
      assert socket.assigns.show_prompt_modal == true
    end

    test "close_prompt closes the modal" do
      socket = mounted_socket(%{show_prompt_modal: true})
      {:noreply, socket} = DashboardLive.handle_event("close_prompt", %{}, socket)
      assert socket.assigns.show_prompt_modal == false
    end
  end

  describe "handle_event/3 - send_message" do
    test "empty text is a no-op" do
      socket = mounted_socket()

      assert {:noreply, ^socket} =
               DashboardLive.handle_event("send_message", %{"chat" => %{"text" => ""}}, socket)
    end

    test "missing chat params is a no-op" do
      socket = mounted_socket()
      assert {:noreply, ^socket} = DashboardLive.handle_event("send_message", %{}, socket)
    end

    test "resets the chat form when no agent is selected" do
      socket = mounted_socket(%{selected_agent: nil})

      {:noreply, socket} =
        DashboardLive.handle_event("send_message", %{"chat" => %{"text" => "hi"}}, socket)

      assert %Phoenix.HTML.Form{} = socket.assigns.chat_form
      assert socket.assigns.chat_form.params == %{"text" => ""}
    end

    test "resets the chat form when the selected agent has a dead pid" do
      agent = agent_record(:run1, %{pid: spawn(fn -> :ok end)})
      Process.sleep(5)
      refute Process.alive?(agent.pid)

      socket = mounted_socket(%{selected_agent: agent})

      {:noreply, socket} =
        DashboardLive.handle_event("send_message", %{"chat" => %{"text" => "hi"}}, socket)

      assert socket.assigns.chat_form.params == %{"text" => ""}
    end
  end

  describe "AgentTracker integration" do
    test "mount reflects tracker state and handle_params loads agent by run_id" do
      :ets.insert(:legion_web_agents, {:x, agent_record(:x, %{started_at: 42})})

      {:ok, socket} = DashboardLive.mount(%{}, %{}, empty_socket())
      assert Enum.any?(socket.assigns.agents, &(&1.run_id == :x))

      encoded = LegionWeb.Helpers.encode_run_id(:x)
      {:noreply, socket} = DashboardLive.handle_params(%{"run_id" => encoded}, "/legion", socket)

      assert socket.assigns.selected_agent.run_id == :x
    end
  end
end
