defmodule Comments do

  def get_file_comments(file_path) do
    source = File.read!(file_path)
    get_comments(source)
  end
  def get_comments(source) do
    charlist = String.to_charlist(source)

    Process.put(:code_formatter_comments, [])

    tokenizer_options = [
      unescape: false,
      preserve_comments: &preserve_comments/5,
      warn_on_unnecessary_quotes: false
    ]

    {:ok, tokens} = :elixir.string_to_tokens(charlist, 1, 1, "nofile", tokenizer_options)

    Process.get(:code_formatter_comments)
  after
    Process.delete(:code_formatter_comments)
  end

  defp preserve_comments(line, _column, tokens, comment, rest) do
    comments = Process.get(:code_formatter_comments)
    comment = {
      line,
      {previous_eol(tokens), next_eol(rest, 0)},
      format_comment(comment, [])
    }
    Process.put(:code_formatter_comments, [comment | comments])
  end

  defp next_eol('\s' ++ rest, count), do: next_eol(rest, count)
  defp next_eol('\t' ++ rest, count), do: next_eol(rest, count)
  defp next_eol('\n' ++ rest, count), do: next_eol(rest, count + 1)
  defp next_eol('\r\n' ++ rest, count), do: next_eol(rest, count + 1)
  defp next_eol(_, count), do: count

  defp previous_eol([{token, {_, _, count}} | _])
       when token in [:eol, :",", :";"] and count > 0 do
    count
  end

  defp previous_eol([]), do: 1
  defp previous_eol(_), do: nil

  defp format_comment('##' ++ rest, acc), do: format_comment([?# | rest], [?# | acc])

  defp format_comment('#!', acc), do: reverse_to_string(acc, '#!')
  defp format_comment('#! ' ++ _ = rest, acc), do: reverse_to_string(acc, rest)
  defp format_comment('#!' ++ rest, acc), do: reverse_to_string(acc, [?#, ?!, ?\s, rest])

  defp format_comment('#', acc), do: reverse_to_string(acc, '#')
  defp format_comment('# ' ++ _ = rest, acc), do: reverse_to_string(acc, rest)
  defp format_comment('#' ++ rest, acc), do: reverse_to_string(acc, [?#, ?\s, rest])

  defp reverse_to_string(acc, prefix) do
    acc |> Enum.reverse(prefix) |> List.to_string()
  end

  # Comments merging

  defp merge_comments({_, meta, _} = ast, comments) do
    {comments, rest} = gather_comments_for_line(comments, line(ast))

    ast = put_comments(ast, :leading_comments, comments)
    {ast, rest}
  end
  defp merge_comments(ast, comments), do: {ast, comments}

  defp merge_leftovers({_, meta, _} = ast, comments) do
    end_line = Keyword.get(meta, :end, [line: 0])[:line]

    {comments, rest} = gather_comments_for_line(comments, end_line)
    ast = put_comments(ast, :trailing_comments, comments)

    {ast, rest}
  end
  defp merge_leftovers(ast, comments), do: {ast, comments}

  defp line({_, meta, _}), do: meta[:line] || 0
  defp line(_), do: 0

  defp gather_comments_for_line(comments, line) do
    {comments, rest} = Enum.reduce(comments, {[], []}, fn
      {comment_line, text} = comment, {comments, rest} ->
        if comment_line <= line do
          {[text | comments], rest}
        else
          {comments, [comment | rest]}
        end
    end)
    comments = Enum.reverse(comments)
    rest = Enum.reverse(rest)

    {comments, rest}
  end

  defp put_comments(ast, key, comments) do
    meta =
      elem(ast, 1)
      |> Keyword.put(key, comments)

    put_elem(ast, 1, meta)
  end

  #{ast, leftovers} = Macro.prewalk(ast, comments, &merge_comments/2)
  #{ast, leftovers} = Macro.postwalk(ast, leftovers, &merge_leftovers/2)

  #if Enum.empty?(leftovers) do
  #  ast
  #else
  #  leftovers = Enum.map(leftovers, &elem(&1, 1))
  #  {:__block__, [trailing_comments: leftovers], [ast]}
  #end
end
