# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# Whether a scope keeps its locals in an Env: the one rule that the
# lowering (`Lower::Function`) and the host walker (`Frames#open?`) read
# (Hir::Locals.env?).
class HirLocalsTest < Minitest::Test
  def test_a_main_or_eval_scope_always_has_an_env
    assert Zr::Hir::Locals.env?(nil, :main)
    assert Zr::Hir::Locals.env?(nil, :eval)
  end

  def test_a_plain_body_has_none
    refute Zr::Hir::Locals.env?(body("x = 1\nx + 1\n"), :def)
  end

  def test_a_block_or_a_binding_in_the_body_gives_one
    assert Zr::Hir::Locals.env?(body("[1].each { |v| v }\n"), :def)
    assert Zr::Hir::Locals.env?(body("binding\n"), :block)
  end

  def test_a_send_by_a_computed_name_gives_one_only_where_names_are_computed
    computed = body("public_send(name)\n")

    assert Zr::Hir::Locals.env?(computed, :def)
    refute Zr::Hir::Locals.env?(computed, :def, computed: false)
  end

  def test_a_default_value_that_holds_a_block_gives_one
    defaults = body("def m(a = -> { 1 }) = a\n").stmts.first.params.defaults

    assert Zr::Hir::Locals.env?(nil, :def, defaults:)
  end

  def test_a_traced_program_gives_each_def_block_file_and_body_one
    Zr::Hir::Locals::TRACED.each do |kind|
      assert Zr::Hir::Locals.env?(nil, kind, traced: true), kind
      refute Zr::Hir::Locals.env?(nil, kind), kind
    end
  end

  private

  def body(source) = Zr::Hir.build(source, "locals.rb", program: false).body
end
