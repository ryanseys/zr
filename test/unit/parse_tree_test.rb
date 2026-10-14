# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/parse"
require_relative "../../lib/zr/cli/parse_tree"

# `--dump=parsetree` (lib/zr/cli/parse_tree.rb): prism's tree in the format
# of prism's C pretty printer, which ruby prints.
class ParseTreeTest < Minitest::Test
  def tree(source) = Zr::CLI::ParseTree.text(Prism.parse(source).value)

  def test_a_node_is_its_name_and_location_then_one_line_for_each_field
    assert_equal <<~TREE, tree("1")
      @ ProgramNode (location: (1,0)-(1,1))
      +-- locals: []
      +-- statements:
          @ StatementsNode (location: (1,0)-(1,1))
          +-- body: (length: 1)
              +-- @ IntegerNode (location: (1,0)-(1,1))
                  +-- IntegerBaseFlags: decimal
                  +-- value: 1
    TREE
  end

  # The flags come first, named by their type; a node with none has nil. A
  # missing node or location is nil, and a location shows its source.
  def test_flags_nil_fields_and_locations
    text = tree("a&.b")

    assert_includes text, "+-- CallNodeFlags: safe_navigation\n"
    assert_includes text, "|   +-- CallNodeFlags: variable_call, ignore_visibility\n"
    assert_includes text, "+-- call_operator_loc: (1,1)-(1,3) = \"&.\"\n"
    assert_includes text, "+-- arguments: nil\n"
    assert_includes tree("[*a, 1]"), "+-- ArrayNodeFlags: contains_splat\n"
  end

  # Several flags are joined with ",", each after a blank.
  def test_several_flags_are_listed_in_the_config_order
    assert_includes tree("/x/imx"), "+-- RegularExpressionFlags: ignore_case, extended, multi_line, forced_us_ascii_encoding\n"
  end

  # The last field of a node gets blanks for the prefix of its children,
  # and the others get "|".
  def test_children_are_indented_under_their_field
    lines = tree("f(1, 2)").lines

    assert_includes lines, "            +-- arguments:\n"
    assert_includes lines, "            |   @ ArgumentsNode (location: (1,2)-(1,6))\n"
    assert_includes lines, "            |       +-- @ IntegerNode (location: (1,2)-(1,3))\n"
    assert_includes lines, "            |       |   +-- IntegerBaseFlags: decimal\n"
    assert_includes lines, "            |       +-- @ IntegerNode (location: (1,5)-(1,6))\n"
    assert_includes lines, "            |           +-- IntegerBaseFlags: decimal\n"
  end

  def test_constants_and_constant_lists
    text = tree("def m(a, b) = a")

    assert_includes text, "+-- name: :m\n"
    assert_includes text, "+-- locals: [:a, :b]\n"
    assert_includes tree("x = 1"), "+-- locals: [:x]\n"
  end

  # A string's bytes as ruby escapes them: control bytes, quotes, a
  # backslash and a "#" that starts an interpolation.
  def test_strings_and_locations_escape_their_bytes
    assert_includes tree('"\x01\a\e\"\\\\\#{x} #y"'), "+-- unescaped: \"\\x01\\a\\x1B\\\"\\\\\\\#{x} #y\"\n"
    assert_includes tree("\"é\""), "+-- unescaped: \"\\xC3\\xA9\"\n"
    assert_includes tree("\"é\""), "+-- content_loc: (1,1)-(1,3) = \"\\xC3\\xA9\"\n"
  end

  # Columns count bytes, as prism's C counts them.
  def test_columns_are_bytes
    assert_includes tree("\"é\"; 1"), "+-- @ IntegerNode (location: (1,6)-(1,7))\n"
  end

  # An integer of any size and sign, and a float as printf's "%f".
  def test_numbers
    assert_includes tree("-(2**70)"), "+-- value: 2\n"
    assert_includes tree("-18446744073709551616"), "+-- value: -18446744073709551616\n"
    assert_includes tree("1.5"), "+-- value: 1.500000\n"
    assert_includes tree("1e400"), "+-- value: inf\n"
  end

  # A symbol's name keeps its bytes.
  def test_a_constant_keeps_its_bytes
    assert_includes tree(":あ"), "+-- unescaped: \"\\xE3\\x81\\x82\"\n"
    assert_includes tree("あ = 1"), "+-- name: :あ\n".b
  end
end
