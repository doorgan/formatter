defmodule NormalizeTest do
  use ExUnit.Case

  @parser_opts [
    token_metadata: true
  ]

  # @short_length [line_length: 10]
  @medium_length [line_length: 20]

  defp doc_to_binary(doc) do
    doc
    |> Inspect.Algebra.format(98)
    |> IO.iodata_to_binary()
  end

  defmacro assert_same(good, opts \\ []) do
    quote bind_quoted: [good: good, opts: opts] do
      good = format_string(good, opts)

      quoted = Code.string_to_quoted!(good, @parser_opts)

      encoder = &{:ok, {:__block__, &2, [&1]}}

      parser_options = @parser_opts ++ [literal_encoder: encoder]

      quoted_wrapped = Code.string_to_quoted!(good, parser_options)

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

  defp format_string(string, opts) do
    string
    |> Code.format_string!(opts)
    |> IO.iodata_to_binary()
  end

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

  test "charlists" do
    normalized = Normalizer.normalize('hello world')

    assert {:__block__, meta, ['hello world']} = normalized
    assert Keyword.has_key?(meta, :line)
    assert meta[:delimiter] == "'"
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

    assert [line: _] = meta[:closing]

    assert first_meta[:token] == "1"
    assert second_meta[:token] == "2"
    assert third_meta[:token] == "3"
  end

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

  test "list with keyword list as last element" do
    quoted = Code.string_to_quoted!("[1, {:a, :b}, 2, c: :d, e: :f]")
    normalized = Normalizer.normalize(quoted)

    assert {:__block__, _,
            [
              [
                {:__block__, _, [1]},
                {:__block__, _,
                 [
                   {
                     {:__block__, a_meta, [:a]},
                     {:__block__, _, [:b]}
                   }
                 ]},
                {:__block__, _, [2]},
                {{:__block__, c_meta, [:c]}, {:__block__, _, [:d]}},
                {{:__block__, e_meta, [:e]}, {:__block__, _, [:f]}}
              ]
            ]} = normalized

    refute a_meta[:format] == :keyword

    assert c_meta[:format] == :keyword
    assert e_meta[:format] == :keyword
  end

  test "keyword list in guard with ommited square brackets" do
    quoted = Code.string_to_quoted!("a when foo: :bar, baz: :qux")
    normalized = Normalizer.normalize(quoted)

    assert {:when, _,
            [
              {:a, _, _},
              [
                {{:__block__, _, [:foo]}, {:__block__, _, [:bar]}},
                {{:__block__, _, [:baz]}, {:__block__, _, [:qux]}}
              ]
            ]} = normalized
  end

  test "maps" do
    quoted = Code.string_to_quoted!("%{foo: :bar}")
    normalized = Normalizer.normalize(quoted)

    assert {:%{}, _,
            [
              {{:__block__, key_meta, [:foo]}, {:__block__, _, [:bar]}}
            ]} = normalized

    assert Keyword.get(key_meta, :format) == :keyword
  end

  test "map with update syntax" do
    quoted = Code.string_to_quoted!("%{base | foo: :bar}")
    normalized = Normalizer.normalize(quoted)

    assert {:%{}, _,
            [
              {:|, _,
               [
                 {:base, _, _},
                 [{{:__block__, key_meta, [:foo]}, {:__block__, _, [:bar]}}]
               ]}
            ]} = normalized

    assert Keyword.get(key_meta, :format) == :keyword
  end

  test "aliases are skipped" do
    quoted = Code.string_to_quoted!("Foo.Bar")
    normalized = Normalizer.normalize(quoted)

    assert quoted == normalized
  end

  test "`Access` in access syntax doesn't get wrapped" do
    quoted = Code.string_to_quoted!("foo[:bar]")
    normalized = Normalizer.normalize(quoted)

    assert {
             {:., _, [Access, :get]},
             _,
             [
               {:foo, _, _},
               {:__block__, _, [:bar]}
             ]
           } = normalized
  end

  test "Only the left side of a dot call is normalized" do
    quoted = Code.string_to_quoted!("foo.bar()")
    normalized = Normalizer.normalize(quoted)

    assert {{:., _, [{:foo, _, _}, :bar]}, _, []} = normalized
  end

  test "do blocks" do
    quoted =
      Code.string_to_quoted!("""
      case do
        :ok
      end
      """)

    normalized = Normalizer.normalize(quoted)

    assert {:case, _,
            [
              {:__block__, _,
               [
                 [
                   {{:__block__, _, [:do]}, {:__block__, _, [:ok]}}
                 ]
               ]}
            ]} = normalized
  end

  test "do block when token_metadata: true" do
    quoted =
      Code.string_to_quoted!(
        """
        case do
          :ok
        end
        """,
        token_metadata: true
      )

    normalized = Normalizer.normalize(quoted)

    assert {:case, meta,
            [
              [
                {{:__block__, _, [:do]}, {:__block__, _, [:ok]}}
              ]
            ]} = normalized

    assert [line: _] = Keyword.get(meta, :do)
    assert [line: _] = Keyword.get(meta, :end)
  end

  test "function with arguments and do block" do
    quoted =
      Code.string_to_quoted!("""
      foo(:bar) do
        :ok
      end
      """)

    normalized = Normalizer.normalize(quoted)

    assert {:foo, _,
            [
              {:__block__, _, [:bar]},
              {:__block__, _,
               [
                 [{{:__block__, _, [:do]}, {:__block__, _, [:ok]}}]
               ]}
            ]} = normalized
  end

  test "do, else, catch, rescue and after blocks" do
    quoted =
      Code.string_to_quoted!("""
      foo do
        :in_do
      else
        :in_else
      catch
        :in_catch
      rescue
        :in_rescue
      after
        :in_after
      end
      """)

    normalized = Normalizer.normalize(quoted)

    assert {:foo, _,
            [
              {:__block__, _,
               [
                 [
                   {{:__block__, _, [:do]}, {:__block__, _, [:in_do]}},
                   {{:__block__, _, [:else]}, {:__block__, _, [:in_else]}},
                   {{:__block__, _, [:catch]}, {:__block__, _, [:in_catch]}},
                   {{:__block__, _, [:rescue]}, {:__block__, _, [:in_rescue]}},
                   {{:__block__, _, [:after]}, {:__block__, _, [:in_after]}}
                 ]
               ]}
            ]} = normalized
  end

  test "left to right arrows" do
    quoted =
      Code.string_to_quoted!("""
      case do
        :left -> :right
      end
      """)

    normalized = Normalizer.normalize(quoted)

    assert {:case, _,
            [
              {:__block__, _,
               [
                 [
                   {{:__block__, _, [:do]},
                    [
                      {:->, _,
                       [
                         [{:__block__, _, [:left]}],
                         {:__block__, _, [:right]}
                       ]}
                    ]}
                 ]
               ]}
            ]} = normalized
  end

  test "left to right arrow with multiple arguments" do
    quoted =
      Code.string_to_quoted!("""
      case do
        :foo, :bar -> :baz
      end
      """)

    normalized = Normalizer.normalize(quoted)

    assert {:case, _,
            [
              {:__block__, _,
               [
                 [
                   {{:__block__, _, [:do]},
                    [
                      {:->, _,
                       [
                         [
                           {:__block__, _, [:foo]},
                           {:__block__, _, [:bar]}
                         ],
                         {:__block__, _, [:baz]}
                       ]}
                    ]}
                 ]
               ]}
            ]} = normalized
  end

  test "Unqualified call's form is skipped" do
    quoted = Code.string_to_quoted!("foo()")
    normalized = Normalizer.normalize(quoted)

    assert {:foo, _, []} = normalized
  end

  describe "preserves formatting" do
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
      assert_same("""
      fn
        foo -> :bar
        baz -> 42
      end
      """)

      assert_same("(() -> :ok)")
      assert_same("(() when node() == :nonode@nohost -> true)")
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

    test "heredocs" do
      assert_same("""
      (
        arg1 ->
          'foo'
        arg2 ->
          'bar'
      )
      """)
    end

    test "multiple empty clauses" do
      assert_same("""
      (
        () -> :ok1
        () -> :ok2
      )
      """)
    end

    test "when with keywords inside call" do
      assert_same("""
      quote((bar(foo(1)) when bat: foo(1)), [])
      """)

      assert_same("""
      quote(do: (bar(foo(1)) when bat: foo(1)), line: 1)
      """)

      assert_same("""
      typespec(quote(do: (bar(foo(1)) when bat: foo(1))), [foo: 1], [])
      """)
    end

    test "type with multiple |" do
      assert_same("""
      @type t ::
              binary
              | :doc_nil
              | :doc_line
              | doc_string
              | doc_cons
              | doc_nest
              | doc_break
              | doc_group
              | doc_color
              | doc_force
              | doc_cancel
      """)
    end

    test "spec with when keywords and |" do
      assert_same("""
      @spec send(dest, msg, [option]) :: :ok | :noconnect | :nosuspend
            when dest: pid | port | atom | {atom, node}, msg: any, option: :noconnect | :nosuspend
      """)

      assert_same("""
      @spec send(dest, msg, [option]) :: :ok | :noconnect | :nosuspend
            when dest:
                  pid
                  | port
                  | atom
                  | {atom, node}
                  | and_a_really_long_type_to_force_a_line_break
                  | followed_by_another_really_long_type
      """)

      assert_same("""
      @callback get_and_update(data, key, (value -> {get_value, value} | :pop)) :: {get_value, data}
                when get_value: var, data: container
      """)
    end

    test "spec with multiple keys on type" do
      assert_same("""
      @spec foo(%{(String.t() | atom) => any}) :: any
      """)
    end

    test "multiple whens with new lines" do
      assert_same("""
      def sleep(timeout)
          when is_integer(timeout) and timeout >= 0
          when timeout == :infinity do
        receive after: (timeout -> :ok)
      end
      """)
    end

    test "for functions" do
      assert_same("""
      foo(fn x -> y end)
      """)

      assert_same("""
      foo(fn
        a1 -> :ok
        b2 -> :error
      end)
      """)

      assert_same("""
      foo(bar, fn
        a1 -> :ok
        b2 -> :error
      end)
      """)

      assert_same(
        """
        foo(fn x ->
          :really_long_atom
        end)
        """,
        @medium_length
      )

      assert_same(
        """
        foo(bar, fn
          a1 ->
            :ok
          b2 ->
            :really_long_error
        end)
        """,
        @medium_length
      )
    end
  end
end
