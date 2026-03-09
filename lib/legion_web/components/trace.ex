defmodule LegionWeb.Components.Trace do
  use LegionWeb, :html

  alias LegionWeb.Helpers

  attr :events, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :display_events, displayable_events(assigns.events))

    ~H"""
    <div
      id="trace-container"
      class="flex-1 overflow-y-auto px-6 py-4 space-y-1 font-mono text-xs"
      phx-hook="AutoScroll"
    >
      <div :if={@events == []} class="flex items-center justify-center h-full">
        <p class="text-sol-base1 italic">Waiting for events&hellip;</p>
      </div>
      <div :for={event <- @display_events} id={"event-#{event.seq}"} class="animate-fade-in">
        <.event_row event={event} />
      </div>
    </div>
    """
  end

  defp displayable_events(events) do
    Enum.filter(events, fn event ->
      event.type not in [:iteration_start, :eval_start]
    end)
  end

  # User sent a message to the agent
  defp event_row(%{event: %{type: :message_start}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start bg-sol-blue/10 border border-sol-blue/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-blue font-semibold">user</span>
      <span class="text-sol-base02 flex-1">{@event.data[:message]}</span>
    </div>
    """
  end

  # Agent finished processing a message
  defp event_row(%{event: %{type: :message_stop}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start py-0.5 text-sol-base00">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-green">&#10003;</span>
      <div class="flex-1">
        <span>
          message complete
          <span :if={@event.data[:iterations]} class="text-sol-base00/70">
            ({@event.data[:iterations]} iterations, {format_duration(@event.data[:duration])})
          </span>
        </span>
        <div
          :if={has_result?(@event.data[:result])}
          class="mt-1.5 p-3 bg-sol-green/8 border border-sol-green/20 rounded-lg"
        >
          <span class="text-sol-base02 whitespace-pre-wrap">{format_message_result(@event.data[:result])}</span>
        </div>
      </div>
    </div>
    """
  end

  # Agent message processing threw an exception
  defp event_row(%{event: %{type: :message_exception}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start bg-sol-red/10 border border-sol-red/20 rounded-lg px-3 py-2.5 my-2">
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-red font-semibold">error</span>
      <span class="text-sol-red/80 flex-1">{format_exception(@event.data)}</span>
    </div>
    """
  end

  # Iteration completed
  defp event_row(%{event: %{type: :iteration_stop}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-center py-0.5 text-sol-base00">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-base00">&middot;</span>
      <span>
        iteration #{@event.data[:iteration]}
        <span :if={@event.data[:action]} class={action_class(@event.data[:action])}>
          {to_string(@event.data[:action])}
        </span>
      </span>
    </div>
    """
  end

  # LLM request started
  defp event_row(%{event: %{type: :llm_start}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-center py-0.5">
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-violet/70">&rarr;</span>
      <span class="text-sol-violet">LLM</span>
      <span class="text-sol-base00">{@event.data[:model]}</span>
      <span :if={@event.data[:message_count]} class="text-sol-base00/70">
        ({@event.data[:message_count]} msgs)
      </span>
    </div>
    """
  end

  # LLM request completed
  defp event_row(%{event: %{type: :llm_stop}} = assigns) do
    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class="text-sol-violet/70">&larr;</span>
      {if object = @event.data[:object] do
        assigns |> assign(:object, object) |> render_llm_response()
      else
        assigns |> render_llm_response_fallback()
      end}
    </div>
    """
  end

  # Sandbox eval completed
  defp event_row(%{event: %{type: :eval_stop}} = assigns) do
    ~H"""
    {if @event.data[:success] do
      assigns |> render_eval_success()
    else
      assigns |> render_eval_error()
    end}
    """
  end

  # Catch-all for unknown event types
  defp event_row(assigns) do
    ~H"""
    <div class="flex gap-2 items-start text-sol-base00 py-0.5">
      <span class="shrink-0 w-16 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span>{inspect(@event.type)}</span>
    </div>
    """
  end

  # Sub-renders for complex events

  defp render_llm_response(assigns) do
    ~H"""
    <div class="flex-1">
      <span class={action_class(@object["action"])}>{@object["action"]}</span>
      <details :if={@object["code"] && @object["code"] != ""} class="mt-1.5">
        <summary class="cursor-pointer text-sol-base00 hover:text-sol-base02 text-xs">
          show code
        </summary>
        <pre class="mt-1.5 p-3 bg-sol-base2 rounded-lg overflow-x-auto whitespace-pre-wrap border border-sol-base1/20 highlight">{Helpers.highlight_elixir(@object["code"])}</pre>
      </details>
      <div
        :if={@object["action"] in ["return", "done"] && has_result?(@object["result"])}
        class="mt-1.5 p-3 bg-sol-green/8 border border-sol-green/20 rounded-lg"
      >
        <span class="text-sol-base02">{extract_response(@object["result"])}</span>
      </div>
    </div>
    """
  end

  defp render_llm_response_fallback(assigns) do
    ~H"""
    <span class="text-sol-base00">(response)</span>
    """
  end

  defp render_eval_success(assigns) do
    has_error = error_result?(assigns.event.data[:result])
    assigns = assign(assigns, :has_error, has_error)

    ~H"""
    <div class="flex gap-2 items-start py-0.5">
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
      <span class={if @has_error, do: "text-sol-red", else: "text-sol-green"}>
        {if @has_error, do: "✗", else: "⚡"}
      </span>
      <div class="flex-1">
        <pre class={[
          "p-3 rounded-lg overflow-x-auto whitespace-pre-wrap text-xs",
          if(@has_error,
            do: "bg-sol-red/8 border border-sol-red/20 text-sol-red",
            else: "bg-sol-base2 border border-sol-base1/20 text-sol-base01"
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
      <span class="shrink-0 w-16 text-sol-base00 tabular-nums">{format_ts(@event.timestamp)}</span>
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

  defp action_class("eval_and_continue"), do: "text-sol-blue"
  defp action_class("eval_and_complete"), do: "text-sol-green"
  defp action_class("return"), do: "text-sol-green font-semibold"
  defp action_class("done"), do: "text-sol-base00"
  defp action_class(_), do: "text-sol-base00"

  defp format_message_result(result) when is_binary(result), do: result
  defp format_message_result(result), do: inspect(result, pretty: true, limit: 200)

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
end
