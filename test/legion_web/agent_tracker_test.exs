defmodule LegionWeb.AgentTrackerTest do
  use ExUnit.Case, async: true

  alias LegionWeb.AgentTracker

  test "defines the tracker query behaviour" do
    assert AgentTracker.behaviour_info(:callbacks) |> Enum.sort() ==
             [get_agent: 1, get_events: 1, get_usage: 1, list_agents: 1]
  end
end
