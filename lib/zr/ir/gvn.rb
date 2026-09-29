# frozen_string_literal: true

require_relative "effects"
require_relative "inst"
require_relative "regions"

module Zr
  module IR
    # Global value numbering over the dominator tree. An instruction may
    # compute the same value as an earlier instruction in a dominating
    # block. The pass then uses the earlier value and deletes the
    # instruction.
    #
    # Two pure, single-result instructions are the same when the opcode,
    # type, condition, offset and operands are equal. The two operands of
    # a commutative opcode can be in either order. Two loads are the same
    # when the address, offset and type are equal and no path between
    # them can write the region. A region is written by a store to it, a
    # store with no known region, a call whose `IR::Effects` include it,
    # or an indirect call. `Regions` gives the region of a load or store.
    # A load of the volatile region is never the same as another load.
    #
    # The walk uses a scoped table, so a value from one arm of a branch
    # is not used in the other arm. For each block, `between` gives the
    # regions that the paths from its dominator can write (for a loop
    # header, this includes the writes of the loop). The table removes
    # those loads when the walk enters the block. In a block, the pass
    # applies writes in order.
    class GVN
      include Regions

      # The opcodes with one result and no effect. The same operands
      # give the same result.
      PURE = (%i[iconst stack_addr symbol_value func_addr icmp fcmp select ireduce uextend sextend bitcast
                 fcvt_from_sint fcvt_to_sint_sat] + Inst::BINOPS + Inst::BITOPS + Inst::FBINOPS + Inst::FUNOPS).to_set.freeze

      def self.run(f) = new(f).run

      def initialize(f)
        @f = f
        @analysis = f.analysis
        @rename = {}
        @dead = {}.compare_by_identity
        @effects = f.callees.to_h { |c| [c.fn, c.effects || Effects::ALL] }
      end

      def run
        children = Hash.new { |h, k| h[k] = [] }
        @analysis.idom.each { |b, d| children[d] << b if d }
        @block = @f.blocks.to_h { |b| [b.name, b] }
        @placed = placements
        @between = between_dominators
        # `@by_key`: expression to `[value, region bit]`. The bit is nil
        # for all instructions other than a load.
        # `@loaded`: region bit to the keys of the loads of that region,
        # so that a write can remove them by region.
        # `@undo`: the changes of the current block, as `[key, old entry]`.
        # The walk puts them back when it leaves the block.
        @by_key = {}
        @loaded = Hash.new { |h, k| h[k] = [] }
        walk(@f.entry_block.name, children)
        return @f if @dead.empty?

        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          insts.reject! { |i| @dead.key?(i) }
          n = 0
          while n < insts.size
            i = insts[n]
            i.args.map! { |a| resolve(a) }
            targets = i.targets
            if targets
              k = 0
              while k < targets.size
                targets[k][1].map! { |a| resolve(a) }
                k += 1
              end
            end
            n += 1
          end
          bi += 1
        end
        @f.changed!(:insts)
      end

      private

      def resolve(v)
        v = @rename[v] while @rename.key?(v)
        v
      end

      # A depth-first walk of the dominator tree. When the walk leaves a
      # block, it undoes the changes of that block to the table. Thus a
      # sibling sees the table as their dominator left it. The walk uses
      # a work list, not recursion, because a chain of blocks can be as
      # long as the function.
      def walk(root, children)
        work = [[root, nil]]
        until work.empty?
          name, undo = work.pop
          if undo
            undo.reverse_each { |key, held| held ? keep(key, held) : @by_key.delete(key) }
            next
          end

          @undo = []
          forget(@between.fetch(name, 0))
          number(@block.fetch(name))
          work << [name, @undo]
          children[name].each { |c| work << [c, nil] }
        end
      end

      def keep(key, held)
        @by_key[key] = held
        @loaded[held[1]] << key if held[1]
      end

      # Removes from the table every load whose region `bits` can write.
      def forget(bits)
        return if bits.zero?

        @loaded.each do |bit, keys|
          next if (bits & bit).zero?

          keys.each do |key|
            held = @by_key.delete(key)
            @undo << [key, held] if held
          end
          keys.clear
        end
      end

      # Numbers each instruction of `b` in order. If the table contains
      # the instruction, the pass renames its result to the table value
      # and deletes it. If not, the pass adds it. A write removes the
      # loads of the regions that it can write.
      def number(b)
        insts = b.insts
        n = 0
        while n < insts.size
          i = insts[n]
          n += 1
          i.args.map! { |a| resolve(a) }
          case i.op
          when :load
            region = region_of(i, i.args[0])
            next if region == :volatile || region == :slot

            take(i, [:load, i.type, i.args[0], i.offset, region], region ? Effects.bit(region) : Effects::ALL)
          when :store then forget(write_bits(i))
          when :call then forget(@effects.fetch(i.callee))
          when :call_indirect then forget(Effects::ALL)
          else
            next unless PURE.include?(i.op) && i.results.size == 1

            args = i.args
            args = args.sort_by(&:to_s) if Inst::COMMUTATIVE.include?(i.op)
            take(i, [i.op, i.type, i.cond, i.offset, *args], nil)
          end
        end
      end

      # If the table has a value for `key`, `i` becomes that value.
      # If not, the table adds `i` (under `bit` when `i` is a load).
      def take(i, key, bit)
        held = @by_key[key]
        if held
          @rename[i.results[0]] = held[0]
          @dead[i] = true
        else
          @by_key[key] = [i.results[0], bit]
          @undo << [key, nil]
          @loaded[bit] << key if bit
        end
      end

      # Returns `{ block => bits }`: the regions that the blocks on a path
      # from the immediate dominator of a block to that block can write.
      # The instructions of the dominator are not included, because they
      # run before the walk enters the block. The block's dominator
      # dominates each predecessor, so the path goes up the dominator
      # chain of the predecessor. For a loop header, the chain from the
      # latch includes the header, so the writes of the loop (and of the
      # header) are included. The loop calculates a fixpoint over the
      # reverse postorder, because the values of a loop depend on each other.
      # It works on the positions of the blocks in `blocks`, not their
      # names: a step up the dominator chain is then an array read (0.16 s
      # to 0.04 s for a function of 23,000 blocks). A predecessor that the
      # entry does not reach has no dominator: its writes count, and the
      # walk stops there.
      def between_dominators
        blocks = @f.blocks
        at = {}
        blocks.each_with_index { |b, n| at[b.name] = n }
        written = blocks.map { |b| writes_of(b) }
        idom = @analysis.idom
        up = blocks.map { |b| (d = idom[b.name]) && at.fetch(d) }
        order = @analysis.rpo.map { |b| at.fetch(b.name) }
        preds = @analysis.preds
        from = order.to_h { |n| [n, preds[blocks[n].name].map { |p| at.fetch(p) }] }
        bits_of = Array.new(blocks.size, 0)
        loop do
          moved = false
          order.each do |n|
            d = up[n]
            bits = bits_of[n]
            from[n].each do |x|
              while x && x != d
                bits |= written[x] | bits_of[x]
                x = up[x]
              end
            end
            next if bits == bits_of[n]

            bits_of[n] = bits
            moved = true
          end
          break unless moved
        end
        between = Hash.new(0)
        order.each { |n| between[blocks[n].name] = bits_of[n] unless bits_of[n].zero? }
        between
      end
    end
  end
end
