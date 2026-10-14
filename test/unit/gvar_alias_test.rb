# frozen_string_literal: true

require "test_helper"
require_relative "../support/hir_dump"

# `alias $hit $&`.
#
# In ruby, an alias of a global applies to the whole program, and it
# takes effect when it runs. An alias under a branch that does not run
# leaves the name an ordinary global. Checked against ruby:
#
#   if false; alias $x $&; end; "hello" =~ /ll/; p $x   # nil
#
# zr cannot store such an alias in the runtime table. `$&` is a value in
# the frame of the last match, not a global, so zr resolves the name when
# it lowers the file. That is correct only for an alias that always runs
# when the file loads. An alias that may not run sets its own flag when
# it runs. Each use of the name checks the flag: after the alias ran, it
# reads the back reference; before, it reads the ordinary global.
class GvarAliasTest < Minitest::Test
  def test_unconditional_alias_makes_name_a_back_reference
    ["alias $hit $&", "class K\n  alias $hit $&\nend", "module M\n  alias $hit $&\nend",
     "begin\n  alias $hit $&\nrescue\n  nil\nend"].each do |where|
      assert_includes dump("#{where}\np $hit\n"), "(backref nth 0)", where
    end
  end

  def test_conditional_alias_sets_a_flag_that_each_use_checks
    wheres = {
      "a branch" => "if false\n  alias $x $&\nend",
      "a loop" => "while false\n  alias $x $&\nend",
      "a rescue" => "begin\n  nil\nrescue\n  alias $x $&\nend",
      "a block" => "[1].each do\n  alias $x $&\nend",
      "a method" => "def m\n  alias $x $&\nend"
    }
    wheres.each do |what, source|
      tree = dump("#{source}\np $x\n")

      assert_includes tree, "$%alias$x", what
      assert_includes tree, "(backref nth 0)", what
    end
  end

  # An alias of one ordinary global to another is an entry in the runtime
  # table, so it takes effect when it runs, wherever it is.
  def test_an_alias_of_an_ordinary_global_is_left_alone
    assert_includes dump("if false\n  alias $x $stdout\nend\n"), "(alias $x $stdout)"
  end

  private

  def dump(source) = Zr::Hir::Dump.program(Zr::Hir.build(source, "alias.rb", eval_support: false))
end
