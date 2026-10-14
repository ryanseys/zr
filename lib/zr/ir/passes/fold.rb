# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Constant folding. An integer instruction on constants becomes its
      # result, with the same rules as the tests' IR interpreter
      # (test/support/ir_interp.rb): arithmetic narrower than
      # `i64` is 32 bits wide, a shift uses its amount modulo the width, a
      # division by zero gives zero, and a remainder by zero gives the
      # dividend. An identity (`x + 0`, `x * 1`, `x & 0`) becomes its operand
      # or constant. A multiply, unsigned division or remainder by a power of
      # two becomes a shift or a mask. A `select` on a constant becomes the
      # selected arm. A widened constant becomes a constant. A `brif` on a
      # constant becomes a `jump`. The pass renames uses in place. `Blocks`
      # removes blocks that become unreachable.
      class Fold
        # @rbs @const: Hash[String, [Integer, String?]]
        # @rbs @jumped: bool
        # @rbs @added: Array[[Integer, Inst]]
        # @rbs @at: Integer

        include Renaming

        MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        SIGNED = %w[slt sle sgt sge].freeze

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        # The pass needs only the types of constants, and it knows each type
        # where it makes the constant. So `@const` keeps the number and type of
        # each constant, and no pass calculates types for the whole function.
        #: (Function f) -> void
        def initialize(f)
          @f = f
          @const = {}
          @rename = {}
          @jumped = false
        end

        # Visits blocks in layout order. A block is settled on entry when all
        # its predecessors come before it. An edge reaches a settled block only
        # if its predecessor was reached and the folded terminator still targets
        # the block. A settled block that no edge reaches is dead, and its edges
        # do not count. If each reaching edge gives a parameter the same
        # constant, the parameter is that constant. A loop header is never
        # settled.
        #: () -> Function
        def run
          arriving = Hash.new { |h, name| h[name] = [] } #: Hash[String, Array[Array[String]]]
          laid = @f.blocks.each_with_index.to_h { |b, at| [b.name, at] }
          before = @f.analysis.preds
          @f.blocks.each_with_index do |b, at|
            settled = !b.equal?(@f.entry_block) && before[b.name].all? { |p| laid.fetch(p) < at }
            edges = arriving[b.name]
            next fold_insts(b) if settled && edges.empty?

            enter(b, edges) if settled
            fold_insts(b)
            b.insts.last&.targets&.each { |(name, args)| arriving[name] << args }
          end
          # A use before its definition in the layout (possible in a loop) is
          # renamed in a second pass.
          rename_uses unless @rename.empty?
          # A `brif` that became a `jump` removed an edge.
          @f.changed!(@jumped ? :cfg : :insts)
        end

        private

        #: (Block b) -> void
        def fold_insts(b)
          @added = []
          b.insts.each_with_index do |i, at|
            @at = at
            rename(i)
            fold(i)
          end
          @added.reverse_each { |at, inst| b.insts.insert(at, inst) }
        end

        # Makes a constant operand just before the instruction at `n`, when the
        # function does not have that constant.
        #: (Integer n, String? type) -> String
        def constant_before(n, type)
          v = @f.value
          @added << [@at, Inst.new(:iconst, type: type, args: [n], results: [v])]
          @const[v] = [n, type]
          v
        end

        # Sets each parameter of `b` to a constant when every edge in `edges`
        # gives it that same constant.
        #: (Block b, Array[Array[String]] edges) -> void
        def enter(b, edges)
          b.params.each_with_index do |(v, type), k|
            first = constant(edges[0][k])
            next unless first && edges.all? { |args| constant(args[k]) == first }

            @const[v] = [first, type]
          end
        end

        # The number in `v`, masked to its type, or nil.
        #: (untyped v) -> Integer?
        def constant(v)
          k, type = @const[v]
          k && k & MASK.fetch(type)
        end

        # The type of the constant `v`.
        #: (untyped v) -> String?
        def constant_type(v) = @const.fetch(v).last

        #: (Inst i) -> void
        def fold(i)
          case i.op
          when :iconst then @const[i.results[0]] = [i.args[0], i.type]
          when *Inst::BINOPS then fold_binop(i)
          when *Inst::BITOPS then fold_bitop(i)
          when :icmp then fold_compare(i)
          when :select then fold_select(i)
          when :uextend, :ireduce, :sextend then fold_width(i)
          when :brif then fold_branch(i)
          when :switch then fold_switch(i)
          end
        end

        # The type of a result gives the width of its arithmetic: 64 bits for
        # `i64`, 32 bits for a narrower type.
        #: (String? type) -> Integer
        def bits_of(type) = type == "i64" ? 64 : 32

        #: (Integer raw, Integer bits) -> Integer
        def signed(raw, bits)
          top = 1 << (bits - 1)
          raw >= top ? raw - (top << 1) : raw
        end

        #: (Integer a, Integer b) -> Integer
        def quotient(a, b) = (a.negative?) == (b.negative?) ? a.abs / b.abs : -(a.abs / b.abs)

        #: (Inst i, Integer n, String? type) -> void
        def become_constant(i, n, type)
          i.op = :iconst
          i.type = type
          i.args = [n & MASK.fetch(type)]
          @const[i.results[0]] = [i.args[0], type]
        end

        #: (Inst i, untyped v) -> void
        def become(i, v)
          @rename[i.results[0]] = v
        end

        #: (Inst i) -> void
        def fold_binop(i)
          a, b = i.args
          ka = constant(a)
          kb = constant(b)
          # The operands and result of a binop have one type. Here, one operand
          # is a constant, so its type is known.
          type = i.type || constant_type(ka ? a : b) if ka || kb
          return become_constant(i, binop(i.op, ka, kb, bits_of(type)), type) if ka && kb

          # `x op 0`, `x op 1` and their commuted forms.
          a, kb = b, ka if ka && !kb && Inst::COMMUTATIVE.include?(i.op)
          return unless kb

          case i.op
          when :iadd, :isub, :bor, :bxor, :ishl, :ushr, :sshr then become(i, a) if kb.zero?
          when :imul
            become(i, a) if kb == 1
            become_constant(i, 0, type) if kb.zero?
            reduce(i, :ishl, a, kb.bit_length - 1, type) if kb > 1 && power_of_two?(kb)
          when :udiv
            become(i, a) if kb == 1
            reduce(i, :ushr, a, kb.bit_length - 1, type) if kb > 1 && power_of_two?(kb)
          when :urem then reduce(i, :band, a, kb - 1, type) if kb > 1 && power_of_two?(kb)
          when :sdiv then become(i, a) if kb == 1
          when :band
            become_constant(i, 0, type) if kb.zero?
            become(i, a) if kb == MASK.fetch(type)
          end
        end

        #: (Integer n) -> bool
        def power_of_two?(n) = (n & (n - 1)).zero?

        # Replaces `i` with the cheaper `op` of `a` and the constant `n`. A
        # multiply, unsigned division or remainder by a power of two becomes a
        # shift or a mask.
        #: (Inst i, op op, untyped a, Integer n, String? type) -> void
        def reduce(i, op, a, n, type)
          i.op = op
          i.args = [a, constant_before(n, type)]
        end

        # The return is untyped: the `case` has no `else`, so Steep adds
        # `false` (`nil & mask`), but each opcode in `Inst::BINOPS` has a
        # branch.
        #: (op op, Integer a, Integer b, Integer bits) -> untyped
        def binop(op, a, b, bits)
          mask = (1 << bits) - 1
          a &= mask
          b &= mask
          sa = signed(a, bits)
          sb = signed(b, bits)
          case op
          when :iadd then a + b
          when :isub then a - b
          when :imul then a * b
          when :band then a & b
          when :bor then a | b
          when :bxor then a ^ b
          when :udiv then b.zero? ? 0 : a / b
          when :sdiv then b.zero? ? 0 : quotient(sa, sb)
          when :urem then b.zero? ? a : a - (a / b) * b
          when :srem then b.zero? ? a : sa - quotient(sa, sb) * sb
          when :ishl then a << (b % bits)
          when :ushr then a >> (b % bits)
          when :sshr then sa >> (b % bits)
          end & mask
        end

        #: (Inst i) -> void
        def fold_compare(i)
          a = constant(i.args[0])
          b = constant(i.args[1])
          return unless a && b

          bits = bits_of(constant_type(i.args[0]))
          a, b = signed(a, bits), signed(b, bits) if SIGNED.include?(i.cond)
          held = case i.cond
                 when "eq" then a == b
                 when "ne" then a != b
                 when "slt", "ult" then a < b
                 when "sle", "ule" then a <= b
                 when "sgt", "ugt" then a > b
                 when "sge", "uge" then a >= b
                 end
          become_constant(i, held ? 1 : 0, "i8")
        end

        #: (Inst i) -> void
        def fold_select(i)
          c, a, b = i.args
          return become(i, a) if a == b

          k = constant(c)
          become(i, k.zero? ? b : a) if k
        end

        # Folds the bit operations on constants, with the same rules as the
        # tests' IR interpreter.
        #: (Inst i) -> void
        def fold_bitop(i)
          k = constant(i.args[0])
          return unless k

          type = constant_type(i.args[0])
          bits = bits_of(type)
          k &= MASK.fetch(type)
          answer = case i.op
                   when :ctz then k.zero? ? bits : (k & -k).bit_length - 1
                   when :clz then bits - k.bit_length
                   when :popcnt then k.to_s(2).count("1")
                   when :bswap then [k].pack(bits == 64 ? "Q>" : "L>").unpack1(bits == 64 ? "Q<" : "L<")
                   end #: Integer
          become_constant(i, answer, type)
        end

        #: (Inst i) -> void
        def fold_width(i)
          k = constant(i.args[0])
          return unless k

          from = constant_type(i.args[0])
          k = signed(k, from == "i8" ? 8 : 32) if i.op == :sextend
          become_constant(i, k, i.type)
        end

        #: (Inst i) -> void
        def fold_branch(i)
          yes, no = i.targets #: [[String, Array[String]], [String, Array[String]]]
          k = constant(i.args[0])
          return unless k || yes[0] == no[0]

          i.op = :jump
          i.args = []
          i.targets = [k.nil? || k != 0 ? yes : no]
          @jumped = true
        end

        #: (Inst i) -> void
        def fold_switch(i)
          k = constant(i.args[0])
          return unless k

          at = (1...i.args.size).find { |n| i.args[n] == k }
          i.op = :jump
          i.targets = [i.targets[at || 0]]
          i.args = []
          @jumped = true
        end
      end
    end
  end
end
