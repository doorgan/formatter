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
      assert meta[:token] == ":hello"
    end

    test "strings" do
      normalized = Normalizer.normalize("hello world")

      assert {:__block__, meta, ["hello world"]} = normalized
      assert Keyword.has_key?(meta, :line)
      assert meta[:token] == ~s["hello world"]
    end

    test "two elements tuples" do
      normalized = Normalizer.normalize({:foo, :bar})

      assert {:__block__, meta, [{
        {:__block__, left_meta, [:foo]},
        {:__block__, right_meta, [:bar]}
      }]} = normalized

      assert Keyword.has_key?(meta, :line)
      assert Keyword.has_key?(left_meta, :line)
      assert Keyword.has_key?(right_meta, :line)
      assert left_meta[:token] == ":foo"
      assert right_meta[:token] == ":bar"
    end

    test "regular lists" do
      normalized = Normalizer.normalize([1, 2, 3])

      assert {:__block__, meta, [
        [
          {:__block__, first_meta, [1]},
          {:__block__, second_meta, [2]},
          {:__block__, third_meta, [3]},
        ]
      ]} = normalized

      metas = [meta, first_meta, second_meta, third_meta]

      assert Enum.all?(metas, &Keyword.has_key?(&1, :line))

      assert first_meta[:token] == "1"
      assert second_meta[:token] == "2"
      assert third_meta[:token] == "3"
    end
  end

  describe "normalizes compositions" do
    test "keyword list" do
      quoted = Code.string_to_quoted!("[a: :b, c: :d]")
      normalized = Normalizer.normalize(quoted)

      assert {:__block__, meta, [[
        {{:__block__, first_key_meta, [:a]},
         {:__block__, _, [:b]}},
        {{:__block__, second_key_meta, [:c]},
         {:__block__, _, [:d]}},
      ]]} = normalized

      assert Keyword.has_key?(meta, :line)
      assert get_in(meta, [:closing, :line]) |> is_integer()
      assert first_key_meta[:format] == :keyword
      assert second_key_meta[:format] == :keyword
    end

    test "mixed keyword list" do
      sample = ~s([1, 2, a: :b])
      quoted = Code.string_to_quoted!(sample) |> IO.inspect
      normalized = Normalizer.normalize(quoted)

      {:ok, doc} = Formatter.quoted_to_algebra(normalized)

      output = doc_to_binary(doc)

      assert sample == output
    end

    test "do blocks" do
      sample = """
      def foo(bar) do
        :ok
      end
      """
      |> String.trim()

      quoted = Code.string_to_quoted!(sample, @parser_opts)
      normalized = Normalizer.normalize(quoted)

      {:ok, doc} = Formatter.quoted_to_algebra(normalized)

      output = doc_to_binary(doc)

      assert sample == output
    end

    test "mixed keyword lists" do
      sample = """
      def foo(bar) do
        [1, foo: :bar]
        :ok
      end
      """ |> String.trim()

      quoted = Code.string_to_quoted!(sample, @parser_opts)

      normalized = Normalizer.normalize(quoted)

      {:ok, doc} = Formatter.quoted_to_algebra(normalized)

      output = doc_to_binary(doc)

      assert sample == output
    end
  end
end
