defmodule Example.MultiAliasTest do
  use ExUnit.Case

  test "expands multi alias" do
    source = """
    alias Foo.{Bar, Baz.Qux}
    """

    expected =
      """
      alias Foo.Bar
      alias Foo.Baz.Qux
      """
      |> String.trim()

    actual = Examples.MultiAlias.fix(source)

    assert actual == expected
  end

  test "preserves comments" do
    source = """
    # Multi alias example
    alias Foo.{ # Opening the multi alias
      Bar, # Here is Bar
      # Here come the Baz
      Baz.Qux # With a Qux!
    }

    # End of the demo :)
    """

    expected =
      """
      # Multi alias example
      # Opening the multi alias
      # Here is Bar
      alias Foo.Bar
      # Here come the Baz
      # With a Qux!
      alias Foo.Baz.Qux

      # End of the demo :)
      """
      |> String.trim()

    actual = Examples.MultiAlias.fix(source)

    assert actual == expected
  end

  test "does not misplace comments above or below" do
    source = """
    # A
    :a

    alias Foo.{Bar, Baz,
    Qux}

    :b # B
    """

    expected =
      """
      # A
      :a

      alias Foo.Bar
      alias Foo.Baz
      alias Foo.Qux
      # B
      :b
      """
      |> String.trim()

    actual = Examples.MultiAlias.fix(source)

    assert actual == expected
  end
end
