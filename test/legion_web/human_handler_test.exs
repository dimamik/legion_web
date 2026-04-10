defmodule LegionWeb.HumanHandlerTest do
  use ExUnit.Case

  alias LegionWeb.HumanHandler

  setup do
    # Subscribe to PubSub for the test run_id
    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect(:test_run)}")

    # Clear ETS tables used by AgentTracker
    :ets.delete_all_objects(:legion_web_agents)
    :ets.delete_all_objects(:legion_web_events)

    :ok
  end

  describe "request/response cycle" do
    test "broadcasts human_request and delivers response back" do
      ref = make_ref()
      from_pid = self()

      # Simulate HumanTool sending the request
      send(HumanHandler, {:human_request, ref, from_pid, "What color?", %{run_id: :test_run}})

      assert_receive {:human_request, "What color?"}, 1000

      # Respond via the handler
      assert HumanHandler.respond(:test_run, "blue") == :ok

      # The response should be sent back to the original process
      assert_receive {:human_response, ^ref, "blue"}, 1000

      # Should also broadcast human_responded
      assert_receive {:human_responded, "blue"}, 1000
    end

    test "respond returns :not_found for unknown run_id" do
      assert HumanHandler.respond(:unknown_run, "hello") == :not_found
    end

    test "clears pending request after response" do
      ref = make_ref()

      send(HumanHandler, {:human_request, ref, self(), "Q?", %{run_id: :test_run}})
      assert_receive {:human_request, "Q?"}, 1000

      assert HumanHandler.respond(:test_run, "A") == :ok
      assert_receive {:human_response, ^ref, "A"}, 1000

      # Second respond should be :not_found
      assert HumanHandler.respond(:test_run, "again") == :not_found
    end

    test "sends status_change and event to AgentTracker on response" do
      ref = make_ref()

      # Insert a test agent so AgentTracker can update it
      :ets.insert(:legion_web_agents, {
        :test_run,
        %{
          run_id: :test_run,
          parent_run_id: nil,
          agent_module: TestAgent,
          pid: self(),
          status: :waiting_for_human,
          started_at: 1000,
          finished_at: nil,
          task: nil,
          iterations: 0
        }
      })

      Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")

      send(HumanHandler, {:human_request, ref, self(), "Q?", %{run_id: :test_run}})
      assert_receive {:human_request, "Q?"}, 1000

      # Drain the :waiting broadcast from AgentTracker
      assert_receive {:waiting, :test_run, _}, 1000

      HumanHandler.respond(:test_run, "answer")

      # AgentTracker should receive and process the status_change to :running
      assert_receive {:running, :test_run, _record}, 1000
    end
  end

  describe "handle_info with unrecognized messages" do
    test "ignores unknown messages" do
      send(HumanHandler, :garbage)

      # The handler should still be alive and working
      assert HumanHandler.respond(:nobody, "test") == :not_found
    end
  end
end
