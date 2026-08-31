defmodule LegionWeb.Markup do
  @moduledoc """
  Turns markdown and source code into safe HTML for the dashboard.

  Languages are addressed by their `Makeup.Registry` name (`"elixir"`,
  `"lua"`, ...). Any lexer registered with Makeup works; a language with no
  registered lexer degrades to HTML-escaped plaintext rather than raising.
  """

  @doc """
  Highlights `code` as `language`, returning safe HTML for use inside a
  `<pre class="highlight">` or `<code class="highlight">`.

  Unknown or `nil` `language` returns the escaped code with no markup.
  """
  @spec highlight(String.t(), String.t() | nil) :: Phoenix.HTML.safe()
  def highlight(code, language) when is_binary(code) do
    case language && Makeup.Registry.get_lexer_by_name(language) do
      {lexer, opts} ->
        Makeup.highlight_inner_html(code, lexer: lexer, lexer_options: opts)

      _ ->
        code |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
    |> Phoenix.HTML.raw()
  end

  @doc """
  Renders markdown to safe HTML, highlighting every fenced code block whose
  info string names a registered lexer. Other fenced blocks are left as
  Earmark emitted them.

  Raw HTML blocks in the markdown are escaped and rendered as text, so
  markdown from an LLM or a user cannot inject markup into the dashboard.
  Malformed markdown renders best-effort instead of raising.
  """
  @spec markdown(String.t()) :: Phoenix.HTML.safe()
  def markdown(text) when is_binary(text) do
    {_status, ast, _messages} = Earmark.Parser.as_ast(text, code_class_prefix: "language-")

    ast
    |> escape_raw_html()
    |> Earmark.Transform.transform()
    |> highlight_code_blocks()
    |> Phoenix.HTML.raw()
  end

  # Earmark passes raw HTML blocks through verbatim, which would let markdown
  # inject `<script>` and friends. Replace every verbatim node with a plain
  # text node so `Earmark.Transform` escapes it.
  defp escape_raw_html(ast) when is_list(ast), do: Enum.map(ast, &escape_raw_html/1)

  defp escape_raw_html({tag, attrs, children, %{verbatim: true}}) do
    raw_text(tag, attrs, children)
  end

  defp escape_raw_html({tag, attrs, children, meta}) do
    {tag, attrs, escape_raw_html(children), meta}
  end

  defp escape_raw_html(other), do: other

  defp raw_text(tag, attrs, children) do
    attrs_text = Enum.map_join(attrs, "", fn {name, value} -> ~s( #{name}="#{value}") end)
    inner = Enum.map_join(children, "\n", &raw_child_text/1)

    case inner do
      "" -> "<#{tag}#{attrs_text}>"
      _ -> "<#{tag}#{attrs_text}>\n#{inner}\n</#{tag}>"
    end
  end

  defp raw_child_text(child) when is_binary(child), do: child
  defp raw_child_text({tag, attrs, children, _meta}), do: raw_text(tag, attrs, children)

  # Earmark emits `<code class="lua language-lua">` for a ```lua fence.
  @code_block_re ~r/<code class="[\w-]+ language-([\w-]+)">(.*?)<\/code>/s

  defp highlight_code_blocks(html) do
    Regex.replace(@code_block_re, html, fn match, language, code ->
      case Makeup.Registry.get_lexer_by_name(language) do
        nil ->
          match

        _ ->
          {:safe, highlighted} = code |> unescape_html() |> highlight(language)
          ~s(<code class="language-#{language} highlight">#{highlighted}</code>)
      end
    end)
  end

  defp unescape_html(html) do
    html
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end
end
