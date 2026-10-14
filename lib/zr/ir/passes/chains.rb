# frozen_string_literal: true

module Zr
  module IR
    module Passes
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
        # The instructions after which a load cannot move: each can write
        # what the load reads.
        WRITES = %i[store call call_indirect].freeze

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
          insts = b.insts
          # The index of the instruction that makes each value before `stop`.
          at = {} #: Hash[String, Integer]
          [stop, insts.size].min.times do |k|
            r = insts[k].results[0]
            at[r] = k if r
          end
          root = at[v] or return
          last_effect = insts.rindex { |i| WRITES.include?(i.op) } || -1
          moved = {} #: Hash[Integer, true]
          work = [root]
          until work.empty?
            k = work.pop #: Integer
            next if moved.key?(k)

            i = insts[k]
            return unless MOVABLE.include?(i.op) || (i.op == :load && k > last_effect)
            return if i.results.size > 1

            moved[k] = true
            i.args.each do |a|
              d = at[a]
              work << d if d && @uses.fetch(a, 0) == 1 && IR.value?(a)
            end
          end
          # Only values that the chain alone reads can move. A value with one
          # reader is read by the chain, because its reader is in the chain.
          moved.keys.sort!.map { |k| insts[k] }
        end
      end
    end
  end
end
