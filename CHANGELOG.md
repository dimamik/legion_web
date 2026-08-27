# Changelog

## Unreleased

### Changes

- Add LLM usage tracking: `LegionWeb.AgentTracker` gains a `get_usage/1` callback, implemented by the telemetry and Postgres trackers, and the agent header shows input / output tokens and cost, with a `Usage` overlay listing totals and every request
- Add the configurable `LegionWeb.AgentTracker` interface, with telemetry-based tracking as the default
- Add `LegionWeb.AgentTracker.Postgres` for loading persisted agents and conversation events from a PostgreSQL-backed `Legion.Store`, with live updates from database notifications
- Align dashboard records, routes, PubSub messages, and human-tool integration with Legion's `agent_id` and `parent_agent_id` terminology
- Ship compiled dashboard CSS and JavaScript with the package
- Update project attribution and repository links to Software Mansion

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
