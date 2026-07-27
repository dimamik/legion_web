# Database Agent Tracker Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate `LegionWeb.AgentTracker.Database` with the current `LegionWeb.AgentTracker` and `Legion.Store` contracts, including live PostgreSQL-backed dashboard updates.

**Architecture:** `Database` remains a named GenServer and receives its store explicitly through startup options. All query functions call that GenServer, which owns the store, PostgreSQL notification connection, and per-agent event cursors; database notifications reload durable snapshots and publish dashboard-compatible status and incremental event messages.

**Tech Stack:** Elixir, OTP GenServer, `Legion.Store`, `Postgrex.Notifications`, Phoenix PubSub, ExUnit

## Global Constraints

- Modify only the `legion_web` repository.
- Do not read the store from application environment.
- Require a Postgres-capable store exposing `__repo__/0` and `__table__/0`; fail startup otherwise.
- Match `Telemetry` with `@max_agents 100`.
- Treat stored conversation messages as append-only.
- Reconstruct only durable message events: user, assistant, eval result, and error.
- Resolve live processes with `Legion.lookup/1`.
- Convert persisted `NaiveDateTime` values to Unix milliseconds.
- Do not synthesize `:started`; broadcast the record's derived current status for every notification.

---

## File Structure

- Modify `lib/legion_web/agent_tracker/database.ex`: option validation, GenServer query boundary, current store calls, payload conversion, notification handling, and event cursors.
- Create `test/legion_web/agent_tracker/database_test.exs`: focused contract, conversion, listener, and incremental-broadcast coverage using fake store/repo/notifications modules.

### Task 1: Move database queries to the GenServer and current store contract

**Files:**
- Modify: `lib/legion_web/agent_tracker/database.ex`
- Create: `test/legion_web/agent_tracker/database_test.exs`

**Interfaces:**
- Consumes: `{LegionWeb.AgentTracker.Database, store: StoreModule}` child specification; `StoreModule.list/1`; `StoreModule.get/1`
- Produces: `list_agents/0`, `get_agent/1`, and `get_events/1` implementing `LegionWeb.AgentTracker`

- [ ] **Step 1: Add failing query-contract tests**

  Define a fake store backed by an Agent and fake notification adapter. Assert that startup requires `:store`, `list_agents/0` calls `store.list(100)`, `get_agent/1` maps `{:ok, %Legion.Store.Payload{}}`, a missing payload maps to `nil`, and all calls work only through the running `Database` GenServer.

- [ ] **Step 2: Run the focused tests and verify failure**

  Run:

  ```bash
  mix test test/legion_web/agent_tracker/database_test.exs
  ```

  Expected: failures because `Database` still reads application environment, exports `list_agents/1`, and calls removed store functions.

- [ ] **Step 3: Put the configured store and listener in GenServer state**

  Change initialization to fetch `:store` from `opts`, validate `__repo__/0` and `__table__/0`, start/listen through the notification adapter, and return:

  ```elixir
  %{
    store: store,
    notifications: notifications,
    event_cursors: %{}
  }
  ```

  Keep `Postgrex.Notifications` as the production default; permit a private/test adapter option so listener behavior can be tested without a real database.

- [ ] **Step 4: Implement GenServer-backed query functions**

  Implement public calls:

  ```elixir
  def list_agents, do: GenServer.call(__MODULE__, :list_agents)
  def get_agent(agent_id), do: GenServer.call(__MODULE__, {:get_agent, agent_id})
  def get_events(agent_id), do: GenServer.call(__MODULE__, {:get_events, agent_id})
  ```

  Implement matching `handle_call/3` clauses using `store.list(@max_agents)` and `store.get(agent_id)`. In `get_events/1`, set `event_cursors[agent_id]` to the returned event count.

- [ ] **Step 5: Normalize current payloads into tracker records**

  Resolve liveness using:

  ```elixir
  case Legion.lookup(payload.agent_id) do
    {:ok, pid} -> {pid, true}
    :error -> {nil, false}
  end
  ```

  Preserve the existing status mapping (`running/idle` while live; `dead/done` while absent), and convert persisted UTC `NaiveDateTime` values to Unix milliseconds before assigning `started_at`.

- [ ] **Step 6: Reconstruct durable events defensively**

  Convert stored message types:

  ```elixir
  :user        -> :message_start
  :assistant   -> :llm_stop
  :eval_result -> :eval_stop
  :error       -> :eval_stop
  ```

  Use `Jason.decode/1` for assistant action content and provide a non-crashing fallback for malformed or legacy content. Return `[]` for missing payloads or missing conversation state.

- [ ] **Step 7: Run the focused tests**

  Run:

  ```bash
  mix test test/legion_web/agent_tracker/database_test.exs
  ```

  Expected: all query, liveness, timestamp, and event-conversion tests pass.

### Task 2: Turn PostgreSQL notifications into compatible live updates

**Files:**
- Modify: `lib/legion_web/agent_tracker/database.ex`
- Modify: `test/legion_web/agent_tracker/database_test.exs`

**Interfaces:**
- Consumes: PostgreSQL notification tuple carrying `agent_id`; GenServer state from Task 1
- Produces: global `{status, agent_id, record}` PubSub messages and per-agent `{:new_event, event}` messages

- [ ] **Step 1: Add failing live-update tests**

  Cover:

  - a notification reloads the payload and broadcasts `{record.status, agent_id, record}` on `"legion_web:agents"`;
  - no `:started` event is synthesized;
  - after `get_events/1` primes a cursor, a later notification broadcasts only appended events;
  - a notification for an unprimed agent establishes its cursor without replaying historical events;
  - a missing store row is ignored without crashing;
  - an unrelated process message is ignored.

- [ ] **Step 2: Run the focused tests and verify failure**

  Run:

  ```bash
  mix test test/legion_web/agent_tracker/database_test.exs
  ```

  Expected: failures because the current listener publishes only the ignored `{:store_updated, agent_id}` tuple.

- [ ] **Step 3: Reload and broadcast the agent record**

  In the notification handler, call `state.store.get(agent_id)`. For an existing payload, convert it to a record and broadcast:

  ```elixir
  Phoenix.PubSub.broadcast(
    LegionWeb.PubSub,
    "legion_web:agents",
    {record.status, agent_id, record}
  )
  ```

  Do not synthesize lifecycle events.

- [ ] **Step 4: Broadcast only appended durable events**

  Convert the payload's current message list, compare its length with `event_cursors[agent_id]`, and:

  - when a cursor exists, broadcast `Enum.drop(events, cursor)` on `"legion_web:agent:#{inspect(agent_id)}"`;
  - when no cursor exists, broadcast no historical events;
  - after either case, store the current event count as the new cursor.

- [ ] **Step 5: Run focused and full verification**

  Run:

  ```bash
  mix format --check-formatted
  mix test test/legion_web/agent_tracker/database_test.exs
  mix test
  ```

  Expected: formatting succeeds and the complete `legion_web` test suite passes.

