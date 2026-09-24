# frozen_string_literal: true

require_relative "../../lib/zr/ir"
require_relative "../../lib/zr/obj/model"

module Zr
  module Native
    # The native floor: IR written by hand, owing nothing to a Ruby
    # lowering. Each method answers `[functions, data]`; the binary it
    # becomes prints `<name>.stdout` and exits 0. Every fact a fixture
    # checks becomes one bit of the exit status, so a wrong answer names
    # itself.
    module Fixtures
      NAMES = %w[arith bits divide hello indirect loops table].freeze

      module_function

      def build(name) = public_send(name)

      # A write through libSystem, and the one datum it reads.
      def hello
        f = IR::Function.new("main", %w[i32 i64], "i32")
        write = f.callee("write", %w[i32 i64 i64], "i64", colocated: false)
        exit = f.callee("exit", %w[i32], nil, colocated: false)
        f.call_val(write, [f.iconst("i32", 1), f.symbol_value(f.symbol("msg")), f.iconst("i64", 11)])
        f.call(exit, [f.iconst("i32", 0)])
        f.ret(f.iconst("i32", 0))
        [[f], [Obj::Data.new("msg", :text_const, "hello, zr!\n", align: 1)]]
      end

      # Overflow flags, select, bit operations, wide and negative
      # constants, 32-bit arithmetic, and a call between two functions of
      # this unit.
      def arith
        check = IR::Function.new("check", %w[i64 i64], "i64")
        a, b = check.args
        check.ret(check.csel(check.icmp("eq", a, b), check.iconst("i64", 0), check.iconst("i64", 1)))

        f = IR::Function.new("main", %w[i32 i64], "i32")
        same = f.callee("check", %w[i64 i64], "i64")
        exit = f.callee("exit", %w[i64], nil, colocated: false)
        zero = f.iconst("i64", 0)
        one = f.iconst("i64", 1)

        # Each fact answers 0 when it holds; the bits shift up as they go.
        bits = nil
        push = lambda do |bit|
          bits = bits.nil? ? bit : f.iadd(f.iadd(bits, bits), bit)
        end

        # 2^62 + 2^62 overflows; 1 + 2 does not.
        big = f.iconst("i64", 4_611_686_018_427_387_904)
        _sum, over = f.sadd_overflow(big, big)
        three, no_over = f.sadd_overflow(one, f.iconst("i64", 2))
        push.call(f.call_val(same, [three, f.iconst("i64", 3)]))
        push.call(f.csel(f.icmp("eq", over, f.iconst("i8", 1)), zero, one))
        push.call(f.csel(f.icmp("eq", no_over, f.iconst("i8", 0)), zero, one))

        # -5 * 7 = -35 with no overflow; 2^62 * 4 overflows.
        product, = f.smul_overflow(f.iconst("i64", -5), f.iconst("i64", 7))
        push.call(f.call_val(same, [product, f.iconst("i64", -35)]))
        _wide, wide_over = f.smul_overflow(big, f.iconst("i64", 4))
        push.call(f.call_val(same, [f.csel(wide_over, one, zero), one]))

        # 0xF0F0 & 0xFF00 = 0xF000, 0xF0F0 | 0x0F0F = 0xFFFF.
        f0f0 = f.iconst("i64", 0xF0F0)
        push.call(f.call_val(same, [f.band(f0f0, f.iconst("i64", 0xFF00)), f.iconst("i64", 0xF000)]))
        push.call(f.call_val(same, [f.bor(f0f0, f.iconst("i64", 0x0F0F)), f.iconst("i64", 0xFFFF)]))

        # A 64-bit constant with every half set, minus one.
        push.call(f.call_val(same, [f.isub(f.iconst("i64", 81_985_529_216_486_895), one),
                                    f.iconst("i64", 81_985_529_216_486_894)]))

        # 32-bit wrap: 4294967295 + 1 is 0 in i32.
        wrapped = f.iadd(f.iconst("i32", -1), f.iconst("i32", 1))
        push.call(f.csel(f.icmp("eq", wrapped, f.iconst("i32", 0)), zero, one))

        # A select on a 64-bit condition tests the whole word: a bit past
        # the low 32 selects the first operand, and zero the second.
        push.call(f.csel(f.iconst("i64", 1 << 40), zero, one))
        push.call(f.csel(zero, one, zero))

        f.call(exit, [bits])
        f.ret(f.iconst("i32", 0))
        [[check, f], []]
      end

      # What the IR says a division by zero, an overflowing division and a
      # long shift answer, which every backend owes the same (lib/zr/ir/inst.rb):
      # `udiv`/`sdiv` by zero answer 0, `urem`/`srem` by zero the dividend,
      # the most negative number divided by -1 wraps to itself, and a shift
      # takes its amount modulo the width. The operands pass through a call,
      # so no backend sees a constant it could fold.
      def divide
        same = IR::Function.new("same", %w[i64], "i64")
        same.ret(same.args[0])
        same32 = IR::Function.new("same32", %w[i32], "i32")
        same32.ret(same32.args[0])

        f = IR::Function.new("main", %w[i32 i64], "i32")
        id = f.callee("same", %w[i64], "i64")
        id32 = f.callee("same32", %w[i32], "i32")
        exit = f.callee("exit", %w[i64], nil, colocated: false)
        zero = f.iconst("i64", 0)
        one = f.iconst("i64", 1)
        wide = ->(n) { f.call_val(id, [f.iconst("i64", n)]) }
        narrow = ->(n) { f.call_val(id32, [f.iconst("i32", n)]) }
        holds = ->(value, want, type = "i64") { f.csel(f.icmp("eq", value, f.iconst(type, want)), zero, one) }

        # Each fact answers 0 when it holds; eight of them fit the status.
        bits = nil
        [holds.call(f.udiv(wide.call(7), wide.call(0)), 0),
         holds.call(f.sdiv(wide.call(-7), wide.call(0)), 0),
         holds.call(f.urem(wide.call(7), wide.call(0)), 7),
         holds.call(f.srem(wide.call(-7), wide.call(0)), -7),
         holds.call(f.sdiv(wide.call(-(2**63)), wide.call(-1)), -(2**63)),
         holds.call(f.srem(wide.call(-(2**63)), wide.call(-1)), 0),
         holds.call(f.ishl(wide.call(1), wide.call(65)), 2),
         holds.call(f.sdiv(narrow.call(-(2**31)), narrow.call(-1)), -(2**31), "i32")].each do |bit|
          bits = bits.nil? ? bit : f.iadd(f.iadd(bits, bits), bit)
        end

        f.call(exit, [bits])
        f.ret(f.iconst("i32", 0))
        [[same, same32, f], []]
      end

      # What the IR says the bit tricks answer (lib/zr/ir/inst.rb): a
      # count of zero's zeros is the width, `popcnt` counts, `bswap`
      # turns the bytes round, each as wide as its operand. The operands
      # pass through a call, so no backend sees a constant it could fold.
      def bits
        same = IR::Function.new("same", %w[i64], "i64")
        same.ret(same.args[0])
        same32 = IR::Function.new("same32", %w[i32], "i32")
        same32.ret(same32.args[0])

        f = IR::Function.new("main", %w[i32 i64], "i32")
        id = f.callee("same", %w[i64], "i64")
        id32 = f.callee("same32", %w[i32], "i32")
        exit = f.callee("exit", %w[i64], nil, colocated: false)
        zero = f.iconst("i64", 0)
        one = f.iconst("i64", 1)
        wide = ->(n) { f.call_val(id, [f.iconst("i64", n)]) }
        narrow = ->(n) { f.call_val(id32, [f.iconst("i32", n)]) }
        holds = ->(value, want, type = "i64") { f.csel(f.icmp("eq", value, f.iconst(type, want)), zero, one) }

        bits = nil
        [holds.call(f.bitop(:ctz, wide.call(0x50)), 4),
         holds.call(f.bitop(:ctz, wide.call(0)), 64),
         holds.call(f.bitop(:clz, wide.call(1)), 63),
         holds.call(f.bitop(:clz, narrow.call(0)), 32, "i32"),
         holds.call(f.bitop(:popcnt, wide.call(0xF0F0_0000_0000_0001)), 9),
         holds.call(f.bitop(:popcnt, narrow.call(-1)), 32, "i32"),
         holds.call(f.bitop(:bswap, wide.call(0x0102_0304_0506_0708)), 0x0807_0605_0403_0201),
         holds.call(f.bitop(:bswap, narrow.call(0x0102_0304)), 0x0403_0201, "i32")].each do |bit|
          bits = bits.nil? ? bit : f.iadd(f.iadd(bits, bits), bit)
        end

        f.call(exit, [bits])
        f.ret(f.iconst("i32", 0))
        [[same, same32, f], []]
      end

      # A call through a function pointer: two addresses stored to a
      # stack slot, loaded back, and called through the one signature.
      def indirect
        double = IR::Function.new("double", %w[i64], "i64")
        double.ret(double.iadd(double.args[0], double.args[0]))

        negate = IR::Function.new("negate", %w[i64], "i64")
        negate.ret(negate.isub(negate.iconst("i64", 0), negate.args[0]))

        f = IR::Function.new("main", %w[i32 i64], "i32")
        sig = f.sig(%w[i64], "i64")
        table = f.stack_addr(f.slot(16))
        f.store(f.func_addr(f.callee("double", %w[i64], "i64")), table)
        f.store(f.func_addr(f.callee("negate", %w[i64], "i64")), table, 8)
        twice = f.call_indirect_val(sig, f.fetch("i64", table), [f.iconst("i64", 21)])
        flipped = f.call_indirect_val(sig, f.fetch("i64", table, 8), [twice])
        # An answer nobody takes: the call still balances the stack.
        f.call_indirect(sig, f.fetch("i64", table), [f.iconst("i64", 1)])
        # `flipped` is -42, so the status is 0.
        f.call(f.callee("exit", %w[i64], nil, colocated: false), [f.iadd(f.iconst("i64", 42), flipped)])
        f.ret(f.iconst("i32", 0))
        [[double, negate, f], []]
      end

      # A table of function pointers in data. Each entry is an absolute
      # relocation, so a position-independent image has to rebase it
      # before `main` can call through it -- which is the one thing a
      # stack slot full of `func_addr` does not reach.
      def table
        twice = IR::Function.new("twice", %w[i64], "i64")
        twice.ret(twice.iadd(twice.args[0], twice.args[0]))
        negate = IR::Function.new("negate", %w[i64], "i64")
        negate.ret(negate.isub(negate.iconst("i64", 0), negate.args[0]))

        f = IR::Function.new("main", %w[i32 i64], "i32")
        sig = f.sig(%w[i64], "i64")
        at = f.symbol_value(f.symbol("table"))
        doubled = f.call_indirect_val(sig, f.fetch("i64", at), [f.iconst("i64", 21)])
        flipped = f.call_indirect_val(sig, f.fetch("i64", at, 8), [doubled])
        # `flipped` is -42, so the status is 0.
        f.call(f.callee("exit", %w[i64], nil, colocated: false), [f.iadd(f.iconst("i64", 42), flipped)])
        f.ret(f.iconst("i32", 0))

        rows = [Obj::Reloc.new(0, :abs64, "twice"), Obj::Reloc.new(8, :abs64, "negate")]
        [[twice, negate, f], [Obj::Data.new("table", :data, [0, 0].pack("Q<2"), relocs: rows)]]
      end

      # The sum 1..100 printed in decimal through a stack buffer: block
      # parameters, a loop, loads and stores, and a table of powers in a
      # slot.
      def loops
        f = IR::Function.new("main", %w[i32 i64], "i32")
        write = f.callee("write", %w[i32 i64 i64], "i64", colocated: false)
        zero = f.iconst("i64", 0)
        one = f.iconst("i64", 1)
        ten = f.iconst("i64", 10)
        last = f.iconst("i64", 100)

        powers = f.stack_addr(f.slot(32))
        [1000, 100, 10, 1].each_with_index { |p, i| f.store(f.iconst("i64", p), powers, i * 8) }
        digits = f.stack_addr(f.slot(16))

        # Sum 1..100.
        adding, (n, total) = f.block(%w[i64 i64])
        f.jump(adding, [one, zero])
        f.switch(adding)
        summed = f.label
        more = f.label
        f.brif(f.icmp("sgt", n, last), summed, more)
        f.switch(more)
        f.jump(adding, [f.iadd(n, one), f.iadd(total, n)])

        # Then print it, one digit per power, `\n` after the last.
        f.switch(summed)
        digit, (left, count, power, at) = f.block(%w[i64 i64 i64 i64])
        f.jump(digit, [total, zero, zero, zero])
        f.switch(digit)
        step = f.fetch("i64", f.iadd(powers, power))
        again = f.label
        carry = f.label
        f.brif(f.icmp("sge", left, step), again, carry)
        f.switch(again)
        f.jump(digit, [f.isub(left, step), f.iadd(count, one), power, at])

        f.switch(carry)
        f.store(f.iadd(count, f.iconst("i64", 48)), f.iadd(digits, at))
        next_power = f.iadd(power, f.iconst("i64", 8))
        done = f.label
        rest = f.label
        f.brif(f.icmp("eq", next_power, f.iconst("i64", 32)), done, rest)
        f.switch(rest)
        f.jump(digit, [left, zero, next_power, f.iadd(at, one)])

        f.switch(done)
        f.store(ten, f.iadd(digits, f.iadd(at, one)))
        f.call_val(write, [f.iconst("i32", 1), digits, f.iconst("i64", 5)])
        f.ret(f.iconst("i32", 0))
        [[f], []]
      end
    end
  end
end
