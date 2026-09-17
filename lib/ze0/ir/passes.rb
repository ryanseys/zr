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
      # Uses renamed in place through `@rename`, a value to the value that
      # stands for it now, followed to its end since a replacement may
      # itself be replaced.
      module Renaming
        def rename_uses
          @f.blocks.each { |b| b.insts.each { |i| rename(i) } }
        end

        def rename(i)
          i.args.map! { |a| resolve(a) }
          i.targets&.each { |(_, args)| args.map! { |a| resolve(a) } }
        end

        def resolve(v)
          v = @rename[v] while @rename.key?(v)
          v
        end
      end

      module_function

      # The unit's small leaves inlined into their callers, before the
      # pipeline runs over each function.
      def inline(functions) = Inline.run(functions)

      # The pipeline, in order.
      def run(f)
        Fold.run(f)
        Forward.run(f)
        Fold.run(f)
        Chains.run(f)
        Blocks.run(f)
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
        include Renaming

        MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        SIGNED = %w[slt sle sgt sge].freeze

        def self.run(f) = new(f).run

        def initialize(f)
          @f = f
          @types = Types.new(f).all
          @const = {}
          @rename = {}
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
          rename_uses unless @rename.empty?
          @f
        end

        private

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
          @rename[i.results[0]] = v
        end

        def fold_binop(i)
          a, b = i.args
          ka = constant(a)
          kb = constant(b)
          return become_constant(i, binop(i.op, ka, kb, bits_of(i.results[0]))) if ka && kb

          # `x op 0`, `x op 1` and their commuted forms.
          a, b, ka, kb = b, a, kb, ka if ka && !kb && Inst::COMMUTATIVE.include?(i.op)
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
        include Renaming

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
          rename_uses unless @rename.empty?
          @f
        end

        private

        def forward(b)
          known = {}
          b.insts.reject! do |i|
            rename(i)
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

        # A store forgets what it overlaps. A remembered store is at most
        # eight bytes wide, so one that overlaps starts within seven
        # bytes below this one or inside it: those keys are probed, not
        # the whole table, which a block of many stores would scan at
        # each of them.
        def remember(known, i)
          v, addr = i.args
          at = slot(addr, i.offset)
          return known.clear unless at

          root, off = at
          width = WIDTH.fetch(@types.fetch(v))
          ((off - 7)...(off + width)).each do |o|
            held = known[[root, o]]
            known.delete([root, o]) if held && o + held[1] > off
          end
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

      # A branch on a conjunction is a chain of branches: `brif (band a,
      # c) T F` becomes `brif a mid F; mid: brif c T F`, and `bor` the
      # same the other way round, so the backend fuses each compare with
      # its own branch and the second test runs only when it decides.
      # What moves into `mid` is `c`'s own chain: the instructions of the
      # block that nothing but that chain reads, all of them without
      # effect. A load moves only when no call or store follows it in
      # the block, since it would then read after them. `Zr::Function`
      # writes this shape at every gated operator: the fixnum test and
      # the gate test joined.
      class Chains
        MOVABLE = (%i[iconst stack_addr symbol_value func_addr icmp fcmp select ireduce uextend sextend bitcast
                      fcvt_from_sint fcvt_to_sint_sat] +
                   Inst::BINOPS + Inst::FBINOPS + Inst::FUNOPS).to_set.freeze

        def self.run(f) = new(f).run

        def initialize(f)
          @f = f
        end

        def run
          @uses = Hash.new(0)
          @f.blocks.each do |b|
            b.insts.each do |i|
              i.args.each { |a| @uses[a] += 1 if IR.value?(a) }
              i.targets&.each { |(_, args)| args.each { |a| @uses[a] += 1 } }
            end
          end
          @f.blocks.dup.each { |b| split(b) }
          @f
        end

        private

        def split(b)
          br = b.insts.last
          return unless br.op == :brif

          gate = b.insts.find { |i| i.results[0] == br.args[0] }
          return unless gate && (gate.op == :band || gate.op == :bor) && @uses[gate.results[0]] == 1

          first, second = gate.args
          moved = chain_of(b, second, b.insts.index(gate))
          return if moved.nil?

          yes, no = br.targets
          mid = @f.block_after(b)
          mid.insts.concat(moved)
          mid.insts << Inst.new(:brif, args: [second], targets: [yes, no])
          b.insts.reject! { |i| i.equal?(gate) || moved.any? { |m| m.equal?(i) } }
          # `a && c` asks about `c` only when `a` holds; `a || c` only
          # when it does not.
          to_mid = [mid.name, []]
          b.insts[-1] = Inst.new(:brif, args: [first], targets: gate.op == :band ? [to_mid, no] : [yes, to_mid])
        end

        # The instructions of `b` before index `stop` that make `v` and
        # feed nothing else, in order, or nil when `v` is not made in `b`
        # or its chain cannot move.
        def chain_of(b, v, stop)
          by_result = {}
          b.insts.first(stop).each { |i| by_result[i.results[0]] = i if i.results[0] }
          root = by_result[v] or return
          last_effect = b.insts.rindex { |i| %i[store call call_indirect].include?(i.op) } || -1
          moved = {}
          work = [root]
          until work.empty?
            i = work.pop
            next if moved.key?(i.object_id)
            return unless MOVABLE.include?(i.op) || (i.op == :load && b.insts.index(i) > last_effect)
            return if i.results.size > 1

            moved[i.object_id] = i
            i.args.each do |a|
              d = by_result[a]
              work << d if d && @uses[a] == 1 && IR.value?(a)
            end
          end
          # Only what the chain alone reads may move: a value read once
          # is read by the chain, since its reader is in it.
          b.insts.first(stop).select { |i| moved.key?(i.object_id) }
        end
      end

      # The blocks: one the entry does not reach goes; one that only
      # jumps on, taking nothing, is jumped past; one with a single
      # predecessor whose only successor it is joins that predecessor,
      # its parameters standing for the arguments the jump carried. Each
      # round can make the next one's work, so the rounds go on until
      # nothing moves. The entry block stays first and is never joined.
      class Blocks
        include Renaming

        def self.run(f) = new(f).run

        def initialize(f)
          @f = f
          @rename = {}
        end

        def run
          loop { break unless unreachable | bypass | merge }
          rename_uses unless @rename.empty?
          @f
        end

        private

        def by_name = @f.blocks.to_h { |b| [b.name, b] }

        def successors(b) = (b.insts.last&.targets || []).map(&:first)

        # `{ name => [[block, k], ...] }`: each edge into a block, as the
        # predecessor and which of its targets.
        def edges
          into = Hash.new { |h, k| h[k] = [] }
          @f.blocks.each do |b|
            b.insts.last&.targets&.each_with_index { |(name, _), k| into[name] << [b, k] }
          end
          into
        end

        def unreachable
          named = by_name
          seen = { @f.entry_block.name => true }
          work = [@f.entry_block]
          until work.empty?
            successors(work.pop).each do |s|
              next if seen[s]

              seen[s] = true
              work << named.fetch(s)
            end
          end
          before = @f.blocks.size
          @f.blocks.select! { |b| seen[b.name] }
          @f.blocks.size != before
        end

        def bypass
          changed = false
          into = edges
          @f.blocks.each do |b|
            next if b.equal?(@f.entry_block) || !b.params.empty? || b.insts.size != 1 || b.insts[0].op != :jump

            name, args = b.insts[0].targets[0]
            next if name == b.name

            into[b.name].each do |p, k|
              t = p.insts.last
              next unless t.op == :jump || args.empty?

              t.targets[k] = [name, args.dup]
              changed = true
            end
          end
          changed
        end

        def merge
          into = edges
          @f.blocks.each do |b|
            next if b.equal?(@f.entry_block) || into[b.name].size != 1

            p, = into[b.name][0]
            t = p.insts.last
            next if t.op != :jump || p.equal?(b)

            b.params.zip(t.targets[0][1]) { |(v, _), a| @rename[v] = a }
            p.insts.pop
            p.insts.concat(b.insts)
            @f.blocks.delete(b)
            return true
          end
          false
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
      # The small leaf functions of a unit, inlined where they are called:
      # a callee with no call, no slot and at most LIMIT instructions (a
      # value's type or class, a frozen test, which the kernel's own
      # inlining leaves as calls when they return early or loop) is copied
      # into the caller, its parameters standing for the arguments and
      # each `return` a jump to the block after the call, which takes the
      # answer as its parameter. A callee's own calls are inlined first,
      # so what is then a leaf (zr_class_of after zr_fixnum_p) serves its
      # callers as one; a cycle is left as calls. A function stays in the
      # unit whatever was copied out of it, since the unit exports it.
      class Inline
        LIMIT = 24

        def self.run(functions) = new(functions).run

        def initialize(functions)
          @by_name = functions.to_h { |f| [f.name, f] }
          @state = {}
        end

        def run
          @by_name.each_key { |name| settle(name) }
          @by_name.values
        end

        private

        # Whether the function named is a leaf small enough to inline,
        # once its own calls are inlined.
        def settle(name)
          case @state[name]
          when :leaf then return true
          when :no, :busy then return false
          end
          @state[name] = :busy
          f = @by_name.fetch(name)
          inline_into(f)
          @state[name] = leaf?(f) ? :leaf : :no
          @state[name] == :leaf
        end

        # No call, no slot read (a slot Mem2Reg promoted away is none),
        # and few enough instructions.
        def leaf?(f)
          count = 0
          f.blocks.each do |b|
            b.insts.each do |i|
              return false if %i[call call_indirect stack_addr].include?(i.op)

              count += 1
            end
          end
          count <= LIMIT
        end

        def inline_into(f)
          while (site = site_in(f))
            expand(f, *site)
          end
        end

        # A call in `f` to a function this pass inlines: its block, the
        # index of the call, the call and the callee.
        def site_in(f)
          f.blocks.each do |b|
            b.insts.each_with_index do |i, k|
              next unless i.op == :call

              c = f.callees.find { |x| x.fn == i.callee }
              next if c.nil? || c.from || !c.colocated

              target = @by_name[c.symbol]
              next if target.nil? || target.equal?(f) || !settle(target.name)

              return [b, k, i, target]
            end
          end
          nil
        end

        # The call at `k` of `b` replaced by a copy of `target`: `b` ends
        # in a jump to the copy of the entry, whose parameters are the
        # arguments themselves when no block of `target` jumps back to its
        # entry (so a constant argument folds in the copy), else carried
        # by the jump; what followed the call moves to a block after the
        # copy, whose parameter is the call's result.
        def expand(f, b, k, call, target)
          rest = f.block_after(b)
          rest.insts.concat(b.insts[(k + 1)..])
          b.insts.slice!(k..)
          rest.params.concat(call.results.zip([target.ret_type]))
          names = {}
          target.globals.each { |g| names[g.gv] = f.symbol(g.symbol, colocated: g.colocated) }
          target.callees.each do |c|
            sig = target.sigs.find { |s| s.sig == c.sig }
            names[c.fn] = f.callee(c.symbol, sig.params, sig.ret, colocated: c.colocated, from: c.from)
          end
          entry = target.entry_block
          passed = target.blocks.none? { |cb| cb.insts.last.targets&.any? { |(blk, _)| blk == entry.name } }
          entry.params.zip(call.args) { |(v, _), arg| names[v] = arg } if passed
          at = f.blocks.index(b) + 1
          copies = target.blocks.map do |cb|
            nb = f.block_beside(at)
            at += 1
            names[cb.name] = nb.name
            cb.params.each { |(v, _)| names[v] = f.value } unless passed && cb.equal?(entry)
            cb.insts.each { |i| i.results.each { |r| names[r] = f.value } }
            [cb, nb]
          end
          copies.each do |cb, nb|
            nb.params.concat(cb.params.map { |(v, t)| [names.fetch(v), t] }) unless passed && cb.equal?(entry)
            cb.insts.each { |i| nb.insts << copy(i, names, rest) }
          end
          b.insts << Inst.new(:jump, targets: [[names.fetch(entry.name), passed ? [] : call.args]])
        end

        def copy(i, names, rest)
          return Inst.new(:jump, targets: [[rest.name, i.args.map { |a| renamed(a, names) }]]) if i.op == :return

          Inst.new(i.op, type: i.type, args: i.args.map { |a| renamed(a, names) }, results: i.results.map { |r| names.fetch(r) },
                   cond: i.cond, offset: i.offset, callee: i.callee && names.fetch(i.callee, i.callee), flags: i.flags,
                   targets: i.targets&.map { |(blk, args)| [names.fetch(blk), args.map { |a| renamed(a, names) }] })
        end

        def renamed(a, names) = a.is_a?(String) ? names.fetch(a, a) : a
      end

    end
  end
end
