defmodule Examples.MultiAlias do
  @doc """
  Walks the source code and expands instances of multi alias syntax like
  ```elixir
  alias Foo.{Bar, Baz.Qux}
  ```
  to individual aliases:
  ```elixir
  alias Foo.Bar
  alias Foo.Baz.Qux
  ```

  It also preserves the comments:
  ```elixir
  # Multi alias example
  alias Foo.{ # Opening the multi alias
    Bar, # Here is Bar
    # Here come the Baz
    Baz.Qux # With a Qux!
  }
  ```
  ```elixir
  # Multi alias example
  # Opening the multi alias
  # Here is Bar
  alias Foo.Bar
  # Here come the Baz
  # With a Qux!
  alias Foo.Baz.Qux
  ```
  """
  def fix(source) do
    {quoted, comments} = Formatter.string_to_quoted_with_comments(source)

    quoted = Comments.merge_comments(quoted, comments)

    quoted =
      Macro.prewalk(quoted, fn
        {:alias, meta, [{{:., _, [_, :{}]}, _, _}]} = quoted ->
          args = expand_multi_alias(quoted, [])
          {:__block__, [line: meta[:line]], args}

        {:__block__, meta, args} ->
          args = Enum.reduce(args, [], &expand_multi_alias/2)
          {:__block__, meta, args}

        quoted ->
          quoted
      end)

    {quoted, comments} = Comments.extract_comments(quoted)

    quoted = Normalizer.normalize(quoted)

    {:ok, doc} = Formatter.quoted_to_algebra(quoted, comments: comments)

    doc |> Inspect.Algebra.format(98) |> IO.iodata_to_binary()
  end

  defp expand_multi_alias(
         {:alias, alias_meta,
          [
            {{:., _, [left, :{}]}, _, right}
          ]},
         args
       ) do
    {_, _, base} = left

    aliases =
      right
      |> Enum.with_index()
      |> Enum.map(fn {aliases, index} ->
        {_, meta, segments} = aliases
        line = alias_meta[:line] + index
        meta = Keyword.put(meta, :line, line)

        meta =
          if index == 0 do
            Keyword.update!(meta, :leading_comments, &(&1 ++ alias_meta[:leading_comments]))
          else
            meta
          end

        {:alias, meta, [{:__aliases__, [line: line], base ++ segments}]}
      end)

    args ++ aliases
  end

  defp expand_multi_alias(quoted, args), do: args ++ [quoted]
end
