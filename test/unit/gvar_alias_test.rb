# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# `alias $hit $&`.
#
# ruby's alias of a global reaches the whole program, and it happens
# where it is written: an alias under a branch that does not run leaves
# the name the ordinary global it looks like. Asked of ruby 4.0.6:
#
#   if false; alias $x $&; end; "hello" =~ /ll/; p $x   # nil
#
# zr cannot carry such a row. `$&` is a register of the frame that last
# matched and not a global, so the name is resolved as the file is
# lowered -- which is right as it stands only for an alias the file runs
# whenever it loads. One written where it may not run sets a flag of its
# own when it runs, and each use of the name asks the flag: the back
# reference once the alias ran, the ordinary global before.
class GvarAliasTest < Minitest::Test
  def test_an_alias_a_file_always_runs_makes_the_name_a_back_reference
    ["alias $hit $&", "class K\n  alias $hit $&\nend", "module M\n  alias $hit $&\nend",
     "begin\n  alias $hit $&\nrescue\n  nil\nend"].each do |where|
      assert_includes dump("#{where}\np $hit\n"), "(backref nth 0)", where
    end
  end

  def test_an_alias_where_it_may_not_run_sets_a_flag_each_use_asks
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

  # An alias of one ordinary global to another is a row the runtime
  # carries, so it runs where it is written, wherever that is.
  def test_an_alias_of_an_ordinary_global_is_left_alone
    assert_includes dump("if false\n  alias $x $stdout\nend\n"), "(alias $x $stdout)"
  end

  private

  def dump(source) = Zr::Hir::Dump.program(Zr::Hir.build(source, "alias.rb", road: false))
end
