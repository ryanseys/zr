# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"

# The kernel's form (A6): one `module Zr::Kern` of plain Ruby. A named
# operation (`Machine.add_wrap`, `Machine.sdiv`, `Machine.u32`, ...)
# lowers to the same IR as the plain operator or cast; it only says
# what the code means where Ruby's operator means something else.
class KernelFormsTest < Minitest::Test
  OPERATORS = <<~RUBY
    module Zr::Kern
      Libc.import :memset, [Ptr, I32, Word] => Ptr
      Pair = layout head: Word, tail: I32
      Thunk = fn [Word] => Word
      LIMIT = 1 << 4

      sig [Ptr, Word] => Word
      def first(p, n)
        Libc.memset(p, Machine.i32(0), Pair.size)
        Pair.set_head(p, n * LIMIT)
        Thunk.call(Machine.addr(:twice), Pair.head(p))
      end

      sig [Word] => Word
      def twice(n)
        n + n
      end

      sig [I32, I8] => Word
      def widen(a, b)
        Machine.word(a) + Machine.word(b) + 0xffff_ffff_ffff_fff0
      end

      sig [Word, Word] => Word
      def mix(a, b)
        (a * b) + (a << 3) - (a / b) + (a % b) + (b - a)
      end
      inline :twice
    end
  RUBY

  NAMED = <<~RUBY
    module Zr::Kern
      Libc.import :memset, [Ptr, I32, Word] => Ptr
      Pair = layout head: Word, tail: I32
      Thunk = fn [Word] => Word
      LIMIT = 1 << 4

      sig [Ptr, Word] => Word
      def first(p, n)
        Libc.memset(p, Machine.i32(0), Pair.size)
        Pair.set_head(p, n * LIMIT)
        Thunk.call(Machine.addr(:twice), Pair.head(p))
      end

      sig [Word] => Word
      def twice(n)
        n + n
      end

      sig [I32, I8] => Word
      def widen(a, b)
        Machine.u32(a) + Machine.u8(b) + Machine.word(0xffff_ffff_ffff_fff0)
      end

      sig [Word, Word] => Word
      def mix(a, b)
        Machine.add_wrap(Machine.mul_wrap(a, b), Machine.shl_wrap(a, 3)) - Machine.sdiv(a, b) + Machine.srem(a, b) + Machine.sub_wrap(b, a)
      end
      inline :twice
    end
  RUBY

  def lowered(source)
    unit = Zr::Machine::Lower.new([[source, "k.rb"]])
    unit.run
    defined = (unit.functions.map(&:name) + unit.data.map(&:name) + unit.raw).to_set
    unit.functions.to_h { |f| [f.name, Zr::IR::Fingerprint.of(f, defined)] }
  end

  def test_a_named_operation_lowers_as_the_operator
    operators = lowered(OPERATORS)
    named = lowered(NAMED)

    assert_equal %w[first mix twice widen], named.keys.sort
    operators.each_key { |name| assert_equal operators[name], named[name], name }
  end

  def refusal(body)
    error = assert_raises(Zr::Machine::Refused) { lowered("module Zr::Kern\n#{body}\nend\n") }
    error.message
  end

  def test_a_bare_call_in_the_plain_form_goes_only_to_a_def
    message = refusal(<<~RUBY)
      Libc.import :getpid, [] => I32
      sig [] => I32
      def pid
        getpid
      end
    RUBY

    assert_match(/an import is `Libc.getpid`/, message)
  end

  def test_libc_calls_only_an_import
    message = refusal(<<~RUBY)
      sig [] => Word
      def one
        Libc.one
      end
    RUBY

    assert_match(/one is not a Libc.import here/, message)
  end

  def test_a_raw_function_repeats_its_signature
    assert_match(/zr_switch is \[Ptr, Ptr\] => Void/, refusal("raw :zr_switch, [Ptr] => Void"))
  end

  def test_the_module_is_zr_kern
    error = assert_raises(Zr::Machine::Refused) { lowered("module Other\nend\n") }

    assert_match(/the kernel's module is Zr::Kern/, error.message)
    error = assert_raises(Zr::Machine::Refused) { lowered("X = 1\n") }

    assert_match(/a kernel file is one `module Zr::Kern`/, error.message)
  end

  def test_there_is_no_machine_def
    assert_match(/not a declaration or a def/, refusal("sig [] => Void\nmachine def x\nend"))
  end
end
