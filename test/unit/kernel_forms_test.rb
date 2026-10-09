# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/machine/lower"

# The kernel's form: one `module Zr::Kern` of plain Ruby. A named
# operation (`Machine.add_wrap`, `Machine.sdiv`, `Machine.u32`, ...)
# lowers to the same IR as the plain operator or cast; it only says
# what the code means where Ruby's operator means something else.
class KernelFormsTest < Minitest::Test
  OPERATORS = <<~RUBY
    module Zr::Kern
      module Libc
        #: (ptr, i32, word) -> ptr
        def self.memset(p, i, n) = Machine.import
      end

      class Pair < Layout
        attr_accessor :head #: word
        attr_accessor :tail #: i32
      end

      module Thunk
        #: (ptr, word) -> word
        def self.call(fn, n) = Machine.indirect
      end

      LIMIT = 1 << 4

      #: (ptr, word) -> word
      def first(p, n)
        Libc.memset(p, Machine.i32(0), Pair.size)
        Pair[p].head = n * LIMIT
        Thunk.call(Machine.addr(:twice), Pair[p].head)
      end

      #: (word) -> word
      def twice(n)
        n + n
      end

      #: (i32, i8) -> word
      def widen(a, b)
        Machine.u32(a) + Machine.u8(b) + 0x7fff_ffff_ffff_fff0
      end

      #: (word, word) -> word
      def mix(a, b)
        (a * b) + (a << 3) - (a / b) + (a % b) + (b - a)
      end

      inline :twice
    end
  RUBY

  NAMED = <<~RUBY
    module Zr::Kern
      module Libc
        #: (ptr, i32, word) -> ptr
        def self.memset(p, i, n) = Machine.import
      end

      class Pair < Layout
        attr_accessor :head #: word
        attr_accessor :tail #: i32
      end

      module Thunk
        #: (ptr, word) -> word
        def self.call(fn, n) = Machine.indirect
      end

      LIMIT = 1 << 4

      #: (ptr, word) -> word
      def first(p, n)
        Libc.memset(p, Machine.i32(0), Pair.size)
        Pair[p].head = n * LIMIT
        Thunk.call(Machine.addr(:twice), Pair[p].head)
      end

      #: (word) -> word
      def twice(n)
        n + n
      end

      #: (i32, i8) -> word
      def widen(a, b)
        Machine.u32(a) + Machine.u8(b) + Machine.word(0x7fff_ffff_ffff_fff0)
      end

      #: (word, word) -> word
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
      module Libc
        #: (i32, ptr, word) -> word
        def self.write(i, p, n) = Machine.import
        #: () -> void
        def self.abort = Machine.import
      end

      #: (ptr, word) -> void
      def zr_bug(bytes, len)
        Libc.write(2, bytes, len)
        Libc.abort()
      end

      #: (word, word) -> word
      def plain(a, b)
        (a + b) - (a * b) + (a << b) + (a / b) + (a >> b)
      end

      #: (word, word) -> word
      def named(a, b)
        Machine.sub_wrap(Machine.add_wrap(a, b), Machine.mul_wrap(a, b)) + Machine.shl_wrap(a, b)
      end

      #: (ptr, word) -> ptr
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
    assert_includes found.fetch(:texts), "k.rb:17: + wraps (ZR_KERNEL_CHECKED)\n"
  end

  def test_a_named_operation_is_not_checked_and_a_ptr_is_checked_unsigned
    found = checks(CHECKED)

    assert_equal 1, found.fetch("named") # the plain + that joins them
    assert_equal 2, found.fetch("address") # n * 8 as a Word, p + as a Ptr
    assert_includes found.fetch(:texts), "k.rb:27: + leaves the range of a Ptr (ZR_KERNEL_CHECKED)\n"
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
      module Libc
        #: () -> i32
        def self.getpid = Machine.import
      end

      #: () -> i32
      def pid
        getpid
      end
    RUBY

    assert_match(/an import is `Libc.getpid`/, message)
  end

  def test_libc_calls_only_an_import
    message = refusal(<<~RUBY)
      #: () -> word
      def one
        Libc.one
      end
    RUBY

    assert_match(/one is not an import here/, message)
  end

  def test_a_raw_function_repeats_its_signature
    assert_match(/zr_switch is \(ptr, ptr\) -> void/, refusal("#: (ptr) -> void\ndef zr_switch(p) = Machine.raw"))
  end

  def test_the_module_is_zr_kern
    error = assert_raises(Zr::Machine::Refused) { lowered("module Other\nend\n") }

    assert_match(/the kernel's module is Zr::Kern/, error.message)
    error = assert_raises(Zr::Machine::Refused) { lowered("X = 1\n") }

    assert_match(/a kernel file is one `module Zr::Kern`/, error.message)
  end

  def test_a_literal_past_a_signed_word_is_machine_word
    message = refusal("#: () -> word\ndef big\n  0x8000000000000000\nend")

    assert_match(/a literal at or above 2\*\*63 is a word only as Machine.word\(literal\)/, message)
  end

  def test_a_narrow_integer_widens_only_by_name
    message = refusal("#: (i32) -> word\ndef wide(a)\n  Machine.word(a)\nend")

    assert_match(/Machine.word of an I32 is Machine.u32 \(zero-extend\) or Machine.sword \(sign-extend\)/, message)
  end

  # A def that may run the collector links its frame into the chain of
  # root frames (the `kroots` static). One that C may call on another OS
  # thread (`any_thread`) does not: that chain is the Ruby thread's.
  ROOTED = <<~RUBY
    module Zr::Kern
      collects :zr_gc
      any_thread :elsewhere

      #: () -> value
      def zr_gc
        Machine.value(4)
      end

      #: (value) -> value
      def keep(v)
        v
      end

      #: () -> value
      def here
        keep(zr_gc)
      end

      #: () -> value
      def elsewhere
        keep(zr_gc)
      end
    end
  RUBY

  def test_an_any_thread_def_has_no_root_frame
    unit = Zr::Machine::Lower.new([[ROOTED, "k.rb"]])
    unit.run
    roots = unit.functions.to_h { |f| [f.name, f.globals.map(&:symbol).include?("zr_static_kroots")] }

    assert roots.fetch("here"), "a collecting def links a root frame"
    refute roots.fetch("elsewhere"), "an any_thread def links none"
  end

  def test_an_any_thread_def_keeps_no_value_in_a_local
    message = refusal("collects :zr_gc\nany_thread :f\n#: () -> value\ndef zr_gc\n  Machine.value(4)\nend\n" \
                      "#: () -> value\ndef f\n  v = zr_gc\n  zr_gc\n  v\nend")

    assert_match(/f is any_thread, so it has no root frame to keep a Value local in/, message)
  end

  def test_there_is_no_machine_def
    assert_match(/not a declaration or a def/, refusal("#: () -> void\nmachine def x\nend"))
  end
end
