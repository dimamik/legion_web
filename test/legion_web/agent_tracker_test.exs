defmodule LegionWeb.AgentTrackerTest do
  use ExUnit.Case

  alias LegionWeb.AgentTracker

  setup do
    # Clear ETS tables before each test
    :ets.delete_all_objects(:legion_web_agents)
    :ets.delete_all_objects(:legion_web_events)

    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")

    :ok
  end

  defp insert_agent(run_id, attrs \\ %{}) do
    record =
      Map.merge(
        %{
          run_id: run_id,
          parent_run_id: nil,
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

    :ets.insert(:legion_web_agents, {run_id, record})
    record
  end

  describe "list_agents/0" do
    test "returns empty list when no agents" do
      assert AgentTracker.list_agents() == []
    end

    test "returns agents sorted by started_at desc" do
      insert_agent(:old, %{started_at: 1000})
      insert_agent(:new, %{started_at: 2000})

      agents = AgentTracker.list_agents()
      assert length(agents) == 2
      assert hd(agents).run_id == :new
    end
  end

  describe "get_agent/1" do
    test "returns agent record" do
      insert_agent(:run1)
      agent = AgentTracker.get_agent(:run1)
      assert agent.run_id == :run1
      assert agent.status == :running
    end

    test "returns nil for missing agent" do
      assert AgentTracker.get_agent(:nonexistent) == nil
    end
  end

  describe "get_events/1" do
    test "returns empty list when no events" do
      assert AgentTracker.get_events(:no_events) == []
    end

    test "returns events in order" do
      e1 = %{seq: 1, type: :llm_start, data: %{}}
      e2 = %{seq: 2, type: :llm_stop, data: %{}}

      :ets.insert(:legion_web_events, {{:run1, 1}, e1})
      :ets.insert(:legion_web_events, {{:run1, 2}, e2})

      events = AgentTracker.get_events(:run1)
      assert length(events) == 2
      assert hd(events).seq == 1
    end

    test "only returns events for the given run_id" do
      :ets.insert(:legion_web_events, {{:run1, 1}, %{seq: 1}})
      :ets.insert(:legion_web_events, {{:run2, 1}, %{seq: 1}})

      assert length(AgentTracker.get_events(:run1)) == 1
    end
  end

  describe "handle_info :agent_started" do
    test "broadcasts agent started" do
      record = %{
        run_id: :new_agent,
        parent_run_id: nil,
        agent_module: TestAgent,
        pid: nil,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {:new_agent, record})

      send(AgentTracker, {:agent_started, :new_agent, record})

      assert_receive {:started, :new_agent, ^record}, 1000
    end
  end

  describe "handle_info :agent_stopped" do
    test "updates agent status to done and broadcasts" do
      insert_agent(:stopping)

      send(AgentTracker, {:agent_stopped, :stopping})

      assert_receive {:stopped, :stopping, record}, 1000
      assert record.status == :done
      assert record.finished_at != nil
    end
  end

  describe "handle_info :status_change" do
    test "updates agent status and broadcasts" do
      insert_agent(:changing)

      send(AgentTracker, {:status_change, :changing, :idle, %{iterations: 3}})

      assert_receive {:idle, :changing, record}, 1000
      assert record.status == :idle
      assert record.iterations == 3
    end
  end

  describe "handle_info :event" do
    test "stores event in ETS and broadcasts" do
      insert_agent(:evented)

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect(:evented)}")

      send(AgentTracker, {:event, :evented, :llm_start, %{model: "gpt-4"}})

      assert_receive {:new_event, event}, 1000
      assert event.type == :llm_start
      assert event.run_id == :evented
      assert event.data.model == "gpt-4"

      events = AgentTracker.get_events(:evented)
      assert length(events) == 1
    end
  end

  describe "handle_info :waiting_for_human" do
    test "updates status and broadcasts" do
      insert_agent(:waiting)

      send(AgentTracker, {:waiting_for_human, :waiting})

      assert_receive {:waiting, :waiting, record}, 1000
      assert record.status == :waiting_for_human
    end
  end

  describe "process monitoring" do
    test "marks agent as dead when monitored process dies unexpectedly" do
      # Start a process that we can kill
      pid = spawn(fn -> Process.sleep(:infinity) end)

      record = %{
        run_id: :monitored,
        parent_run_id: nil,
        agent_module: TestAgent,
        pid: pid,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {:monitored, record})
      send(AgentTracker, {:agent_started, :monitored, record})

      # Wait for the monitor to be set up
      assert_receive {:started, :monitored, _}, 1000

      # Kill the process
      Process.exit(pid, :kill)

      assert_receive {:dead, :monitored, dead_record}, 1000
      assert dead_record.status == :dead
      assert dead_record.finished_at != nil
    end

    test "does not mark agent as dead if already done" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      record = %{
        run_id: :already_done,
        parent_run_id: nil,
        agent_module: TestAgent,
        pid: pid,
        status: :running,
        started_at: 1000,
        finished_at: nil,
        task: nil,
        iterations: 0
      }

      :ets.insert(:legion_web_agents, {:already_done, record})
      send(AgentTracker, {:agent_started, :already_done, record})
      assert_receive {:started, :already_done, _}, 1000

      # Mark as done before killing
      :ets.insert(:legion_web_agents, {:already_done, %{record | status: :done}})

      Process.exit(pid, :kill)

      refute_receive {:dead, :already_done, _}, 200
    end
  end

  describe "event limit" do
    test "does not store events beyond max_events_per_agent limit" do
      insert_agent(:limited)

      # Insert 500 events (the max)
      for seq <- 1..500 do
        :ets.insert(:legion_web_events, {{:limited, seq}, %{seq: seq}})
      end

      # Send one more event - it should still broadcast but not store
      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect(:limited)}")
      send(AgentTracker, {:event, :limited, :llm_start, %{}})

      assert_receive {:new_event, _}, 1000
      assert length(AgentTracker.get_events(:limited)) == 500
    end
  end

  describe "forward_to_parent" do
    test "forwards events to parent agent topic" do
      insert_agent(:parent)
      insert_agent(:child, %{parent_run_id: :parent})

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect(:parent)}")

      # Simulate the telemetry handler forwarding - call handle_telemetry directly
      # which sends both the event for the child and forwards to parent
      AgentTracker.handle_telemetry(
        [:legion, :llm, :request, :stop],
        %{duration: 100},
        %{run_id: :child, object: %{"action" => "return"}},
        nil
      )

      # Should receive the forwarded event on parent topic
      assert_receive {:new_event, event}, 1000
      assert event.type == :llm_stop
    end
  end
end
