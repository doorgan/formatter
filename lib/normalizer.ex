defmodule Normalizer do

  defguard is_literal(x) when
    is_integer(x)
    or is_float(x)
    or is_binary(x)
    or is_atom(x)

  def string_to_quoted(string, opts \\ []) do
    file = Keyword.get(opts, :file, "nofile")
    line = Keyword.get(opts, :line, 1)
    charlist = String.to_charlist(string)

    tokenizer_options = [
      unescape: false,
      warn_on_unnecessary_quotes: false
    ]

    parser_options = [
      literal_encoder: &{:ok, {:__block__, [literal?: true] ++ &2, [&1]}},
      token_metadata: true
    ]

    with {:ok, tokens} <- :elixir.string_to_tokens(charlist, line, 1, file, tokenizer_options),
         {:ok, forms} <- :elixir.tokens_to_quoted(tokens, file, parser_options) do
      forms
    end
  end

  @doc """
  Wraps literals in the quoted expression to conform to the AST format expected
  by the formatter.
  """
  def normalize(quoted) do
    quoted = maybe_normalize_literal(quoted, line: 1)

    Macro.prewalk(quoted, fn
      {:__aliases__, _, _} = node -> node
      {:., _, [_, :{}]} = node -> node
      {form, meta, args} = node when is_list(args) ->
        cond do
          meta[:literal?] ->
            node

          Keyword.has_key?(meta, :do) ->
            {last_arg, leading_args} = List.pop_at(args, -1)

            {_, _, last_arg} = maybe_normalize_literal(last_arg, meta)

            {form, meta, leading_args ++ last_arg}

          true ->
            args = Enum.map(args, &maybe_normalize_literal(&1, meta))

            {form, meta, args}
        end
      node -> node
    end)
  end

  # Strings
  defp maybe_normalize_literal(x, parent_meta) when is_binary(x) do
    {:__block__, [literal?: true, line: parent_meta[:line], token: Macro.to_string(x), delimiter: ~s["]], [x]}
  end

  # Integers, floats, atoms
  defp maybe_normalize_literal(x, parent_meta) when is_literal(x) do
    meta = [literal?: true, line: parent_meta[:line], token: Macro.to_string(x)]
        meta =
          if not is_nil(parent_meta[:format]) do
            Keyword.put(meta, :format, parent_meta[:format])
          else
            meta
          end
        {:__block__, meta, [x]}
  end

  # 2-tuples
  defp maybe_normalize_literal({left, right}, parent_meta) do
    meta = [literal?: true, line: parent_meta[:line]]
        left_parent_meta =
          if is_atom(left) do
            Keyword.put(parent_meta, :format, :keyword)
          else
            meta
          end

        {:__block__, meta, [
          {maybe_normalize_literal(left, left_parent_meta),
           maybe_normalize_literal(right, parent_meta)}
        ]}
  end

  # Lists
  defp maybe_normalize_literal(x, parent_meta) when is_list(x) do
    cond do
      keyword?(x) ->
        meta = [literal?: true, line: parent_meta[:line], closing: [line: parent_meta[:line]]]
        {:__block__, meta, [Enum.map(x, fn
          {left, right} ->
            left_parent_meta =
              if is_atom(left) and not Keyword.has_key?(parent_meta, :do) do
                Keyword.put(parent_meta, :format, :keyword)
              else
                meta
              end

          {maybe_normalize_literal(left, left_parent_meta),
          maybe_normalize_literal(right, parent_meta)}
        end)]}

      true ->
        {:__block__, [literal?: true, line: parent_meta[:line], closing: [line: parent_meta[:line]]], [Enum.map(x, &maybe_normalize_literal(&1, parent_meta))]}
    end
  end

  # Everything else
  defp maybe_normalize_literal(x, _parent_meta) do
    x
  end

  defp keyword?([{_, _} | list]), do: keyword?(list)
  defp keyword?(rest), do: rest == []
end
