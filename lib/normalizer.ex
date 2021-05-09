defmodule Normalizer do
  defguard is_literal(x)
           when is_integer(x) or
                  is_float(x) or
                  is_binary(x) or
                  is_atom(x)

  @doc """
  Converts the given string into a quoted expression following the same method
  as `Code.Formatter.to_algebra/2`.
  """
  def string_to_quoted(string, opts \\ []) do
    file = Keyword.get(opts, :file, "nofile")
    line = Keyword.get(opts, :line, 1)
    charlist = String.to_charlist(string)

    tokenizer_options = [
      unescape: false,
      warn_on_unnecessary_quotes: false
    ]

    parser_options = [
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true
    ]

    with {:ok, tokens} <- :elixir.string_to_tokens(charlist, line, 1, file, tokenizer_options),
         {:ok, forms} <- :elixir.tokens_to_quoted(tokens, file, parser_options) do
      forms
    end
  end

  def quoted_to_string(quoted, _comments \\ []) do
    {:ok, doc} = Formatter.quoted_to_algebra(quoted)

    Inspect.Algebra.format(doc, 80)
    |> IO.iodata_to_binary()
  end

  @doc """
  Wraps literals in the quoted expression to conform to the AST format expected
  by the formatter.
  """
  def normalize(quoted) do
    normalize(quoted, line: 1)
  end

  defp normalize({:__block__, _, [literal]} = quoted, _parent_meta) when is_literal(literal) do
    quoted
  end

  defp normalize({:__block__, meta, args} = quoted, _parent_meta) do
    if Keyword.has_key?(meta, :format) do
      quoted
    else
      {:__block__, meta, Enum.map(args, &normalize(&1, meta))}
    end
  end

  # Skip aliases so the module segment atoms don't get wrapped
  defp normalize({:__aliases__, _, _} = quoted, _parent_meta) do
    quoted
  end

  # Skip qualified tuples left hand side
  defp normalize({:., _, [_, :{}]} = quoted, _parent_meta) do
    quoted
  end

  # foo[:bar]
  defp normalize({:., _, [Access, :get]} = quoted, _parent_meta) do
    quoted
  end

  # Only normalize the left side of the dot operator
  defp normalize({:., meta, [left, right]}, _parent_meta) do
    {:., meta, [normalize(left, meta), right]}
  end

  defp normalize([{:->, _, _} | _] = quoted, parent_meta) do
    Enum.map(quoted, &normalize(&1, parent_meta))
  end

  # left -> right
  defp normalize({:->, meta, [left, right]}, _parent_meta) do
    left = Enum.map(left, &normalize(&1, meta))
    right = normalize(right, meta)
    {:->, meta, [left, right]}
  end

  # Maps
  defp normalize({:%{}, meta, args}, _parent_meta) do
    args = Enum.map(args, &normalize(&1, meta))

    args =
      case args do
        # Unwrap the right hand side if we're in an update syntax
        [{:|, pipe_meta, [left, {_, _, [right]}]}] ->
          [{:|, pipe_meta, [left, right]}]

        # Unwrap args so we have 2-tuples instead of blocks
        [{_, _, args}] ->
          args

        args ->
          args
      end

    {:%{}, meta, args}
  end

  # If a keyword list is an argument of a guard, we need to drop the block
  # wrapping
  defp normalize({:when, meta, args} = _quoted, _parent_meta) do
    args =
      Enum.map(args, fn
        arg when is_list(arg) ->
          {_, _, [arg]} = normalize(arg, meta)
          arg

        arg ->
          normalize(arg, meta)
      end)

    {:when, meta, args}
  end

  # Calls
  defp normalize({form, meta, args}, _parent_meta) when is_list(args) do
    # Only normalize the form if it's a qualified call
    form =
      if is_atom(form) do
        form
      else
        normalize(form, meta)
      end

    cond do
      Keyword.has_key?(meta, :do) ->
        {last_arg, leading_args} = List.pop_at(args, -1)

        last_arg =
          Enum.map(last_arg, fn {tag, block} ->
            block = normalize(block, meta)

            block =
              case block do
                {_, _, [[{:->, _, _} | _] = block]} -> block
                block -> block
              end

            # Only wrap the tag if it isn't already wrapped
            tag =
              case tag do
                {:__block__, _, _} -> tag
                _ -> {:__block__, [line: meta[:line]], [tag]}
              end

            {tag, block}
          end)

        # {_, _, last_arg} = normalize(last_arg, meta)
        {_, _, [leading_args]} = normalize(leading_args, meta)

        {form, meta, leading_args ++ [last_arg]}

      true ->
        args = Enum.map(args, &normalize(&1, meta))

        {form, meta, args}
    end
  end

  # Strings
  defp normalize(x, parent_meta) when is_binary(x) do
    meta = [
      line: parent_meta[:line],
      token: Macro.to_string(x)
    ]

    {:__block__, meta, [x]}
  end

  # Integers, floats, atoms
  defp normalize(x, parent_meta) when is_literal(x) do
    meta = [line: parent_meta[:line]]

    meta =
      if not is_atom(x) do
        Keyword.put(meta, :token, Macro.to_string(x))
      else
        meta
      end

    meta =
      if not is_nil(parent_meta[:format]) do
        Keyword.put(meta, :format, parent_meta[:format])
      else
        meta
      end

    {:__block__, meta, [x]}
  end

  # 2-tuples
  defp normalize({left, right}, parent_meta) do
    meta = [line: parent_meta[:line]]

    left_parent_meta =
      if is_atom(left) do
        Keyword.put(parent_meta, :format, :keyword)
      else
        meta
      end

    {:__block__, meta,
     [
       {normalize(left, left_parent_meta), normalize(right, parent_meta)}
     ]}
  end

  # Lists
  defp normalize(list, parent_meta) when is_list(list) do
    if !Enum.empty?(list) and List.ascii_printable?(list) do
      # It's a charlist
      {:__block__, [line: parent_meta[:line], delimiter: "'"], [list]}
    else
      meta = [line: parent_meta[:line], closing: [line: parent_meta[:line]]]

      args = normalize_list_elements(list, parent_meta)

      {:__block__, meta, [args]}
    end
  end

  # Everything else
  defp normalize(quoted, _parent_meta) do
    quoted
  end

  defp normalize_list_elements(elems, parent_meta, keyword? \\ false)

  defp normalize_list_elements([[{_, _, [{_, _}]}] = first | rest], parent_meta, keyword?) do
    # Skip already normalized 2-tuples
    [first | normalize_list_elements(rest, parent_meta, keyword?)]
  end

  defp normalize_list_elements([{left, right} | rest], parent_meta, keyword?) do
    keyword? =
      if not keyword? do
        Enum.empty?(rest) or keyword?(rest)
      else
        keyword?
      end

    pair =
      if keyword? do
        {_, _, [{left, right}]} = normalize({left, right})
        left = Macro.update_meta(left, &Keyword.put(&1, :format, :keyword))
        {left, right}
      else
        left = normalize(left)
        right = normalize(right)
        {:__block__, [line: parent_meta[:line]], [{left, right}]}
      end

    [pair | normalize_list_elements(rest, parent_meta, keyword?)]
  end

  defp normalize_list_elements([first | rest], parent_meta, keyword?) do
    [normalize(first, parent_meta) | normalize_list_elements(rest, parent_meta, keyword?)]
  end

  defp normalize_list_elements([], _parent_meta, _keyword?) do
    []
  end

  defp keyword?([{_, _} | list]), do: keyword?(list)
  defp keyword?(rest), do: rest == []
end
