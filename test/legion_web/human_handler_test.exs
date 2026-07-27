defmodule LegionWeb.HumanHandlerTest do
  use ExUnit.Case

  alias LegionWeb.HumanHandler

  setup do
    # Subscribe to PubSub for the test agent_id
    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:#{inspect(:test_agent)}")

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
      send(HumanHandler, {:human_request, ref, from_pid, "What color?", %{agent_id: :test_agent}})

      assert_receive {:human_request, "What color?"}, 1000

      # Respond via the handler
      assert HumanHandler.respond(:test_agent, "blue") == :ok

      # The response should be sent back to the original process
      assert_receive {:human_response, ^ref, "blue"}, 1000

      # Should also broadcast human_responded
      assert_receive {:human_responded, "blue"}, 1000
    end

    test "respond returns :not_found for unknown agent_id" do
      assert HumanHandler.respond(:unknown_agent, "hello") == :not_found
    end

    test "clears pending request after response" do
      ref = make_ref()

      send(HumanHandler, {:human_request, ref, self(), "Q?", %{agent_id: :test_agent}})
      assert_receive {:human_request, "Q?"}, 1000

      assert HumanHandler.respond(:test_agent, "A") == :ok
      assert_receive {:human_response, ^ref, "A"}, 1000

      # Second respond should be :not_found
      assert HumanHandler.respond(:test_agent, "again") == :not_found
    end

    test "emits human activity through telemetry" do
      ref = make_ref()
      handler_id = {__MODULE__, self(), make_ref()}

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:legion_web, :agent, :waiting_for_human],
            [:legion_web, :agent, :human_response]
          ],
          fn event, measurements, metadata, test_pid ->
            send(test_pid, {:human_activity, event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      send(HumanHandler, {:human_request, ref, self(), "Q?", %{agent_id: :test_agent}})
      assert_receive {:human_request, "Q?"}, 1000

      assert_receive {:human_activity, [:legion_web, :agent, :waiting_for_human], %{},
                      %{agent_id: :test_agent}},
                     1000

      HumanHandler.respond(:test_agent, "answer")

      assert_receive {:human_activity, [:legion_web, :agent, :human_response], %{},
                      %{agent_id: :test_agent, text: "answer"}},
                     1000
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
