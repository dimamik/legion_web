defmodule LegionWeb.AgentTracker.PostgresTest do
  use ExUnit.Case, async: false

  alias Legion.Store.Payload
  alias LegionWeb.AgentTracker.LegionAgent
  alias LegionWeb.AgentTracker.LegionEvent
  alias LegionWeb.AgentTracker.Postgres

  defmodule Store do
    def start_link(_opts) do
      Agent.start_link(fn -> %{payloads: %{}, list_limits: []} end, name: __MODULE__)
    end

    def child_spec(opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
    end

    def put(%Payload{} = payload) do
      Agent.update(__MODULE__, fn state ->
        put_in(state.payloads[payload.agent_id], payload)
      end)
    end

    def list_limits, do: Agent.get(__MODULE__, & &1.list_limits)

    def list(limit) do
      Agent.get_and_update(__MODULE__, fn state ->
        {state.payloads |> Map.values() |> Enum.sort_by(& &1.started_at, :desc),
         %{state | list_limits: [limit | state.list_limits]}}
      end)
    end

    def get(agent_id) do
      Agent.get(__MODULE__, fn state ->
        case Map.fetch(state.payloads, agent_id) do
          {:ok, payload} -> {:ok, payload}
          :error -> :error
        end
      end)
    end

    def __repo__, do: LegionWeb.AgentTracker.PostgresTest.Repo
    def __table__, do: "test_agents"
  end

  defmodule Repo do
    def config, do: []
  end

  defmodule Notifications do
    def start_link(_opts), do: Agent.start_link(fn -> nil end)
    def listen(_notifications, _channel), do: {:ok, make_ref()}
  end

  setup do
    start_supervised!(Store)

    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agents")

    Store.put(%Payload{
      agent_id: "new",
      agent_module: TestAgent,
      status: :idle,
      started_at: ~N[2026-07-27 12:00:00]
    })

    :ok
  end

  test "passes requested list limit to the configured store" do
    assert {:ok, _pid} = Postgres.start_link(store: Store, notifications: Notifications)

    assert [agent] = Postgres.list_agents(50)
    assert agent.agent_id == "new"
    assert Store.list_limits() == [50]
  end

  test "reads agent records and durable events through the GenServer" do
    Store.put(%Payload{
      agent_id: "history",
      agent_module: TestAgent,
      status: :idle,
      started_at: ~N[2026-07-27 12:01:02.003004],
      conversation_state: %{
        messages: [
          %{type: :user, content: "hello", at: 1},
          %{type: :assistant, content: "not-json", at: 2},
          %{type: :eval_result, content: "ok", at: 3},
          %{type: :error, content: "failed", at: 4}
        ],
        bindings: []
      }
    })

    assert {:ok, _pid} = Postgres.start_link(store: Store, notifications: Notifications)

    assert %LegionAgent{agent_id: "history", status: :done, started_at: 1_785_153_662_003} =
             Postgres.get_agent("history")

    assert Postgres.get_agent("missing") == nil

    assert [
             %LegionEvent{seq: 1, type: :message_start, data: %{message: "hello"}},
             %LegionEvent{seq: 2, type: :llm_stop, data: %{object: %{"raw" => "not-json"}}},
             %LegionEvent{seq: 3, type: :eval_stop, data: %{success: true, result: "ok"}},
             %LegionEvent{seq: 4, type: :eval_stop, data: %{success: false, error: "failed"}}
           ] = Postgres.get_events("history")
  end

  test "uses Legion.lookup to expose a live agent pid" do
    parent = self()

    pid =
      spawn(fn ->
        :yes = Legion.AgentIndex.register_name("live", self())
        send(parent, :live_agent_registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :live_agent_registered
    on_exit(fn -> send(pid, :stop) end)

    Store.put(%Payload{
      agent_id: "live",
      agent_module: TestAgent,
      status: :running,
      started_at: ~N[2026-07-27 12:00:00]
    })

    assert {:ok, _pid} = Postgres.start_link(store: Store, notifications: Notifications)
    assert %{pid: ^pid, status: :running} = Postgres.get_agent("live")
  end

  test "reads usage through the GenServer" do
    usage = [%{"input_tokens" => 1, "output_tokens" => 2, "at" => 1}]

    Store.put(%Payload{
      agent_id: "usage",
      agent_module: TestAgent,
      status: :idle,
      started_at: ~N[2026-07-27 12:00:00],
      usage: usage
    })

    assert {:ok, _pid} = Postgres.start_link(store: Store, notifications: Notifications)

    assert Postgres.get_usage("usage") == usage
    assert Postgres.get_usage("new") == []
    assert Postgres.get_usage("missing") == []
  end

  test "notification broadcasts the agent's current usage" do
    start_supervised!({Postgres, store: Store, notifications: Notifications})
    usage = [%{"input_tokens" => 1, "at" => 1}]

    Store.put(%Payload{
      agent_id: "new",
      agent_module: TestAgent,
      status: :idle,
      started_at: ~N[2026-07-27 12:00:00],
      usage: usage
    })

    send(Postgres, {:notification, self(), make_ref(), "test_agents", "new"})

    assert_receive {:usage, "new", ^usage}
  end

  test "notification broadcasts the agent's derived current status" do
    start_supervised!({Postgres, store: Store, notifications: Notifications})

    send(Postgres, {:notification, self(), make_ref(), "test_agents", "new"})

    assert_receive {:done, "new", %{agent_id: "new", pid: nil, status: :done}}
    refute_receive {:started, "new", _}
  end

  test "notification broadcasts only events appended after get_events" do
    started_at = ~N[2026-07-27 12:00:00]

    Store.put(%Payload{
      agent_id: "events",
      agent_module: TestAgent,
      status: :running,
      started_at: started_at,
      conversation_state: %{
        messages: [%{type: :user, content: "first", at: 1}],
        bindings: []
      }
    })

    start_supervised!({Postgres, store: Store, notifications: Notifications})
    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:\"events\"")

    assert [%{seq: 1, type: :message_start}] = Postgres.get_events("events")

    Store.put(%Payload{
      agent_id: "events",
      agent_module: TestAgent,
      status: :idle,
      started_at: started_at,
      conversation_state: %{
        messages: [
          %{type: :user, content: "first", at: 1},
          %{type: :assistant, content: ~s({"action":"done"}), at: 2}
        ],
        bindings: []
      }
    })

    send(Postgres, {:notification, self(), make_ref(), "test_agents", "events"})

    assert_receive {:new_event,
                    %{seq: 2, type: :llm_stop, data: %{object: %{"action" => "done"}}}}

    refute_receive {:new_event, %{seq: 1}}
  end

  test "notification does not replay history for an unprimed agent" do
    Store.put(%Payload{
      agent_id: "unprimed",
      agent_module: TestAgent,
      status: :running,
      started_at: ~N[2026-07-27 12:00:00],
      conversation_state: %{
        messages: [%{type: :user, content: "old", at: 1}],
        bindings: []
      }
    })

    start_supervised!({Postgres, store: Store, notifications: Notifications})
    Phoenix.PubSub.subscribe(LegionWeb.PubSub, "legion_web:agent:\"unprimed\"")

    send(Postgres, {:notification, self(), make_ref(), "test_agents", "unprimed"})

    refute_receive {:new_event, _}
  end
end
