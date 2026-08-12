defmodule LegionWeb.AgentTrackerTest do
  use ExUnit.Case

  alias LegionWeb.AgentTracker
  alias LegionWeb.AgentTracker.LegionAgent
  alias LegionWeb.AgentTracker.Telemetry

  setup do
    # Clear ETS tables before each test
    :ets.delete_all_objects(:legion_web_agents)
    :ets.delete_all_objects(:legion_web_events)

    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")

    :ok
  end

  test "defines the tracker query behaviour" do
    assert AgentTracker.behaviour_info(:callbacks) |> Enum.sort() ==
             [get_agent: 1, get_events: 1, list_agents: 0]
  end

  defp insert_agent(agent_id, attrs \\ %{}) do
    record =
      Map.merge(
        %LegionAgent{
          agent_id: agent_id,
          parent_agent_id: nil,
          agent_module: TestAgent,
          pid: self(),
          status: :running,
          started_at: System.system_time(:millisecond),
          finished_at: nil,
          task: nil,
          iterations: 0
        },
        attrs
      )

    :ets.insert(:legion_web_agents, {agent_id, record})
    record
  end

  describe "list_agents/0" do
    test "returns empty list when no agents" do
      assert Telemetry.list_agents() == []
    end

    test "returns agents sorted by started_at desc" do
      insert_agent("old", %{started_at: 1000})
      insert_agent("new", %{started_at: 2000})

      agents = Telemetry.list_agents()
      assert length(agents) == 2
      assert hd(agents).agent_id == "new"
    end
  end

  describe "get_agent/1" do
    test "returns agent record" do
      insert_agent("agent1")
      agent = Telemetry.get_agent("agent1")
      assert agent.agent_id == "agent1"
      assert agent.status == :running
    end

    test "returns nil for missing agent" do
      assert Telemetry.get_agent("nonexistent") == nil
    end
  end

  describe "get_events/1" do
    test "returns empty list when no events" do
      assert Telemetry.get_events("no_events") == []
    end

    test "returns events in order" do
      e1 = %{seq: 1, type: :llm_start, data: %{}}
      e2 = %{seq: 2, type: :llm_stop, data: %{}}

      :ets.insert(:legion_web_events, {{"agent1", 1}, e1})
      :ets.insert(:legion_web_events, {{"agent1", 2}, e2})

      events = Telemetry.get_events("agent1")
      assert length(events) == 2
      assert hd(events).seq == 1
    end

    test "only returns events for the given agent_id" do
      :ets.insert(:legion_web_events, {{"agent1", 1}, %{seq: 1}})
      :ets.insert(:legion_web_events, {{"agent2", 1}, %{seq: 1}})

      assert length(Telemetry.get_events("agent1")) == 1
    end
  end

  describe "handle_info :agent_started" do
    test "publishes canonical agent and event structs" do
      record = insert_agent("typed")

      assert %{__struct__: LegionWeb.AgentTracker.LegionAgent} = record

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect("typed")}")
      send(Telemetry, {:event, "typed", :llm_start, %{model: "gpt-4"}})

      assert_receive {:new_event, %{__struct__: LegionWeb.AgentTracker.LegionEvent}}
    end

    test "broadcasts agent started" do
      record = %LegionAgent{
        agent_id: "new_agent",
        parent_agent_id: nil,
        agent_module: TestAgent,
        pid: nil,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {"new_agent", record})

      send(Telemetry, {:agent_started, "new_agent", record})

      assert_receive {:started, "new_agent", ^record}, 1000
    end
  end

  describe "handle_info :agent_stopped" do
    test "updates agent status to done and broadcasts" do
      insert_agent("stopping")

      send(Telemetry, {:agent_stopped, "stopping"})

      assert_receive {:stopped, "stopping", record}, 1000
      assert record.status == :done
      assert record.finished_at != nil
    end
  end

  describe "handle_info :status_change" do
    test "updates agent status and broadcasts" do
      insert_agent("changing")

      send(Telemetry, {:status_change, "changing", :idle, %{iterations: 3}})

      assert_receive {:idle, "changing", record}, 1000
      assert record.status == :idle
      assert record.iterations == 3
    end
  end

  describe "handle_info :event" do
    test "stores event in ETS and broadcasts" do
      insert_agent("evented")

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect("evented")}")

      send(Telemetry, {:event, "evented", :llm_start, %{model: "gpt-4"}})

      assert_receive {:new_event, event}, 1000
      assert event.type == :llm_start
      assert event.agent_id == "evented"
      assert event.data.model == "gpt-4"

      events = Telemetry.get_events("evented")
      assert length(events) == 1
    end
  end

  describe "handle_info :waiting_for_human" do
    test "updates status and broadcasts" do
      insert_agent("waiting")

      send(Telemetry, {:waiting_for_human, "waiting"})

      assert_receive {:waiting, "waiting", record}, 1000
      assert record.status == :waiting_for_human
    end
  end

  describe "process monitoring" do
    test "marks agent as dead when monitored process dies unexpectedly" do
      # Start a process that we can kill
      pid = spawn(fn -> Process.sleep(:infinity) end)

      record = %LegionAgent{
        agent_id: "monitored",
        parent_agent_id: nil,
        agent_module: TestAgent,
        pid: pid,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {"monitored", record})
      send(Telemetry, {:agent_started, "monitored", record})

      # Wait for the monitor to be set up
      assert_receive {:started, "monitored", _}, 1000

      # Kill the process
      Process.exit(pid, :kill)

      assert_receive {:dead, "monitored", dead_record}, 1000
      assert dead_record.status == :dead
      assert dead_record.finished_at != nil
    end

    test "does not mark agent as dead if already done" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      record = %LegionAgent{
        agent_id: "already_done",
        parent_agent_id: nil,
        agent_module: TestAgent,
        pid: pid,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {"already_done", record})
      send(Telemetry, {:agent_started, "already_done", record})
      assert_receive {:started, "already_done", _}, 1000

      # Mark as done before killing
      :ets.insert(:legion_web_agents, {"already_done", %{record | status: :done}})

      Process.exit(pid, :kill)

      refute_receive {:dead, "already_done", _}, 200
    end
  end

  describe "event limit" do
    test "does not store events beyond max_events_per_agent limit" do
      insert_agent("limited")

      # Insert 500 events (the max)
      for seq <- 1..500 do
        :ets.insert(:legion_web_events, {{"limited", seq}, %{seq: seq}})
      end

      # Send one more event - it should still broadcast but not store
      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect("limited")}")
      send(Telemetry, {:event, "limited", :llm_start, %{}})

      assert_receive {:new_event, _}, 1000
      assert length(Telemetry.get_events("limited")) == 500
    end
  end

  describe "forward_to_parent" do
    test "forwards events to parent agent topic" do
      insert_agent("parent")
      insert_agent("child", %{parent_agent_id: "parent"})

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect("parent")}")

      Telemetry.handle_telemetry(
        [:legion, :llm, :request, :stop],
        %{duration: 100},
        %{agent_id: "child", object: %{"action" => "return"}},
        nil
      )

      # Should receive the forwarded event on parent topic
      assert_receive {:new_event, event}, 1000
      assert event.type == :llm_stop
    end
  end

  describe "human activity telemetry" do
    test "marks an agent waiting and running around a human response" do
      insert_agent("waiting")

      Telemetry.handle_telemetry(
        [:legion_web, :agent, :waiting_for_human],
        %{},
        %{agent_id: "waiting"},
        nil
      )

      assert_receive {:waiting, "waiting", %{status: :waiting_for_human}}, 1000

      Telemetry.handle_telemetry(
        [:legion_web, :agent, :human_response],
        %{},
        %{agent_id: "waiting", text: "answer"},
        nil
      )

      assert_receive {:running, "waiting", %{status: :running}}, 1000
      assert [%{type: :human_response, data: %{text: "answer"}}] = Telemetry.get_events("waiting")
    end
  end
end
