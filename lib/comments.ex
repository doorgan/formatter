defmodule Comments do

  @doc """
  Merges the comments into the given quoted expression.

  The comments are inserted into the metadata of their closest node. Comments in
  the same line of before a node are inserted into the `:leading_comments` field
  while comments that are right before an `end` keyword are inserted into the
  `:trailing_comments` field.
  """
  def merge_comments(quoted, comments) do
    {quoted, leftovers} = Macro.prewalk(quoted, comments, &do_merge_comments/2)
    {quoted, leftovers} = Macro.postwalk(quoted, leftovers, &merge_leftovers/2)

    if Enum.empty?(leftovers) do
      quoted
    else
      {:__block__, [trailing_comments: leftovers], [quoted]}
    end
  end

  defp do_merge_comments({_, _meta, _} = quoted, comments) do
    {comments, rest} = gather_comments_for_line(comments, line(quoted))

    quoted = put_comments(quoted, :leading_comments, comments)
    {quoted, rest}
  end

  defp do_merge_comments(quoted, comments), do: {quoted, comments}

  defp merge_leftovers({_, meta, _} = quoted, comments) do
    end_line = Keyword.get(meta, :end, line: 0)[:line]

    {comments, rest} = gather_comments_for_line(comments, end_line)
    quoted = put_comments(quoted, :trailing_comments, comments)

    {quoted, rest}
  end

  defp merge_leftovers(quoted, comments), do: {quoted, comments}

  defp line({_, meta, _}), do: meta[:line] || 0
  defp line(_), do: 0

  defp gather_comments_for_line(comments, line) do
    {comments, rest} =
      Enum.reduce(comments, {[], []}, fn
        {comment_line, _, _} = comment, {comments, rest} ->
          if comment_line <= line do
            {[comment | comments], rest}
          else
            {comments, [comment | rest]}
          end
      end)

    rest = Enum.reverse(rest)

    {comments, rest}
  end

  defp put_comments(quoted, key, comments) do
    meta =
      elem(quoted, 1)
      |> Keyword.put(key, comments)

    put_elem(quoted, 1, meta)
  end

  @doc """
  Does the opposite of `merge_comments`, it extracts the comments from the
  quoted expression and returns both as a `{quoted, comments}` tuple.
  """
  def extract_comments(quoted) do
    Macro.postwalk(quoted, [], fn
      {_, meta, _} = quoted, acc ->
        line = meta[:line] || 1

        leading_comments =
          Keyword.get(meta, :leading_comments, [])
          |> Enum.map(fn {_, eols, text} ->
            {line, eols, text}
          end)
          |> Enum.reverse()

        acc = if Enum.empty?(leading_comments), do: acc, else: acc ++ leading_comments

        trailing_comments =
          Keyword.get(meta, :trailing_comments, [])
          |> Enum.map(fn {comment_line, eols, text} ->
            # Preserve original commet line if parent node does not have
            # ending line information
            end_line = meta[:end][:line] || meta[:closing][:line] || comment_line
            {end_line, eols, text}
          end)
          |> Enum.reverse()

        acc = if Enum.empty?(trailing_comments), do: acc, else: acc ++ trailing_comments

        quoted =
          Macro.update_meta(quoted, fn meta ->
            meta
            |> Keyword.delete(:leading_comments)
            |> Keyword.delete(:trailing_comments)
          end)

        {quoted, acc}

      other, acc ->
        {other, acc}
    end)
  end
end
