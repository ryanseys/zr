# frozen_string_literal: true

require "set"

require_relative "function"
require_relative "types"
require_relative "verify"

module Ze0
  module IR
    # The passes every emitter runs over a function before it is
    # assembled, in one order from one place, so the aarch64 backend, the
    # wasm backend and the eval road all see the same IR.
    #
    # What every pass keeps: a value is defined once and its definition
    # dominates its uses, the entry block stays first and keeps its
    # parameters, every block ends in a terminator, a `brif` carries no
    # arguments, and a store to a record slot is never removed, because
    # the collector reads it as a root.
    module Passes
      module_function

      # The pipeline, in order.
      def run(f)
        Fold.run(f)
        Forward.run(f)
        Fold.run(f)
        DCE.run(f)
        f
      end

      # The pipeline and then the checks: what an emitter takes. The
      # dominance and type checks cost a pass of their own, so a build
      # runs them only under `ZE0_VERIFY=1`; the checks that run the IR
      # against the interpreter always do.
      def prepare(f, strict: ENV["ZE0_VERIFY"] == "1")
        run(f)
        Verify.check(f, strict: strict)
      end

      # Constant folding. An integer instruction of constants becomes the
      # constant it answers, as `IR::Interp` answers it: arithmetic below
      # `i64` runs 32 bits wide, a shift takes its amount modulo the
      # width, a division by zero answers zero and a remainder by zero
      # the dividend. An identity (`x + 0`, `x * 1`, `x & 0`) is its
      # operand or its constant, a `select` on a constant is the arm
      # taken, a widening of a constant is a constant, and a `brif` on a
      # constant is a `jump`. Uses are renamed in place; the block the
      # untaken arm named may then be unreachable, which is `Blocks`'s to
      # remove.
      class Fold
        MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        SIGNED = %w[slt sle sgt sge].freeze

        def self.run(f) = new(f).run

        def initialize(f)
          @f = f
          @types = Types.new(f).all
          @const = {}
          @alias = {}
        end

        def run
          @f.blocks.each do |b|
            b.insts.each do |i|
              rename(i)
              fold(i)
            end
          end
          # A use laid out before its definition, which a loop can do,
          # is renamed on a second pass.
          @f.blocks.each { |b| b.insts.each { |i| rename(i) } } unless @alias.empty?
          @f
        end

        private

        def rename(i)
          i.args.map! { |a| resolve(a) }
          i.targets&.each { |(_, args)| args.map! { |a| resolve(a) } }
        end

        def resolve(v)
          v = @alias[v] while @alias.key?(v)
          v
        end

        # The number `v` holds, masked to its type, or nil.
        def constant(v)
          k = @const[v]
          k && k & MASK.fetch(@types.fetch(v))
        end

        def fold(i)
          case i.op
          when :iconst then @const[i.results[0]] = i.args[0]
          when *Inst::BINOPS then fold_binop(i)
          when :icmp then fold_compare(i)
          when :select then fold_select(i)
          when :uextend, :ireduce, :sextend then fold_width(i)
          when :brif then fold_branch(i)
          end
        end

        # The type of an instruction's result names the width of its
        # arithmetic: 64 bits for `i64`, 32 for anything narrower.
        def bits_of(v) = @types.fetch(v) == "i64" ? 64 : 32

        def signed(raw, bits)
          top = 1 << (bits - 1)
          raw >= top ? raw - (top << 1) : raw
        end

        def quotient(a, b) = (a.negative?) == (b.negative?) ? a.abs / b.abs : -(a.abs / b.abs)

        def become_constant(i, n)
          r = i.results[0]
          i.op = :iconst
          i.type = @types.fetch(r)
          i.args = [n & MASK.fetch(i.type)]
          @const[r] = i.args[0]
        end

        def become(i, v)
          @alias[i.results[0]] = v
        end

        def fold_binop(i)
          a, b = i.args
          ka = constant(a)
          kb = constant(b)
          return become_constant(i, binop(i.op, ka, kb, bits_of(i.results[0]))) if ka && kb

          # `x op 0`, `x op 1` and their commuted forms.
          a, b, ka, kb = b, a, kb, ka if ka && !kb && %i[iadd imul band bor bxor].include?(i.op)
          return unless kb

          case i.op
          when :iadd, :isub, :bor, :bxor, :ishl, :ushr, :sshr then become(i, a) if kb.zero?
          when :imul
            become(i, a) if kb == 1
            become_constant(i, 0) if kb.zero?
          when :udiv, :sdiv then become(i, a) if kb == 1
          when :band
            become_constant(i, 0) if kb.zero?
            become(i, a) if kb == MASK.fetch(@types.fetch(a))
          end
        end

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

        def fold_compare(i)
          a = constant(i.args[0])
          b = constant(i.args[1])
          return unless a && b

          bits = bits_of(i.args[0])
          a, b = signed(a, bits), signed(b, bits) if SIGNED.include?(i.cond)
          held = case i.cond
                 when "eq" then a == b
                 when "ne" then a != b
                 when "slt", "ult" then a < b
                 when "sle", "ule" then a <= b
                 when "sgt", "ugt" then a > b
                 when "sge", "uge" then a >= b
                 end
          become_constant(i, held ? 1 : 0)
        end

        def fold_select(i)
          c, a, b = i.args
          return become(i, a) if a == b

          k = constant(c)
          become(i, k.zero? ? b : a) if k
        end

        def fold_width(i)
          k = constant(i.args[0])
          return unless k

          from = @types.fetch(i.args[0])
          k = signed(k, from == "i8" ? 8 : 32) if i.op == :sextend
          become_constant(i, k)
        end

        def fold_branch(i)
          yes, no = i.targets
          k = constant(i.args[0])
          return unless k || yes[0] == no[0]

          i.op = :jump
          i.args = []
          i.targets = [k.nil? || k != 0 ? yes : no]
        end
      end

      # Store-to-load forwarding over stack slots. A load from a slot at
      # a constant offset, in the block of the last store there with
      # nothing between that could write it, is that store's value: the
      # load goes and the store stays, as a root the collector reads.
      # `Zr::Function` stages a send's receiver and arguments in record
      # slots and reads them back at once, which is this shape at every
      # send. What can write a slot: a call, which may reach the frame
      # through an address the function passed out, and a store through
      # an address that is not a slot's; either forgets everything. A
      # store to a slot forgets what it overlaps.
      class Forward
        WIDTH = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze

        def self.run(f) = new(f).run

        def initialize(f)
          @f = f
          @types = Types.new(f).all
          @const = {}
          @roots = {}
          @rename = {}
        end

        def run
          @f.blocks.each { |b| forward(b) }
          return @f if @rename.empty?

          @f.blocks.each do |b|
            b.insts.each do |i|
              i.args.map! { |a| @rename.fetch(a, a) }
              i.targets&.each { |(_, args)| args.map! { |a| @rename.fetch(a, a) } }
            end
          end
          @f
        end

        private

        def forward(b)
          known = {}
          b.insts.reject! do |i|
            i.args.map! { |a| @rename.fetch(a, a) }
            case i.op
            when :iconst then @const[i.results[0]] = i.args[0]
            when :stack_addr then @roots[i.results[0]] = [i.results[0], 0]
            when :iadd then note_sum(i)
            when :store then remember(known, i)
            when :load then next true if forwarded(known, i)
            when :call, :call_indirect then known.clear
            end
            false
          end
        end

        # `v = base + k` past a slot's address is the slot's address and
        # a constant more.
        def note_sum(i)
          a, b = i.args
          a, b = b, a if @const.key?(a)
          root, k = @roots[a]
          return unless root && @const.key?(b)

          @roots[i.results[0]] = [root, k + @const.fetch(b)]
        end

        # `[root, offset]` of the slot byte `addr` and `off` name, or nil.
        def slot(addr, off)
          root, k = @roots[addr]
          root && [root, k + off]
        end

        def remember(known, i)
          v, addr = i.args
          at = slot(addr, i.offset)
          return known.clear unless at

          width = WIDTH.fetch(@types.fetch(v))
          known.delete_if { |(root, off), (_, w)| root == at[0] && off < at[1] + width && at[1] < off + w }
          known[at] = [v, width]
        end

        # Whether the load reads what a remembered store put, whole and
        # as the same type.
        def forwarded(known, i)
          at = slot(i.args[0], i.offset)
          return false unless at && (held = known[at])

          v, width = held
          return false unless WIDTH.fetch(i.type) == width && @types.fetch(v) == i.type

          @rename[i.results[0]] = v
          true
        end
      end

      # Dead code: an instruction with a result nothing reads and no
      # effect is removed, to a fixpoint, so a chain of them goes at once.
      # A call, a store and a terminator stay whatever their results.
      class DCE
        PURE = (%i[iconst stack_addr symbol_value func_addr icmp fcmp select ireduce uextend sextend bitcast load
                   fcvt_from_sint fcvt_to_sint_sat] +
                Inst::BINOPS + Inst::FBINOPS + Inst::FUNOPS + Inst::PAIRS).to_set.freeze

        def self.run(f)
          loop do
            used = Set.new
            f.blocks.each do |b|
              b.insts.each do |i|
                i.args.each { |a| used << a if IR.value?(a) }
                i.targets&.each { |(_, args)| args.each { |a| used << a } }
              end
            end
            removed = false
            f.blocks.each do |b|
              b.insts.reject! do |i|
                next false unless PURE.include?(i.op) && i.results.none? { |r| used.include?(r) }

                removed = true
              end
            end
            break unless removed
          end
          f
        end
      end
    end
  end
end
