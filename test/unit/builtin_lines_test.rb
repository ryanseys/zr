# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../tool/gen/builtin_lines"

# tool/gen/builtin_lines.rb reads the :line events that the body of each
# of CRuby's Ruby-written core methods fires, when the build can know
# them. TracePoint.fire replays them after the method's :call.
class BuiltinLinesTest < Minitest::Test
  Lines = Zr::Dev::Gen::BuiltinLines::Lines

  def test_the_generated_file_is_current
    out, ok = Checks.generate("builtin_lines")

    assert ok, out
  end

  def test_a_body_of_one_primitive_fires_its_line_with_a_block_or_without
    known = lines_of(<<~RUBY)
      def start
        Primitive.attr! :leaf
        Primitive.gc_start_internal
      end
    RUBY

    assert_equal({ block: [3], bare: [3] }, known)
  end

  def test_statements_with_no_call_before_the_last_fire_each_line
    known = lines_of(<<~RUBY)
      def f
        a = 1
        b = :x
        Primitive.cexpr!("x")
      end
    RUBY

    assert_equal({ block: [2, 3, 4], bare: [2, 3, 4] }, known)
  end

  def test_a_block_guard_gives_a_sequence_for_a_call_without_a_block
    known = lines_of(<<~RUBY)
      def then
        Primitive.attr! :inline_block
        unless defined?(yield)
          return Primitive.cexpr!("enum")
        end
        yield(self)
      end
    RUBY

    assert_equal({ block: [3, 6], bare: [3, 4] }, known)
  end

  def test_a_modifier_guard_on_block_given_fires_its_one_line
    known = lines_of(<<~RUBY)
      def each
        return to_enum(__method__) unless block_given?
        Primitive.each_m
      end
    RUBY

    assert_equal({ block: [2, 3], bare: [2] }, known)
  end

  def test_a_loop_after_the_guard_leaves_only_the_bare_sequence
    known = lines_of(<<~RUBY)
      def times
        unless defined?(yield)
          return Primitive.cexpr!("enum")
        end
        i = 0
        while i < self
          yield i
          i = i.succ
        end
        self
      end
    RUBY

    assert_equal({ bare: [2, 3] }, known)
  end

  def test_a_call_before_the_last_statement_is_not_known
    assert_nil lines_of(<<~RUBY)
      def tap
        yield(self)
        self
      end
    RUBY
  end

  def test_a_last_statement_with_a_branch_or_a_block_is_not_known
    assert_nil lines_of("def f\n  x ? 1 : 2\nend\n")
    assert_nil lines_of("def f\n  [1].each { |x| x }\nend\n")
  end

  def test_a_body_with_a_rescue_is_not_known
    assert_nil lines_of("def f\n  Primitive.x\nrescue\n  nil\nend\n")
  end

  def test_a_mandatory_only_split_gives_the_lines_of_a_call_of_its_lead_arguments
    known = lines_of(<<~RUBY)
      def Float(arg, exception: true)
        if Primitive.mandatory_only?
          Primitive.rb_f_float1(arg)
        else
          Primitive.rb_f_float(arg, exception)
        end
      end
    RUBY

    assert_equal({ lead: 1, only: [3], raise_only: 3, block: [5], bare: [5], raise: 5 }, known)
  end

  def test_a_branching_second_half_keeps_only_the_mandatory_lines
    known = lines_of(<<~RUBY)
      def first n = unspecified = true
        if Primitive.mandatory_only?
          Primitive.attr! :leaf
          Primitive.cexpr! %q{ ary_first(self) }
        else
          if unspecified
            Primitive.cexpr! %q{ ary_first(self) }
          end
        end
      end
    RUBY

    assert_equal({ lead: 0, only: [4] }, known)
  end

  def test_an_error_raises_at_the_first_primitive_that_takes_a_parameter
    known = lines_of(<<~RUBY)
      def first n = unspecified = true
        if Primitive.mandatory_only?
          Primitive.cexpr! %q{ ary_first(self) }
        else
          if unspecified
            Primitive.cexpr! %q{ ary_first(self) }
          else
            Primitive.cexpr! %q{ ary_take(self, NUM2LONG(n)) }
          end
        end
      end
    RUBY

    assert_equal({ lead: 0, only: [3], raise: 8 }, known)
  end

  def test_a_primitive_in_the_test_of_a_branch_only_decides
    known = lines_of(<<~RUBY)
      def warn(*msgs, uplevel: nil, category: nil)
        if Primitive.cexpr!("NIL_P(category)")
          Primitive.rb_warn_m(msgs, uplevel, nil)
        else
          Primitive.rb_warn_m(msgs, uplevel, category)
        end
      end
    RUBY

    assert_equal({ raise: 3 }, known)
  end

  def test_a_method_without_parameters_raises_at_no_line_of_its_own
    assert_nil lines_of("def f\n  x = 1\n  Primitive.g(x)\nend\n")&.dig(:raise)
  end

  def test_statements_on_one_line_fire_it_once
    assert_equal({ block: [2], bare: [2] }, lines_of("def f\n  a = 1; Primitive.x(a)\nend\n"))
  end

  private

  def lines_of(source)
    Lines.of(Prism.parse(source).value.statements.body.first)
  end
end
