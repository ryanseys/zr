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

  def test_an_unsupported_form_gives_the_place_and_the_form
    e = Zr::Hir::Refused.unsupported("the flip-flop operator", file: "app.rb", line: 12, column: 5)

    assert_equal "app.rb:12:5: zr does not support the flip-flop operator yet", e.message
    assert_equal ["app.rb", 12, 5, "the flip-flop operator"], [e.file, e.line, e.column, e.form]
    assert_kind_of Zr::Hir::Refused, e
  end

  def test_a_node_class_gives_its_form_in_words
    flip = Class.new { def self.name = "Prism::FlipFlopNode" }.new
    other = Class.new { def self.name = "Prism::InterpolatedXStringNode" }.new

    forms = [flip, other].map { |node| Zr::Refused.form_of(node) }

    assert_equal ["the flip-flop operator (a range as a condition)", "interpolated xstring (InterpolatedXString)"], forms
  end

  def test_the_excerpt_puts_a_caret_under_the_column
    Dir.mktmpdir("zr-refused-") do |dir|
      file = File.join(dir, "app.rb")
      File.write(file, "x = 1\nif (a == 1)..(a == 2) then p a end\n")
      e = Zr::Refused.unsupported("the flip-flop operator", file: file, line: 2, column: 4)

      assert_equal "    if (a == 1)..(a == 2) then p a end\n       ^", e.excerpt
    end
  end

  def test_a_message_only_refusal_has_no_excerpt
    e = Zr::Refused.new("a relocation of type 9")

    assert_nil e.excerpt
    assert_nil e.form
  end
end
