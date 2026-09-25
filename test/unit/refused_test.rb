# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/refused"
require_relative "../../lib/zr/backend"
require_relative "../../lib/zr/ir/types"
require_relative "../../lib/zr/ir/interp"
require_relative "../../lib/zr/backend/aarch64/assembler"
require_relative "../../lib/zr/obj/macho/block"
require_relative "../../lib/zr/eval/walk/tree"
require_relative "../../lib/zr/backend/aarch64/codegen"
require_relative "../../lib/zr/backend/wasm/codegen"
require_relative "../../lib/zr/lower"
require_relative "../../lib/zr/hir"

# Every stage's own `Refused` keeps its own superclass (`StandardError`,
# `Backend::Refused`, `::NotImplementedError`), so exit codes, the spec
# tier split and the cc fallbacks still match on that superclass. What
# they all share, directly or by inheriting it, is `Zr::Refusal`.
class RefusedTest < Minitest::Test
  REFUSED_CLASSES = [
    Zr::Refused,
    Zr::Backend::Refused,
    Zr::IR::Types::Refused,
    Zr::IR::Interp::Refused,
    Zr::Backend::Aarch64::Assembler::Refused,
    Zr::Obj::MachO::Refused,
    Zr::Eval::Tree::Refused,
    # Inherit `Zr::Refusal` from a stage's own `Refused` above, rather
    # than including it a second time.
    Zr::Backend::Aarch64::Codegen::Refused,
    Zr::Backend::Wasm::Codegen::Refused,
    Zr::Lower::Refused,
    Zr::Hir::Refused,
  ].freeze

  REFUSED_CLASSES.each do |klass|
    define_method("test_#{klass.name.gsub("::", "_")}_is_a_zr_refusal") do
      assert_operator klass, :<, Zr::Refusal
    end
  end

  def test_zr_refused_keeps_standard_error_as_its_superclass
    assert_operator Zr::Refused, :<, StandardError
  end

  def test_eval_tree_refused_keeps_not_implemented_error_as_its_superclass
    assert_operator Zr::Eval::Tree::Refused, :<, ::NotImplementedError
  end

  def test_a_refusal_instance_answers_is_a_refusal
    assert_kind_of Zr::Refusal, Zr::Backend::Refused.new("no code for this form")
  end
end
