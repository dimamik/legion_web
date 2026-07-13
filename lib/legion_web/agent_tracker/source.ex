defmodule LegionWeb.AgentTracker.Source do
  @moduledoc """
  Behaviour for AgentTracker sources.

  A source reads an external or local signal stream and emits canonical
  AgentTracker commands.
  """
  @type opts :: keyword()

  @callback init(opts()) :: :ok | {:error, term()}
end
