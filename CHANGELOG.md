# Changelog

## Unreleased

### Changes

- Escape raw HTML blocks in rendered markdown: LLM responses and system prompts can no longer inject markup (e.g. `<script>`) into the dashboard, and malformed markdown renders best-effort instead of raising
- Honor the `:transport` router option - `"longpoll"` previously fell through to websocket
- Use `Legion.running?/1` when sending chat messages, so agents running on other nodes (Postgres tracker) no longer crash the dashboard
- Render persisted agents whose module no longer exists instead of crashing, and show `"unknown"` for a missing agent module name
- Evict the oldest stored event when an agent passes the per-agent cap, instead of silently dropping new events
- Monitor HumanTool askers so pending questions from crashed or timed-out evals are cleaned up
- Guard all telemetry-handler sends against a restarting tracker, which previously could detach the handler
- Show "Load more" only when the tracker actually holds more agents
- Convert trace durations from native time units instead of assuming nanoseconds
- Style markdown in trace response boxes (previously referenced non-existent `prose` classes)
- Ship only `priv/static/app.css` and `priv/static/app.js` in the Hex package

- Add LLM usage tracking: `LegionWeb.AgentTracker` gains a `get_usage/1` callback, implemented by the telemetry and Postgres trackers, and the agent header shows input / output tokens and cost, with a `Usage` overlay listing totals and every request
- Add the configurable `LegionWeb.AgentTracker` interface, with telemetry-based tracking as the default
- Add `LegionWeb.AgentTracker.Postgres` for loading persisted agents and conversation events from a PostgreSQL-backed `Legion.Store`, with live updates from database notifications
- Align dashboard records, routes, PubSub messages, and human-tool integration with Legion's `agent_id` and `parent_agent_id` terminology
- Ship compiled dashboard CSS and JavaScript with the package
- Update project attribution and repository links to Software Mansion
- Add `LegionWeb.Markup` - highlight trace code in the language of the agent's `Legion.Sandbox` (Lua by default) and system-prompt fenced blocks by their fence language, backed by `makeup_syntect`

## v0.3.0 - 2026-04-21

### Changes

- Introduce `TraceReducer` - incremental state machine that pairs LLM and eval events, groups sub-agent spans, and collapses redundant eval_and_complete + return/done pairs, replacing the previous multi-pass list processing in the Trace component
- Add system prompt overlay with agent config badges, accessible from the agent detail header
- Inline eval results directly into their parent LLM step instead of rendering separate rows
- Display final LLM response text and LLM errors in trace view
- Add `ResetForm` JS hook to clear chat input after submit
- Properly escape quoted strings when extracting `HumanTool.ask` questions
- Use Igniter module aliases in the install mix task
- Add tests for `DashboardLive`, `TraceReducer` error paths, and `legion_web.install` task

## v0.1.0

![LegionWeb Dashboard](https://raw.githubusercontent.com/dimamik/legion_web/main/img/preview.png)

Initial release of `legion_web` - stateless dashboard for monitoring your AI Agents spawned by legion.
