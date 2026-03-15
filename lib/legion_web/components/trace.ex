defmodule LegionWeb.Components.Trace do
  @moduledoc false

  use LegionWeb, :html

  alias LegionWeb.Helpers

  attr :events, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :display_events, displayable_events(assigns.events))

    ~H"""
    <div
      id="trace-container"
      class="flex-1 overflow-y-auto px-6 py-4 space-y-1 font-mono text-xs text-black"
      phx-hook="AutoScroll"
    >
      <div :if={@events == []} class="flex items-center justify-center h-full">
        <p class="text-black/40 italic">Waiting for events&hellip;</p>
      </div>
      <%= for group <- @display_events do %>
        <%= case group do %>
          <% {:event, event} -> %>
            <div id={"event-#{event.seq}"} class="animate-fade-in">
              <.event_row event={event} />
            </div>
          <% {:subagent, agent_name, events} -> %>
            <details
              id={"subagent-#{hd(events).seq}"}
              class="animate-fade-in my-1"
              phx-hook="DetailsState"
            >
              <summary class="cursor-pointer flex gap-2 items-center py-1 px-3 bg-sol-base2/50 border border-sol-base1/20 rounded-lg hover:bg-sol-base2">
                <span class="text-sol-cyan font-semibold text-xs">{agent_name}</span>
                <span class="text-black/50 text-xs">{length(events)} events</span>
              </summary>
              <div class="ml-4 pl-3 border-l-2 border-sol-cyan/30 space-y-1 py-1">
                <div :for={event <- events} id={"event-#{event.seq}"}>
                  <.event_row event={event} />
                </div>
              </div>
            </details>
        <% end %>
      <% end %>
    </div>
    """
  end

  @hidden_types [:iteration_start, :iteration_stop, :eval_start, :llm_start, :message_stop]

  defp displayable_events(events) do
    events
    |> merge_eval_results()
    |> Enum.reject(&hidden_event?/1)
    |> remove_redundant_eval_and_complete()
    |> group_subagent_events()
  end

  # Attach eval_stop results to preceding eval_and_complete/eval_and_continue llm_stop events,
  # then hide those eval_stop rows (the result is shown inline on the llm_stop row)
  defp merge_eval_results(events) do
    {result, pending} =
      Enum.reduce(events, {[], nil}, fn
        %{type: :eval_stop, data: eval_data}, {acc, %{} = llm_event} ->
          merged = put_in(llm_event.data[:eval_result], eval_data[:result])
          {acc ++ [merged], nil}

        %{type: :eval_start}, {acc, %{} = _llm_event} = state ->
          # Skip eval_start between llm_stop and eval_stop
          {acc, elem(state, 1)}

        event, {acc, %{} = llm_event} ->
          {acc ++ [llm_event, event], nil}

        %{type: :llm_stop, data: %{object: %{"action" => action}}} = event, {acc, nil}
        when action in ["eval_and_complete", "eval_and_continue"] ->
          {acc, event}

        event, {acc, nil} ->
          {acc ++ [event], nil}
      end)

    case pending do
      nil -> result
      event -> result ++ [event]
    end
  end

  # Hide eval_and_complete llm_stop when followed by a return/done llm_stop
  # (the final result will be shown on the return/done row)
  defp remove_redundant_eval_and_complete(events) do
    events
    |> Enum.chunk_every(2, 1, [:end])
    |> Enum.flat_map(fn
      [
        %{type: :llm_stop, data: %{object: %{"action" => "eval_and_complete"}}},
        %{type: :llm_stop, data: %{object: %{"action" => action}}}
      ]
      when action in ["return", "done"] ->
        []

      [event, _] ->
        [event]

      [event] ->
        [event]
    end)
  end

  # Group consecutive sub-agent events into collapsible sections
  defp group_subagent_events(events) do
    {result, pending} = Enum.reduce(events, {[], nil}, &accumulate_event/2)

    case pending do
      nil -> result
      {name, sub_events} -> result ++ [{:subagent, name, sub_events}]
    end
  end

  defp accumulate_event(event, {result, pending}) do
    if subagent_event?(event) do
      accumulate_subagent_event(event, result, pending)
    else
      flush_pending(event, result, pending)
    end
  end

  defp accumulate_subagent_event(event, result, pending) do
    name = agent_short_name(event.data[:agent])

    case pending do
      {^name, sub_events} ->
        {result, {name, sub_events ++ [event]}}

      nil ->
        {result, {name, [event]}}

      {other_name, sub_events} ->
        {result ++ [{:subagent, other_name, sub_events}], {name, [event]}}
    end
  end

  defp flush_pending(event, result, pending) do
    case pending do
      nil -> {result ++ [{:event, event}], nil}
      {name, sub_events} -> {result ++ [{:subagent, name, sub_events}, {:event, event}], nil}
    end
  end

  defp hidden_event?(%{type: type}) when type in @hidden_types, do: true
  defp hidden_event?(%{type: :eval_stop, data: %{success: true}}), do: true
  defp hidden_event?(_), do: false

  defp subagent_event?(%{run_id: parent_run_id, data: %{run_id: child_run_id}})
       when parent_run_id != child_run_id,
       do: true

  defp subagent_event?(_), do: false

  defp agent_short_name(nil), do: "sub-agent"

  defp agent_short_name(module) when is_atom(module) do
    module |> Module.split() |> List.last()
  end

  defp agent_short_name(other), do: inspect(other)

  # Event rows

  defp event_row(%{event: %{type: :message_start}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start bg-sol-blue/10 border border-sol-blue/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="flex-1">{@event.data[:message]}</span>
    </div>
    """
  end

  defp event_row(%{event: %{type: :human_response}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start bg-sol-yellow/10 border border-sol-yellow/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="flex-1">{@event.data[:text]}</span>
    </div>
    """
  end

  defp event_row(%{event: %{type: :message_exception}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start bg-sol-red/10 border border-sol-red/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-red font-semibold">error</span>
      <span class="text-sol-red/80 flex-1">{format_exception(@event.data)}</span>
    </div>
    """
  end

  defp event_row(%{event: %{type: :llm_stop}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      {if object = @event.data[:object] do
        assigns |> assign(:object, object) |> render_llm_response()
      else
        assigns |> render_llm_response_fallback()
      end}
      <span class="text-black/50 ml-auto shrink-0">
        {format_duration(@event.data[:duration])}
      </span>
    </div>
    """
  end

  defp event_row(%{event: %{type: :eval_stop}} = assigns) do
    ~H"""
    {if @event.data[:success] do
      assigns |> render_eval_success()
    else
      assigns |> render_eval_error()
    end}
    """
  end

  defp event_row(assigns) do
    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span>{inspect(@event.type)}</span>
    </div>
    """
  end

  # Sub-renders

  defp render_llm_response(assigns) do
    assigns =
      assigns
      |> assign(:human_question, extract_human_question(assigns.object["code"]))
      |> assign(:eval_result, assigns.event.data[:eval_result])

    ~H"""
    <div class="flex-1">
      <%= if @human_question do %>
        <div class="flex gap-2 items-center">
          <span class="text-sol-orange font-semibold">?</span>
          <span class="text-black">{@human_question}</span>
        </div>
      <% else %>
        <span class={action_class(@object["action"])}>{@object["action"]}</span>
        <details :if={@object["code"] && @object["code"] != ""} class="mt-1.5 code-details">
          <summary class="cursor-pointer text-black/60 hover:text-black text-xs">
            <span class="show-label">show code</span>
            <span class="hide-label">hide code</span>
          </summary>
          <pre class="mt-1.5 p-3 bg-sol-base2 rounded-lg overflow-x-auto whitespace-pre-wrap border border-sol-base1/20 highlight">{Helpers.highlight_elixir(@object["code"])}</pre>
        </details>
        <div
          :if={@object["action"] in ["return", "done"] && has_result?(@object["result"])}
          class="mt-1.5 p-3 bg-sol-green/8 border border-sol-green/20 rounded-lg"
        >
          <div class="text-black prose prose-sm max-w-none">
            {render_markdown(extract_response(@object["result"]))}
          </div>
        </div>
        <div
          :if={has_result?(@eval_result)}
          class="mt-1.5 p-3 bg-sol-base2 border border-sol-base1/20 rounded-lg"
        >
          <pre class="text-xs whitespace-pre-wrap">{format_eval_result(@eval_result)}</pre>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_llm_response_fallback(assigns) do
    ~H"""
    <span>(response)</span>
    """
  end

  defp render_eval_success(assigns) do
    has_error = error_result?(assigns.event.data[:result])
    assigns = assign(assigns, :has_error, has_error)

    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class={if @has_error, do: "text-sol-red", else: "text-sol-green"}>
        {if @has_error, do: "✗", else: "⚡"}
      </span>
      <div class="flex-1">
        <pre class={[
          "p-3 rounded-lg overflow-x-auto whitespace-pre-wrap text-xs",
          if(@has_error,
            do: "bg-sol-red/8 border border-sol-red/20 text-sol-red",
            else: "bg-sol-base2 border border-sol-base1/20 text-black"
          )
        ]}>{format_eval_result(@event.data[:result])}</pre>
      </div>
    </div>
    """
  end

  defp render_eval_error(assigns) do
    is_timeout = match?(%{type: :timeout}, assigns.event.data[:error])
    assigns = assign(assigns, :is_timeout, is_timeout)

    ~H"""
    <div class={[
      "flex gap-2 items-start py-0.5",
      @is_timeout && "bg-sol-orange/8 border border-sol-orange/20 rounded-lg p-2.5 my-1"
    ]}>
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class={if @is_timeout, do: "text-sol-orange", else: "text-sol-red"}>
        {if @is_timeout, do: "⏱", else: "✗"}
      </span>
      <div class="flex-1">
        <pre class={[
          "p-3 rounded-lg overflow-x-auto whitespace-pre-wrap text-xs",
          if(@is_timeout,
            do: "text-sol-orange",
            else: "bg-sol-red/8 border border-sol-red/20 text-sol-red"
          )
        ]}>{format_eval_error(@event.data[:error])}</pre>
      </div>
    </div>
    """
  end

  # Helpers

  defp has_result?(nil), do: false
  defp has_result?(""), do: false
  defp has_result?(_), do: true

  defp error_result?({:error, _}), do: true

  defp error_result?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&error_result?/1)

  defp error_result?(list) when is_list(list), do: Enum.any?(list, &error_result?/1)
  defp error_result?(_), do: false

  defp format_ts(ms) when is_integer(ms) do
    ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_ts(_), do: "--:--:--"

  defp format_duration(nil), do: nil

  defp format_duration(duration) when is_integer(duration) do
    ms = div(duration, 1_000_000)
    Helpers.format_ms(ms)
  end

  defp format_duration(_), do: nil

  defp extract_human_question(nil), do: nil

  defp extract_human_question(code) when is_binary(code) do
    case Regex.run(~r/HumanTool\.ask\(\s*"([^"]+)"\s*\)/, code) do
      [_, question] -> question
      _ -> nil
    end
  end

  defp action_class("eval_and_continue"), do: "text-sol-blue"
  defp action_class("eval_and_complete"), do: "text-sol-green"
  defp action_class("return"), do: "text-sol-green font-semibold"
  defp action_class("done"), do: "text-black"
  defp action_class(_), do: "text-black"

  defp format_eval_result(result) do
    formatted = inspect(result, pretty: true, limit: 100, printable_limit: 2000)

    if String.length(formatted) > 1500 do
      String.slice(formatted, 0, 1500) <> "\n… (truncated)"
    else
      formatted
    end
  end

  defp format_eval_error(%{message: message}) when is_binary(message), do: message
  defp format_eval_error(error) when is_exception(error), do: Exception.message(error)
  defp format_eval_error(error), do: inspect(error, pretty: true, limit: 50)

  defp format_exception(data) do
    case data do
      %{reason: reason} when is_exception(reason) -> Exception.message(reason)
      %{reason: reason} -> inspect(reason, pretty: true, limit: 50)
      _ -> "Unknown error"
    end
  end

  defp extract_response(result) when is_map(result) do
    case Map.get(result, "response") do
      nil -> format_result(result)
      response when is_binary(response) -> response
      other -> inspect(other)
    end
  end

  defp extract_response(result) when is_binary(result), do: result
  defp extract_response(result), do: inspect(result, pretty: true, limit: 500)

  defp format_result(result) when is_map(result) do
    Jason.encode!(result, pretty: true)
  rescue
    _ -> inspect(result, pretty: true, limit: 500)
  end

  defp format_result(result), do: inspect(result, pretty: true, limit: 500)

  defp render_markdown(text) when is_binary(text) do
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  defp render_markdown(other), do: other
end
