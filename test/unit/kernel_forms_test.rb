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
        Machine.word(a) + Machine.word(b) + 0x7fff_ffff_ffff_fff0
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
        Machine.u32(a) + Machine.u8(b) + Machine.word(0x7fff_ffff_ffff_fff0)
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

  CHECKED = <<~RUBY
    module Zr::Kern
      Libc.import :write, [I32, Ptr, Word] => Word
      Libc.import :abort, [] => Void

      sig [Ptr, Word] => Void
      def zr_bug(bytes, len)
        Libc.write(2, bytes, len)
        Libc.abort()
      end

      sig [Word, Word] => Word
      def plain(a, b)
        (a + b) - (a * b) + (a << b) + (a / b) + (a >> b)
      end

      sig [Word, Word] => Word
      def named(a, b)
        Machine.sub_wrap(Machine.add_wrap(a, b), Machine.mul_wrap(a, b)) + Machine.shl_wrap(a, b)
      end

      sig [Ptr, Word] => Ptr
      def address(p, n)
        p + (n * 8)
      end
    end
  RUBY

  # The calls to zr_bug in each def, and the messages they print.
  def checks(source)
    unit = Zr::Machine::Lower.new([[source, "k.rb"]], checked: true)
    unit.run
    unit.functions.to_h do |f|
      calls = f.blocks.sum { |b| b.insts.count { |i| i.op == :call && f.callees.find { |c| c.fn == i.callee }&.symbol == "zr_bug" } }
      [f.name, calls]
    end.merge(texts: unit.data.map(&:bytes).grep(String).grep(/ZR_KERNEL_CHECKED/))
  end

  def test_the_checked_build_checks_each_plain_operator
    found = checks(CHECKED)

    assert_equal 9, found.fetch("plain") # four +, one each of - * <<, / by a negative or zero, >> by 64
    assert_includes found.fetch(:texts), "k.rb:13: + wraps (ZR_KERNEL_CHECKED)\n"
  end

  def test_a_named_operation_is_not_checked_and_a_ptr_is_checked_unsigned
    found = checks(CHECKED)

    assert_equal 1, found.fetch("named") # the plain + that joins them
    assert_equal 2, found.fetch("address") # n * 8 as a Word, p + as a Ptr
    assert_includes found.fetch(:texts), "k.rb:23: + leaves the range of a Ptr (ZR_KERNEL_CHECKED)\n"
  end

  def test_the_build_without_checks_has_none
    unit = Zr::Machine::Lower.new([[CHECKED, "k.rb"]], checked: false)
    unit.run

    assert_empty unit.data.map(&:bytes).grep(String).grep(/ZR_KERNEL_CHECKED/)
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

  def test_a_literal_past_a_signed_word_is_machine_word
    message = refusal("sig [] => Word\ndef big\n  0x8000000000000000\nend")

    assert_match(/a literal at or above 2\*\*63 is a word only as Machine.word\(literal\)/, message)
  end

  def test_there_is_no_machine_def
    assert_match(/not a declaration or a def/, refusal("sig [] => Void\nmachine def x\nend"))
  end
end
