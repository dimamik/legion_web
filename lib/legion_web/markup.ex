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
  """
  @spec markdown(String.t()) :: Phoenix.HTML.safe()
  def markdown(text) when is_binary(text) do
    text
    |> Earmark.as_html!(code_class_prefix: "language-")
    |> highlight_code_blocks()
    |> Phoenix.HTML.raw()
  end

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
