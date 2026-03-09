defmodule LegionWeb.Helpers do
  @moduledoc false

  def module_name(module) when is_atom(module) do
    module |> Module.split() |> List.last()
  end

  def full_module_name(module) when is_atom(module) do
    module |> to_string() |> String.replace_prefix("Elixir.", "")
  end

  def relative_time(ms) when is_integer(ms) do
    diff = System.system_time(:millisecond) - ms

    cond do
      diff < 1_000 -> "just now"
      diff < 60_000 -> "#{div(diff, 1_000)}s ago"
      diff < 3_600_000 -> "#{div(diff, 60_000)}m ago"
      true -> "#{div(diff, 3_600_000)}h ago"
    end
  end

  def relative_time(nil), do: "—"

  def format_duration(started_at, finished_at)
      when is_integer(started_at) and is_integer(finished_at) do
    format_ms(finished_at - started_at)
  end

  def format_duration(_, _), do: nil

  def format_ms(ms) when ms >= 0 do
    cond do
      ms < 1_000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1_000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  def format_ms(_), do: nil

  def status_class(:running), do: "bg-sol-green soft-pulse"
  def status_class(:idle), do: "bg-sol-blue"
  def status_class(:waiting_for_human), do: "bg-sol-yellow soft-pulse"
  def status_class(:done), do: "bg-sol-cyan"
  def status_class(:error), do: "bg-sol-red"
  def status_class(:dead), do: "bg-sol-red/70"
  def status_class(_), do: "bg-sol-base1"

  def status_label(:running), do: "running"
  def status_label(:idle), do: "idle"
  def status_label(:waiting_for_human), do: "waiting"
  def status_label(:done), do: "done"
  def status_label(:error), do: "error"
  def status_label(:dead), do: "failed"
  def status_label(other), do: to_string(other)

  def status_text_class(:running), do: "text-sol-green"
  def status_text_class(:idle), do: "text-sol-blue"
  def status_text_class(:waiting_for_human), do: "text-sol-yellow"
  def status_text_class(:done), do: "text-sol-cyan"
  def status_text_class(:error), do: "text-sol-red"
  def status_text_class(:dead), do: "text-sol-red"
  def status_text_class(_), do: "text-sol-base1"

  def truncate(str, max_len \\ 80)
  def truncate(nil, _), do: ""

  def truncate(str, max_len) when is_binary(str) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len) <> "…"
    else
      str
    end
  end

  def inspect_value(value, limit \\ 200) do
    value
    |> inspect(pretty: true, limit: 20)
    |> String.slice(0, limit)
  end

  def highlight_elixir(code) when is_binary(code) do
    code
    |> Makeup.highlight_inner_html(lexer: Makeup.Lexers.ElixirLexer)
    |> Phoenix.HTML.raw()
  end

  def agent_topic(run_id), do: "legion_web:agent:#{inspect(run_id)}"

  def encode_run_id(run_id) do
    run_id
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  def decode_run_id(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, binary} -> :erlang.binary_to_term(binary, [:safe])
      :error -> nil
    end
  rescue
    _ -> nil
  end
end
