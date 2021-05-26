defmodule AST do
  def from_string(source) do
    {quoted, comments} =
      Code.string_to_quoted_with_comments!(source,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        unescape: false
      )

    Comments.merge_comments(quoted, comments)
  end

  def format_ast(quoted) do
    {quoted, comments} = Comments.extract_comments(quoted)

    quoted
    |> Code.quoted_to_algebra(comments: comments)
    |> Inspect.Algebra.format(98)
    |> IO.iodata_to_binary()
  end

  def postwalk(quoted, fun) do
    {quoted, _} =
      Macro.postwalk(quoted, %{line_correction: 0}, fn
        {_, _, _} = quoted, state ->
          quoted = Macro.update_meta(quoted, &correct_lines(&1, state.line_correction))
          fun.(quoted, state)

        quoted, state ->
          fun.(quoted, state)
      end)

    quoted
  end

  def correct_lines(meta, line_correction) do
    meta =
      if line = meta[:line] do
        Keyword.put(meta, :line, line + line_correction)
      else
        meta ++ [line: 1]
      end

    corrections =
      Enum.map(~w[closing do end end_of_expression]a, &correct_line(meta, &1, line_correction))

    Enum.reduce(corrections, meta, fn correction, meta ->
      Keyword.merge(meta, correction)
    end)
  end

  defp correct_line(meta, key, line_correction) do
    with value when value != [] <- Keyword.get(meta, key, []) do
      value = put_in(value, [:line], value[:line] + line_correction)
      [{key, value}]
    else
      _ -> meta
    end
  end
end
