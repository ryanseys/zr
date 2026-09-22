# frozen_string_literal: true

require "set"

require_relative "function"
require_relative "gvn"
require_relative "licm"
require_relative "statics"
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
          return if @rename.empty?

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
      #
      # `Fold` runs twice because `Forward` uncovers constants for it: a
      # load whose value it forwards is a constant the first fold could
      # not see. It earns the second pass -- built without it, the
      # runtime's object grows by 223 KB, and the whole pass costs 0.6 s
      # of the 9.3 s that object takes. `Statics` runs after `Forward`,
      # whose slot loads it need not walk, and before `Chains`, so the
      # gate test it leaves as a value splits into the branch chain;
      # `GVN` after it, so the values it made are numbered with the rest,
      # and `LICM` after that, so a loop's turns hold one of each value.
      def run(f)
        Fold.run(f)
        Forward.run(f)
        Statics.run(f)
        GVN.run(f)
        LICM.run(f)
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
      # operand or its constant, a multiply, unsigned division or
      # remainder by a power of two is a shift or a mask, a `select` on
      # a constant is the arm taken, a widening of a constant is a
      # constant, and a `brif` on a constant is a `jump`. Uses are
      # renamed in place; the block the untaken arm named may then be
      # unreachable, which is `Blocks`'s to remove.
      class Fold
        include Renaming

        MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        SIGNED = %w[slt sle sgt sge].freeze

        def self.run(f) = new(f).run

        # Only a constant's type is ever asked for, and a constant's type
        # is known where it is made, so `@const` keeps each constant's
        # number with its type and no pass types the whole function.
        def initialize(f)
          @f = f
          @const = {}
          @rename = {}
          @jumped = false
        end

        # Blocks in layout order. A block whose predecessors all come
        # before it is settled on entry: no edge from any of them reaches
        # it unless that predecessor was reached and its terminator, once
        # folded, still names it. A settled block no edge reaches is dead,
        # and its own edges count for nothing; a parameter every edge that
        # does reach it gives the same constant is that constant. A block
        # a later one jumps back to (a loop's head) is never settled.
        def run
          arriving = Hash.new { |h, name| h[name] = [] }
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
          # A use laid out before its definition, which a loop can do,
          # is renamed on a second pass.
          rename_uses unless @rename.empty?
          # A `brif` folded to a `jump` took an edge away.
          @f.changed!(@jumped ? :cfg : :insts)
        end

        private

        def fold_insts(b)
          @added = []
          b.insts.each_with_index do |i, at|
            @at = at
            rename(i)
            fold(i)
          end
          @added.reverse_each { |at, inst| b.insts.insert(at, inst) }
        end

        # A constant operand made where the instruction being folded
        # stands, for a fold that needs one the function does not hold.
        def constant_before(n, type)
          v = @f.value
          @added << [@at, Inst.new(:iconst, type: type, args: [n], results: [v])]
          @const[v] = [n, type]
          v
        end

        # Each parameter of `b` that every edge in `edges` gives the same
        # constant, known as that constant.
        def enter(b, edges)
          b.params.each_with_index do |(v, type), k|
            first = constant(edges[0][k])
            next unless first && edges.all? { |args| constant(args[k]) == first }

            @const[v] = [first, type]
          end
        end

        # The number `v` holds, masked to its type, or nil.
        def constant(v)
          k, type = @const[v]
          k && k & MASK.fetch(type)
        end

        # The type of the constant `v`.
        def constant_type(v) = @const.fetch(v).last

        def fold(i)
          case i.op
          when :iconst then @const[i.results[0]] = [i.args[0], i.type]
          when *Inst::BINOPS then fold_binop(i)
          when :icmp then fold_compare(i)
          when :select then fold_select(i)
          when :uextend, :ireduce, :sextend then fold_width(i)
          when :brif then fold_branch(i)
          end
        end

        # A result's type names the width of its arithmetic: 64 bits for
        # `i64`, 32 for anything narrower.
        def bits_of(type) = type == "i64" ? 64 : 32

        def signed(raw, bits)
          top = 1 << (bits - 1)
          raw >= top ? raw - (top << 1) : raw
        end

        def quotient(a, b) = (a.negative?) == (b.negative?) ? a.abs / b.abs : -(a.abs / b.abs)

        def become_constant(i, n, type)
          i.op = :iconst
          i.type = type
          i.args = [n & MASK.fetch(type)]
          @const[i.results[0]] = [i.args[0], type]
        end

        def become(i, v)
          @rename[i.results[0]] = v
        end

        def fold_binop(i)
          a, b = i.args
          ka = constant(a)
          kb = constant(b)
          # A binop's operands and result share a type, one of them here
          # a constant's.
          type = i.type || constant_type(ka ? a : b) if ka || kb
          return become_constant(i, binop(i.op, ka, kb, bits_of(type)), type) if ka && kb

          # `x op 0`, `x op 1` and their commuted forms.
          a, b, ka, kb = b, a, kb, ka if ka && !kb && Inst::COMMUTATIVE.include?(i.op)
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

        def power_of_two?(n) = (n & (n - 1)).zero?

        # `i` as the cheaper `op` of `a` and the constant `n`: a multiply,
        # an unsigned division or remainder by a power of two is a shift
        # or a mask.
        def reduce(i, op, a, n, type)
          i.op = op
          i.args = [a, constant_before(n, type)]
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

        def fold_select(i)
          c, a, b = i.args
          return become(i, a) if a == b

          k = constant(c)
          become(i, k.zero? ? b : a) if k
        end

        def fold_width(i)
          k = constant(i.args[0])
          return unless k

          from = constant_type(i.args[0])
          k = signed(k, from == "i8" ? 8 : 32) if i.op == :sextend
          become_constant(i, k, i.type)
        end

        def fold_branch(i)
          yes, no = i.targets
          k = constant(i.args[0])
          return unless k || yes[0] == no[0]

          i.op = :jump
          i.args = []
          i.targets = [k.nil? || k != 0 ? yes : no]
          @jumped = true
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
          @f.changed!(:insts)
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
          width = Types::WIDTH.fetch(@types.fetch(v))
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
          return false unless Types::WIDTH.fetch(i.type) == width && @types.fetch(v) == i.type

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
          @uses = @f.analysis.uses
          @f.blocks.dup.each { |b| split(b) }
          @f.changed!(:cfg)
        end

        private

        def split(b)
          br = b.insts.last
          return unless br.op == :brif

          gate = b.insts.find { |i| i.results[0] == br.args[0] }
          return unless gate && (gate.op == :band || gate.op == :bor) && @uses.fetch(gate.results[0], 0) == 1

          first, second = gate.args
          # A second operand read elsewhere too (`GVN` makes one of two
          # alike) stays where it is, computed ahead of both branches;
          # only one read by the gate alone moves behind the first test.
          moved = @uses.fetch(second, 0) == 1 ? chain_of(b, second, b.insts.index(gate)) : []
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
              work << d if d && @uses.fetch(a, 0) == 1 && IR.value?(a)
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
          @f.changed!(:cfg)
        end

        private

        # `{ name => [[block, k], ...] }`: each edge into a block, as the
        # predecessor and which of its targets.
        def edges
          into = Hash.new { |h, k| h[k] = [] }
          @f.blocks.each do |b|
            b.insts.last&.targets&.each_with_index { |(name, _), k| into[name] << [b, k] }
          end
          into
        end

        # The blocks in reverse postorder are the reached ones.
        def unreachable
          reached = @f.analysis.rpo
          return false if reached.size == @f.blocks.size

          @f.blocks.replace(@f.blocks & reached)
          @f.changed!(:cfg)
          true
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
          @f.changed!(:cfg) if changed
          changed
        end

        # Every such block joined in one round, in layout order: a block
        # that takes another's instructions takes its edges out too, so a
        # later block whose predecessor was joined joins the block that
        # took it. A predecessor laid out after the block it takes moves
        # up into that block's place: the layout keeps every definition
        # ahead of the blocks it dominates, which `Types` walks it for.
        def merge
          into = edges
          joined = {}.compare_by_identity
          laid = {}
          at = 0
          while at < @f.blocks.size
            laid[@f.blocks[at].name] = at
            at += 1
          end
          @f.blocks.each do |b|
            next if b.nil? || b.equal?(@f.entry_block) || into[b.name].size != 1

            p, = into[b.name][0]
            t = p.insts.last
            next if t.op != :jump || p.equal?(b)

            b.params.zip(t.targets[0][1]) { |(v, _), a| @rename[v] = a }
            p.insts.pop
            p.insts.concat(b.insts)
            b.insts.last&.targets&.each_with_index do |(name, _), k|
              into[name].map! { |from, at| from.equal?(b) && at == k ? [p, k] : [from, at] }
            end
            joined[b] = true
            at = laid.fetch(b.name)
            from = laid.fetch(p.name)
            next if from < at

            @f.blocks[at] = p
            @f.blocks[from] = nil
            laid[p.name] = at
          end
          return false if joined.empty?

          @f.blocks.reject! { |b| b.nil? || joined.key?(b) }
          @f.changed!(:cfg)
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

        # Each value's readers counted once; an instruction found dead
        # takes one reader off each of its operands, and an operand's
        # instruction left with none is dead in turn.
        def self.run(f)
          readers = f.analysis.uses.dup
          readers.default = 0
          defined = {}
          f.blocks.each { |b| b.insts.each { |i| i.results.each { |r| defined[r] = i } } }
          dead = {}.compare_by_identity
          work = f.blocks.flat_map { |b| b.insts.select { |i| unread?(i, readers) } }
          while (i = work.pop)
            next if dead.key?(i)

            dead[i] = true
            i.args.each do |a|
              next unless IR.value?(a)

              readers[a] -= 1
              d = defined[a]
              work << d if d && readers[a].zero? && unread?(d, readers)
            end
          end
          return f if dead.empty?

          f.blocks.each { |b| b.insts.reject! { |i| dead.key?(i) } }
          f.changed!(:insts)
        end

        def self.unread?(i, readers) = PURE.include?(i.op) && i.results.none? { |r| readers[r].positive? }
      end
      # The small leaf functions of a unit, inlined where they are called:
      # a callee with no call, at most LIMIT instructions and at most
      # SLOT_BYTES of stack (a value's type or class, a frozen test, which
      # the kernel's own inlining leaves as calls when they loop) is
      # copied into the caller, its parameters standing for the arguments,
      # its slots made the caller's own, and each `return` a jump to the
      # block after the call, which takes the answer as its parameter. A
      # callee's own calls are inlined first, so what is then a leaf
      # (zr_class_of after zr_fixnum_p) serves its callers as one; a cycle
      # is left as calls. A function stays in the unit whatever was copied
      # out of it, since the unit exports it.
      class Inline
        LIMIT = 24
        # Every site the callee is copied to holds its slots, so a large
        # buffer stays behind a call.
        SLOT_BYTES = 128

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

        # No call, few enough instructions, and little stack in the slots
        # still read (a slot Mem2Reg promoted away is none).
        def leaf?(f)
          count = 0
          read = []
          f.blocks.each do |b|
            b.insts.each do |i|
              return false if %i[call call_indirect].include?(i.op)

              read << i.args[0] if i.op == :stack_addr
              count += 1
            end
          end
          count <= LIMIT && read.uniq.sum { |slot| slot_of(f, slot).bytes } <= SLOT_BYTES
        end

        def slot_of(f, name) = f.slots.fetch(name.delete_prefix("ss").to_i)

        def inline_into(f)
          expanded = false
          while (site = site_in(f))
            expand(f, *site)
            expanded = true
          end
          f.changed!(:cfg) if expanded
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
          target.blocks.each do |cb|
            cb.insts.each { |i| names[i.args[0]] ||= f.slot(slot_of(target, i.args[0]).bytes) if i.op == :stack_addr }
          end
          target.callees.each do |c|
            sig = target.sigs.find { |s| s.sig == c.sig }
            names[c.fn] = f.callee(c.symbol, sig.params, sig.ret, colocated: c.colocated, from: c.from, effects: c.effects)
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
                   targets: i.targets&.map { |(blk, args)| [names.fetch(blk), args.map { |a| renamed(a, names) }] },
                   region: i.region)
        end

        def renamed(a, names) = a.is_a?(String) ? names.fetch(a, a) : a
      end

    end
  end
end
