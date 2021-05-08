defmodule NormalizeTest do
  use ExUnit.Case

  @parser_opts [
    token_metadata: true
  ]

  defp doc_to_binary(doc) do
    doc
    |> Inspect.Algebra.format(80)
    |> IO.iodata_to_binary()
  end

  defp format_string(string) do
    string
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  defmacro assert_same(good) do
    quote bind_quoted: [good: good] do
      good = format_string(good)

      quoted = Code.string_to_quoted!(good, @parser_opts)

      quoted_wrapped =
        Code.string_to_quoted!(
          good,
          @parser_opts ++
            [
              literal_encoder: &{:ok, {:__block__, &2, [&1]}}
            ]
        )

      normalized = Normalizer.normalize(quoted)
      normalized_wrapped = Normalizer.normalize(quoted_wrapped)

      {:ok, doc} = Formatter.quoted_to_algebra(normalized)
      {:ok, doc_wrapped} = Formatter.quoted_to_algebra(normalized_wrapped)

      output = doc_to_binary(doc)
      output_wrapped = doc_to_binary(doc_wrapped)

      assert good == output
      assert good == output_wrapped
    end
  end

  describe "normalizes" do
    test "integers" do
      normalized = Normalizer.normalize(10)

      assert {:__block__, meta, [10]} = normalized
      assert Keyword.has_key?(meta, :line)
      assert meta[:token] == "10"
    end

    test "floats" do
      normalized = Normalizer.normalize(10.42)

      assert {:__block__, meta, [10.42]} = normalized
      assert Keyword.has_key?(meta, :line)
      assert meta[:token] == "10.42"
    end

    test "atoms" do
      normalized = Normalizer.normalize(:hello)

      assert {:__block__, meta, [:hello]} = normalized
      assert Keyword.has_key?(meta, :line)
    end

    test "strings" do
      normalized = Normalizer.normalize("hello world")

      assert {:__block__, meta, ["hello world"]} = normalized
      assert Keyword.has_key?(meta, :line)
      assert meta[:token] == ~s["hello world"]
    end

    test "two elements tuples" do
      normalized = Normalizer.normalize({:foo, :bar})

      assert {:__block__, meta,
              [
                {
                  {:__block__, left_meta, [:foo]},
                  {:__block__, right_meta, [:bar]}
                }
              ]} = normalized

      assert Keyword.has_key?(meta, :line)
      assert Keyword.has_key?(left_meta, :line)
      assert Keyword.has_key?(right_meta, :line)
    end

    test "regular lists" do
      normalized = Normalizer.normalize([1, 2, 3])

      assert {:__block__, meta,
              [
                [
                  {:__block__, first_meta, [1]},
                  {:__block__, second_meta, [2]},
                  {:__block__, third_meta, [3]}
                ]
              ]} = normalized

      metas = [meta, first_meta, second_meta, third_meta]

      assert Enum.all?(metas, &Keyword.has_key?(&1, :line))

      assert first_meta[:token] == "1"
      assert second_meta[:token] == "2"
      assert third_meta[:token] == "3"
    end
  end

  describe "normalizes compositions of" do
    test "keyword lists" do
      quoted = Code.string_to_quoted!("[a: :b, c: :d]")
      normalized = Normalizer.normalize(quoted)

      assert {:__block__, meta,
              [
                [
                  {{:__block__, first_key_meta, [:a]}, {:__block__, _, [:b]}},
                  {{:__block__, second_key_meta, [:c]}, {:__block__, _, [:d]}}
                ]
              ]} = normalized

      assert Keyword.has_key?(meta, :line)
      assert get_in(meta, [:closing, :line]) |> is_integer()
      assert first_key_meta[:format] == :keyword
      assert second_key_meta[:format] == :keyword
    end

    test "mixed keyword lists" do
      assert_same("[1, 2, a: :b, c: :d]")
      assert_same("[1, {:foo, :bar}, 5, c: :d]")
    end

    test "do blocks" do
      sample = """
      def foo(bar) do
        :ok
      end
      """

      assert_same(sample)
    end

    test "conds and cases" do
      sample = """
      case something do
        foo -> bar
        baz -> qux
      end
      cond do
        foo? -> :bar
        true -> :ok
      end
      """

      assert_same(sample)
    end

    test "anonymous functions" do
      sample = """
      fn
        foo -> :bar
        baz -> 42
      end
      """

      assert_same(sample)
    end

    test "anonymous functions with multiple arguments" do
      sample = """
      fn
        foo, bar -> :bar
        baz, qux, :foo -> 42
      end
      """

      assert_same(sample)
    end

    test "functions with guards" do
      sample = """
      def foo(bar, baz) when not is_nil(baz) do
        :test
      end
      """

      assert_same(sample)
    end

    test "functions with optional argument" do
      sample = """
      def foo(bar, opts \\\\ []) do
        :test
      end
      """

      assert_same(sample)
    end

    test "function with no arguments" do
      sample = """
      defmodule Foo do
        :foo
        :bar
      end
      """

      assert_same(sample)
    end

    test "guard definitions" do
      sample = """
      defguard is_number(x) when is_integer(x) or is_float(x)
      """

      assert_same(sample)
    end

    test "function with const pattern matching arg" do
      sample = """
      def foo([arg | args]) do
        :foo
        :test
      end
      """

      assert_same(sample)
    end
  end

  test "calls to erlang modules" do
    sample = """
    :erlang.iolist_to_binary(iolist)
    """

    assert_same(sample)
  end

  test "access syntax" do
    sample = """
    foo[:bar]
    foo[bar]
    foo.bar[baz]
    """

    assert_same(sample)
  end

  test "maps" do
    sample = """
    %{foo: bar}
    """

    assert_same(sample)
  end

  test "map update syntax" do
    sample = """
    %{base | foo: bar}
    %{base | nested: %{foo: bar}}
    """

    assert_same(sample)
  end
end
