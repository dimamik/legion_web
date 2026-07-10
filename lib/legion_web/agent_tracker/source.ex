defmodule LegionWeb.AgentTracker.Source do
  @moduledoc """
  Behaviour for AgentTracker source processes.

  A source reads an external or local signal stream and emits canonical
  AgentTracker commands.
  """
  @type opts :: keyword()

  @callback start_link(opts()) :: GenServer.on_start()
end
