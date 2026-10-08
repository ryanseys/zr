# frozen_string_literal: true

require_relative "function"
require_relative "../config"
require_relative "gvn"
require_relative "licm"
require_relative "statics"
require_relative "switches"
require_relative "threads"
require_relative "types"
require_relative "verify"

module Zr
  module IR
    # The passes that each emitter runs on a function before assembly. They
    # run in one order from one place, so the aarch64 backend, the wasm
    # backend and eval support all get the same IR.
    #
    # Each pass keeps these invariants: a value has one definition, and the
    # definition dominates its uses. The entry block stays first and keeps
    # its parameters. Each block ends in a terminator. A `brif` has no
    # arguments. A store to a record slot is never removed, because the
    # collector reads it as a root.
    module Passes
      # Renames uses in place through `@rename` (a value to its replacement).
      # The lookup follows the chain, because a replacement can also have a
      # replacement.
      module Renaming
        # @rbs @f: Function
        # @rbs @rename: Hash[String, untyped]

        #: () -> void
        def rename_uses
          @f.blocks.each { |b| b.insts.each { |i| rename(i) } }
        end

        #: (Inst i) -> void
        def rename(i)
          return if @rename.empty?

          i.args.map! { |a| resolve(a) }
          i.targets&.each { |(_, args)| args.map! { |a| resolve(a) } }
        end

        #: (untyped v) -> untyped
        def resolve(v)
          v = @rename[v] while @rename.key?(v)
          v
        end
      end

      module_function

      # Inlines the small leaf functions of the unit into their callers,
      # before the pipeline runs on each function.
      #: (Array[Function] functions) -> Array[Function]
      def inline(functions) = Inline.run(functions)

      # The pipeline, in order.
      #
      # `Fold` runs two times, because `Forward` finds constants that the
      # first fold cannot see. Without the second fold, the runtime object is
      # 223 KB larger; the pass costs 0.6 s of the 9.3 s build of that object.
      # `Statics` runs after `Forward`, so it does not see the slot loads, and
      # before `Chains`, so its gate test splits into the branch chain. `GVN`
      # runs after `Statics` to number its new values. `LICM` runs last, so a
      # loop has one copy of each value. `Threads` runs after `Chains`, whose
      # split tests it can skip. `Switches` runs after both, on the tests
      # that are left, and `Blocks` drops the blocks they leave.
      #: (Function f) -> Function
      def run(f)
        Fold.run(f)
        Forward.run(f)
        Statics.run(f)
        GVN.run(f)
        LICM.run(f)
        Fold.run(f)
        Chains.run(f)
        Threads.run(f)
        Switches.run(f)
        Blocks.run(f)
        DCE.run(f)
        f
      end

      # Runs the pipeline and then the checks, and returns the IR for an
      # emitter. The dominance and type checks are slow, so a build runs them
      # only when `ZR_VERIFY=1`. The checks that run the IR against the
      # interpreter always run.
      #: (Function f, ?strict: bool) -> Function
      def prepare(f, strict: Config.current.verify?)
        run(f)
        Verify.check(f, strict: strict)
      end

      # Constant folding. An integer instruction on constants becomes its
      # result, with the same rules as `IR::Interp`: arithmetic narrower than
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

        # Folds the bit operations on constants, with the same rules as
        # `IR::Interp`.
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

      # Store-to-load forwarding for stack slots. A load from a slot at a
      # constant offset gets the value of the last store to that slot in the
      # block, if nothing between them can write the slot. The pass deletes
      # the load; the store stays as a root for the collector.
      # `Zr::Lower::Function` stores the receiver and arguments of each send
      # in record slots and loads them back at once, so this occurs at each
      # send. A call (which can get a frame address that the function passed
      # out) or a store through a non-slot address clears all known stores.
      # A store to a slot clears the stores that it overlaps.
      class Forward
        # A slot place is `[root address, offset]`. `known` maps a place to
        # `[value, width]`.
        # @rbs @types: Hash[String, String?]
        # @rbs @const: Hash[String, Integer]
        # @rbs @roots: Hash[String, [String, Integer]]

        include Renaming

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        #: (Function f) -> void
        def initialize(f)
          @f = f
          @types = Types.new(f).all
          @const = {}
          @roots = {}
          @rename = {}
        end

        #: () -> Function
        def run
          @f.blocks.each { |b| forward(b) }
          rename_uses unless @rename.empty?
          @f.changed!(:insts)
        end

        private

        #: (Block b) -> void
        def forward(b)
          known = {} #: Hash[[String, Integer], [String, Integer]]
          b.insts.reject! do |i|
            rename(i)
            case i.op
            when :iconst then @const[i.results[0]] = i.args[0]
            when :stack_addr then @roots[i.results[0]] = [i.results[0], 0]
            when :iadd then note_sum(i)
            when :store then remember(known, i)
            when :load then next true if forwarded?(known, i)
            when :call, :call_indirect then known.clear
            end
            false
          end
        end

        # `v = base + k`, where `base` is a slot address, is that slot address
        # plus a constant.
        #: (Inst i) -> void
        def note_sum(i)
          a, b = i.args
          a, b = b, a if @const.key?(a)
          root, k = @roots[a]
          return unless root && @const.key?(b)

          @roots[i.results[0]] = [root, k + @const.fetch(b)]
        end

        # `[root, offset]` of the slot byte at `addr` plus `off`, or nil.
        #: (untyped addr, Integer off) -> [String, Integer]?
        def slot(addr, off)
          root, k = @roots[addr]
          root && [root, k + off]
        end

        # A store clears the known stores that it overlaps. A known store is at
        # most 8 bytes wide, so an overlapping store starts at most 7 bytes
        # below this one, or inside it. The pass checks only those keys. A scan
        # of the full table at each store is slow in a block with many stores.
        #: (Hash[[String, Integer], [String, Integer]] known, Inst i) -> void
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

        # Whether the load reads all of a known store's value, with the same
        # type.
        #: (Hash[[String, Integer], [String, Integer]] known, Inst i) -> bool
        def forwarded?(known, i)
          at = slot(i.args[0], i.offset)
          return false unless at && (held = known[at])

          v, width = held
          return false unless Types::WIDTH.fetch(i.type) == width && @types.fetch(v) == i.type

          @rename[i.results[0]] = v
          true
        end
      end

      # Changes a branch on a conjunction into a chain of branches:
      # `brif (band a, c) T F` becomes `brif a mid F; mid: brif c T F`. `bor`
      # is the same with the arms swapped. The backend then fuses each compare
      # with its branch, and the second test runs only when it is necessary.
      # The chain of `c` moves into `mid`: the instructions of the block that
      # only that chain reads, all without effects. A load moves only when no
      # call or store follows it in the block. If the chain cannot move, or
      # `c` comes from a different block, `c` stays before both branches.
      # The pass splits both halves again, so `a || b || c` becomes three
      # branches. `Zr::Lower::Function` makes this shape at each gated
      # operator: the fixnum test and the gate test.
      class Chains
        # @rbs @f: Function
        # @rbs @uses: Hash[String, Integer]
        # @rbs @after: Hash[Block, Array[Block]]

        MOVABLE =(%i[iconst stack_addr symbol_value func_addr gates icmp fcmp select ireduce uextend sextend bitcast
                      fcvt_from_sint fcvt_to_sint_sat] +
                   Inst::BINOPS + Inst::BITOPS + Inst::FBINOPS + Inst::FUNOPS).to_set.freeze

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        #: (Function f) -> void
        def initialize(f)
          @f = f
        end

        #: () -> Function
        def run
          @uses = @f.analysis.uses
          @after = {} #: Hash[Block, Array[Block]]
                   .compare_by_identity
          # A split gives two branches to examine again: the branch of the block
          # (now on the first operand), and the branch of `mid` (on the second).
          work = @f.blocks.dup
          until work.empty?
            b = work.pop #: Block
            mid = split(b)
            work.push(b, mid) if mid
          end
          lay_out unless @after.empty?
          @f.changed!(:cfg)
        end

        private

        # Puts each new block just after the block that it split, before
        # the blocks of that block's earlier splits: the layout of an insert
        # into `blocks` at each split, which was quadratic (0.5 s of a
        # function of 23,000 blocks).
        #: () -> void
        def lay_out
          laid = [] #: Array[Block]
          work = @f.blocks.reverse
          until work.empty?
            b = work.pop #: Block
            laid << b
            work.concat(@after[b].reverse) if @after.key?(b)
          end
          @f.blocks.replace(laid)
        end

        # Returns the block of the second test, or nil.
        #: (Block b) -> Block?
        def split(b)
          br = b.insts.last
          return unless br.op == :brif

          at = b.insts.index { |i| i.results[0] == br.args[0] }
          return unless at

          gate = b.insts[at]
          return unless (gate.op == :band || gate.op == :bor) && @uses.fetch(gate.results[0], 0) == 1

          first, second = gate.args
          # If other instructions also read the second operand (`GVN` can merge
          # two equal values), it stays before both branches. Only an operand
          # that only the gate reads moves after the first test.
          moved = (@uses.fetch(second, 0) == 1 && chain_of(b, second, at)) || []
          yes, no = br.targets #: [[String, Array[String]], [String, Array[String]]]
          mid = @f.unplaced_block
          (@after[b] ||= []).unshift(mid)
          mid.insts.concat(moved)
          mid.insts << Inst.new(:brif, args: [second], targets: [yes, no])
          b.insts.reject! { |i| i.equal?(gate) || moved.any? { |m| m.equal?(i) } }
          # `a && c` tests `c` only when `a` is true; `a || c` only when `a` is
          # false.
          to_mid = [mid.name, []] #: [String, Array[String]]
          b.insts[-1] = Inst.new(:brif, args: [first], targets: gate.op == :band ? [to_mid, no] : [yes, to_mid])
          mid
        end

        # Returns, in order, the instructions of `b` before index `stop` that
        # make `v` and feed nothing else. Returns nil when `v` is not made in
        # `b` or its chain cannot move.
        #: (Block b, untyped v, Integer stop) -> Array[Inst]?
        def chain_of(b, v, stop)
          by_result = {} #: Hash[String, Inst]
          b.insts.first(stop).each { |i| by_result[i.results[0]] = i if i.results[0] }
          root = by_result[v] or return
          last_effect = b.insts.rindex { |i| %i[store call call_indirect].include?(i.op) } || -1
          moved = {} #: Hash[Integer, Inst]
          work = [root]
          until work.empty?
            i = work.pop #: Inst
            next if moved.key?(i.object_id)
            return unless MOVABLE.include?(i.op) || (i.op == :load && (b.insts.index(i) || -1) > last_effect)
            return if i.results.size > 1

            moved[i.object_id] = i
            i.args.each do |a|
              d = by_result[a]
              work << d if d && @uses.fetch(a, 0) == 1 && IR.value?(a)
            end
          end
          # Only values that the chain alone reads can move. A value with one
          # reader is read by the chain, because its reader is in the chain.
          b.insts.first(stop).select { |i| moved.key?(i.object_id) }
        end
      end

      # Simplifies the blocks. The pass removes a block that the entry does
      # not reach. It skips a block that only jumps and has no parameters. It
      # joins a block to its single predecessor when the block is the only
      # successor of that predecessor; the block parameters become the jump
      # arguments. One round can make work for the next, so rounds continue
      # until nothing changes. The entry block stays first and is never joined.
      class Blocks
        include Renaming

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        #: (Function f) -> void
        def initialize(f)
          @f = f
          @rename = {}
        end

        #: () -> Function
        def run
          loop { break unless pruned? | bypassed? | merged? }
          rename_uses unless @rename.empty?
          @f.changed!(:cfg)
        end

        private

        # `{ name => [[block, k], ...] }`: each edge into a block, as the
        # predecessor and the index of the target.
        #: () -> Hash[String, Array[[Block, Integer]]]
        def edges
          into = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[[Block, Integer]]]
          @f.blocks.each do |b|
            b.insts.last&.targets&.each_with_index { |(name, _), k| into[name] << [b, k] }
          end
          into
        end

        # Each step below changes the function and answers whether it did.

        # Drops the unreachable blocks. The blocks in reverse postorder are
        # the reachable blocks.
        #: () -> bool
        def pruned?
          reached = @f.analysis.rpo
          return false if reached.size == @f.blocks.size

          @f.blocks.replace(@f.blocks & reached)
          @f.changed!(:cfg)
          true
        end

        #: () -> bool
        def bypassed?
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

        # Joins all such blocks in one round, in layout order. A block that
        # takes the instructions of another block also takes its outgoing
        # edges. So a later block whose predecessor was joined joins the block
        # that took it. A predecessor after its successor in the layout moves up
        # to the successor's position. Thus each definition stays before the
        # blocks that it dominates, which `Types` needs.
        #: () -> bool
        def merged?
          into = edges
          joined = {} #: Hash[Block, bool]
                   .compare_by_identity
          laid = @f.blocks.each_with_index.to_h { |b, at| [b.name, at] }
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

            # The hole stays until the `reject!` below.
            holes = @f.blocks #: Array[Block?]
            holes[at] = p
            holes[from] = nil
            laid[p.name] = at
          end
          return false if joined.empty?

          @f.blocks.reject! { |b| b.nil? || joined.key?(b) }
          @f.changed!(:cfg)
          true
        end
      end

      # Dead code elimination. The pass removes an instruction with no
      # effect whose result nothing reads. It continues to a fixpoint, so it
      # removes a full chain in one run. A call, a store and a terminator
      # always stay.
      class DCE
        PURE = (%i[iconst stack_addr symbol_value func_addr gates icmp fcmp select ireduce uextend sextend bitcast load
                   fcvt_from_sint fcvt_to_sint_sat] +
                Inst::BINOPS + Inst::BITOPS + Inst::FBINOPS + Inst::FUNOPS + Inst::PAIRS).to_set.freeze

        # Counts the readers of each value one time. When the pass removes an
        # instruction, it subtracts one reader from each operand. An operand
        # with zero readers is then dead.
        #: (Function f) -> Function
        def self.run(f)
          readers = f.analysis.uses.dup
          readers.default = 0
          defined = {} #: Hash[String, Inst]
          f.blocks.each { |b| b.insts.each { |i| i.results.each { |r| defined[r] = i } } }
          dead = {} #: Hash[Inst, bool]
                 .compare_by_identity
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

        #: (Inst i, Hash[String, Integer] readers) -> bool
        def self.unread?(i, readers) = PURE.include?(i.op) && i.results.none? { |r| readers[r].positive? }
      end
      # Inlines the small leaf functions of a unit at their call sites. A leaf
      # has no call, at most LIMIT instructions and at most SLOT_BYTES of
      # stack (for example a type or class test, or a frozen test, that the
      # kernel leaves as a call in a loop). The pass copies the callee into
      # the caller: the parameters become the arguments, the slots become
      # caller slots, and each `return` becomes a jump to the block after the
      # call, which takes the result as its parameter. The pass inlines the
      # calls in a callee first, so a callee can become a leaf (zr_class_of
      # after zr_fixnum_p). A cycle stays as calls. The original function
      # stays in the unit, because the unit exports it.
      class Inline
        # @rbs @by_name: Hash[String, Function]
        # @rbs @outputs: Array[Function]
        # @rbs @sources: Hash[String, Function]
        # @rbs @state: Hash[String, Symbol]
        # @rbs @calls: Hash[String, Hash[String, bool]]

        LIMIT = 24
        # Each call site gets a copy of the callee slots, so a callee with a
        # large buffer stays a call.
        SLOT_BYTES = 128

        #: (Array[Function] functions) -> Array[Function]
        def self.run(functions) = new(functions).run

        # `sources` are functions that can be inlined but that this pass
        # does not change, because a pass inlined them already: the kernel
        # under a core file (`Cache::Lowering::Core`).
        #: (Array[Function] functions, ?sources: Array[Function]) -> void
        def initialize(functions, sources: [])
          @by_name = functions.to_h { |f| [f.name, f] }
          @outputs = @by_name.values
          @sources = {}
          sources.each { |f| @by_name[f.name] ||= @sources[f.name] = f }
          @state = {}
          @calls = Hash.new { |h, name| h[name] = {} }
        end

        #: () -> Array[Function]
        def run
          @outputs.each { |f| inlinable?(f.name) }
          @outputs
        end

        # Whether the function `name` is a leaf that this pass inlines, once
        # it ran.
        #: (String name) -> bool
        def settled_leaf?(name) = @state[name] == :leaf

        # The colocated symbols that the calls of the function `name` named,
        # before this pass inlined any of them: a `Cache::Lowering::Core` entry depends on
        # what each of them is.
        #: (String name) -> Array[String]
        def calls(name) = @calls[name].keys

        private

        # Whether the function is a leaf that is small enough to inline, after
        # its own calls are inlined. The first question inlines them (not
        # those of a source, which are inlined already).
        #: (String name) -> bool
        def inlinable?(name)
          case @state[name]
          when :leaf then return true
          when :no, :busy then return false
          end
          @state[name] = :busy
          f = @by_name.fetch(name)
          inline_into(f) unless @sources.key?(name)
          @state[name] = leaf?(f) ? :leaf : :no
          @state[name] == :leaf
        end

        # No call, not too many instructions, and little stack in the slots that
        # are still read (a slot that Mem2Reg promoted does not count).
        #: (Function f) -> bool
        def leaf?(f)
          count = 0
          read = [] #: Array[String]
          f.blocks.each do |b|
            b.insts.each do |i|
              return false if %i[call call_indirect stack_args].include?(i.op)

              read << i.args[0] if i.op == :stack_addr
              count += 1
            end
          end
          count <= LIMIT && read.uniq.sum { |slot| slot_of(f, slot).bytes } <= SLOT_BYTES
        end

        #: (Function f, String name) -> Slot
        def slot_of(f, name) = f.slots.fetch(name.delete_prefix("ss").to_i)

        # Expands each site in turn. The blocks before a site's block have no
        # site, and the copy of the callee comes after it, so the search for
        # the next site starts at that block.
        #: (Function f) -> void
        def inline_into(f)
          expanded = false
          from = 0
          while (site = site_in(f, from))
            from, b, k, call, target = site
            expand(f, b, k, call, target)
            expanded = true
          end
          f.changed!(:cfg) if expanded
        end

        # A call in `f`, from the block at `from` on, to a function that this
        # pass inlines: the index of its block, the block, the index of the
        # call, the call and the callee.
        #: (Function f, Integer from) -> [Integer, Block, Integer, Inst, Function]?
        def site_in(f, from)
          callees = {} #: Hash[String, Callee]
          f.callees.each { |c| callees[c.fn] ||= c }
          (from...f.blocks.size).each do |n|
            b = f.blocks[n]
            b.insts.each_with_index do |i, k|
              next unless i.op == :call

              c = callees[i.callee]
              next if c.nil? || c.from || !c.colocated

              @calls[f.name][c.symbol] = true

              target = @by_name[c.symbol]
              next if target.nil? || target.equal?(f) || !inlinable?(target.name)

              return [n, b, k, i, target]
            end
          end
          nil
        end

        # Replaces the call at `k` of `b` with a copy of `target`. `b` ends
        # with a jump to the copy of the entry. If no block of `target` jumps
        # back to its entry, the entry parameters become the arguments (so a
        # constant argument folds in the copy). If not, the jump passes them.
        # The instructions after the call move to a block after the copy. That
        # block takes the result of the call as its parameter.
        #: (Function f, Block b, Integer k, Inst call, Function target) -> void
        def expand(f, b, k, call, target)
          rest = f.block_after(b)
          rest.insts.concat(b.insts.drop(k + 1))
          b.insts.slice!(k..)
          # A call has a result only when its callee returns a value.
          results = call.results.zip([target.ret_type]) #: Array[[String, String]]
          rest.params.concat(results)
          names = {} #: Hash[String, String]
          target.globals.each { |g| names[g.gv] = f.symbol(g.symbol, colocated: g.colocated) }
          target.blocks.each do |cb|
            cb.insts.each { |i| names[i.args[0]] ||= f.slot(slot_of(target, i.args[0]).bytes) if i.op == :stack_addr }
          end
          target.callees.each do |c|
            sig = target.sigs.find { |s| s.sig == c.sig } #: Sig
            names[c.fn] = f.callee(c.symbol, sig.params, sig.ret, colocated: c.colocated, from: c.from, effects: c.effects)
          end
          entry = target.entry_block
          passed = target.blocks.none? { |cb| cb.insts.last.targets&.any? { |(blk, _)| blk == entry.name } }
          entry.params.zip(call.args) { |(v, _), arg| names[v] = arg } if passed
          at = (f.blocks.index(b) or raise "#{f.name}: #{b.name} is not in the function") + 1
          copies = target.blocks.map do |cb|
            nb = f.block_beside(at)
            at += 1
            names[cb.name] = nb.name
            cb.params.each { |(v, _)| names[v] = f.value } unless passed && cb.equal?(entry)
            cb.insts.each { |i| i.results.each { |r| names[r] = f.value } }
            [cb, nb]
          end #: Array[[Block, Block]]
          copies.each do |cb, nb|
            nb.params.concat(cb.params.map { |(v, t)| [names.fetch(v), t] }) unless passed && cb.equal?(entry)
            cb.insts.each { |i| nb.insts << copy(i, names, rest) }
          end
          b.insts << Inst.new(:jump, targets: [[names.fetch(entry.name), passed ? [] : call.args]])
        end

        #: (Inst i, Hash[String, String] names, Block rest) -> Inst
        def copy(i, names, rest)
          return Inst.new(:jump, targets: [[rest.name, i.args.map { |a| renamed(a, names) }]]) if i.op == :return

          Inst.new(i.op, type: i.type, args: i.args.map { |a| renamed(a, names) }, results: i.results.map { |r| names.fetch(r) },
                   cond: i.cond, offset: i.offset, callee: i.callee && names.fetch(i.callee, i.callee), flags: i.flags,
                   targets: i.targets&.map { |(blk, args)| [names.fetch(blk), args.map { |a| renamed(a, names) }] },
                   region: i.region)
        end

        #: (untyped a, Hash[String, String] names) -> untyped
        def renamed(a, names) = a.is_a?(String) ? names.fetch(a, a) : a
      end

    end
  end
end
