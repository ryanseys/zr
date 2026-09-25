# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# `Zr::Hir::Build.eval_call?` tells if a call compiles ruby code that runs
# in the frame of the call. Two callers use it. The loader uses it to
# decide if the program includes eval support. `Build#evals?` uses it to
# decide if the enclosing method arms the catch for a `return`.
#
# Each case below was checked against ruby 4.0.7 first.
# `test/spec/lang/eval/eval_test.rb` checks the same cases end to end.
class EvalCallTest < Minitest::Test
  Build = Zr::Hir::Build

  def test_eval_always_counts_whatever_its_receiver
    assert Build.eval_call?(:eval, argc: 1)
    assert Build.eval_call?(:eval, argc: 2)
  end

  def test_the_three_eval_forms_count_only_with_a_string
    %i[instance_eval class_eval module_eval].each do |name|
      assert Build.eval_call?(name, argc: 1), "#{name} of a string compiles"
      refute Build.eval_call?(name, argc: 0), "#{name} of a block does not"
    end
  end

  def test_send_counts_when_its_method_is_an_eval
    assert Build.eval_call?(:send, named: :eval, argc: 2)
    assert Build.eval_call?(:__send__, named: :instance_eval, argc: 2)
    refute Build.eval_call?(:public_send, named: :instance_eval, argc: 1)
    refute Build.eval_call?(:send, named: :puts, argc: 2)
  end

  def test_a_fetch_counts_whatever_arguments_the_later_call_takes
    assert Build.eval_call?(:method, named: :eval, argc: 1)
    assert Build.eval_call?(:instance_method, named: :class_eval, argc: 1)
    refute Build.eval_call?(:public_method, named: :puts, argc: 1)
  end

  def test_an_ordinary_call_does_not_count
    refute Build.eval_call?(:puts, argc: 1)
    refute Build.eval_call?(:evaluate, argc: 1)
  end

  # Each spelling of an eval call must arm the catch. If only `eval` arms
  # it, `instance_eval("return 1")` loses its return.
  def test_every_spelling_arms_the_return_catch
    sources = {
      "eval" => %q{eval("return 1")},
      "instance_eval" => %q{instance_eval("return 1")},
      "instance_eval on a receiver" => %q{1.instance_eval("return 1")},
      "class_eval" => %q{C.class_eval("return 1")},
      "module_eval" => %q{C.module_eval("return 1")},
      "send" => %q{send(:eval, "return 1")},
      "__send__" => %q{__send__(:eval, "return 1")},
      "method" => %q{method(:eval).call("return 1")},
      "binding" => %q{binding.eval("return 1")}
    }
    sources.each do |what, call|
      assert armed?(call), "a return inside #{what} needs the catch"
    end
  end

  def test_a_def_the_eval_writes_keeps_its_own_return
    refute armed?(%q{def inner; return 1; end})
    refute armed?(%q{[1].each { |x| x }})
  end

  private

  # Returns true if `def m` with `body` arms the return catch.
  # `eval_support: false` leaves out eval support: the test checks only
  # the front end, and eval support would build 200 units for each case.
  def armed?(body)
    program = Zr::Hir.build("class C; end\ndef m\n  #{body}\nend\n", "eval_call_test.rb", eval_support: false)
    defs(program.body).find { |d| d.name == :m }.evals
  end

  # Every `Hir::Def` in a body, nested ones included.
  def defs(node)
    return [] unless node.is_a?(Zr::Hir::Node)

    rows = node.is_a?(Zr::Hir::Def) ? [node] : []
    rows + node.to_a.flatten.flat_map { |child| defs(child) }
  end
end
