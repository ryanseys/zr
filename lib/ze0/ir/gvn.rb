# frozen_string_literal: true

require_relative "effects"
require_relative "inst"

module Ze0
  module IR
    # Global value numbering over the dominator tree: an instruction that
    # computes what one before it already computed, in a block that
    # dominates it, reads that value instead and goes.
    #
    # What counts as the same: the opcode, the type, the condition, the
    # offset and the operands (the two of a commutative opcode in either
    # order), for an instruction with no effect and one result. A load
    # counts too, of the same address, offset and type, as long as
    # nothing on any path between the two can write its region: a store
    # to the region, a store the lowering could not place, a call whose
    # effects (`IR::Effects`) include it, or a call through a pointer.
    # A load or a store with no region of its own is placed by its
    # address where that is a static's or a slot's, with a constant
    # added: a static's word has its region, a slot is left to
    # `Forward` and `Mem2Reg`. A load of the volatile region is never
    # the same as another.
    #
    # The walk goes down the dominator tree with a scoped table, so a
    # value found in one arm of a branch is not offered to the other.
    # What the paths between a block and its dominator may write is
    # summed once a block (`between`): the writes of every block on
    # such a path, a loop's own writes among them for its header, and
    # the table forgets those regions on the way in. Within a block the
    # writes are applied in order.
    class GVN
      # The opcodes with one result and no effect, where the same
      # operands give the same answer.
      PURE = (%i[iconst stack_addr symbol_value func_addr icmp fcmp select ireduce uextend sextend bitcast
                 fcvt_from_sint fcvt_to_sint_sat] + Inst::BINOPS + Inst::FBINOPS + Inst::FUNOPS).to_set.freeze

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
        # `@by_key`: expression to `[value, region bit]`, the bit nil but
        # for a load; `@loaded`: region bit to the keys of the loads of
        # it, so a write forgets them by region; `@undo`: what the block
        # being walked changed, `[key, what it held]`, put back on the
        # way up.
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

      # A depth-first walk of the dominator tree, what each block did to
      # the table undone on the way back up, so a sibling arm sees the
      # table as their dominator left it. A list rather than recursion:
      # a chain of blocks is as long as the function.
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

      # The table forgets every load whose region `bits` may write.
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

      # Each instruction of `b` in order: one the table already holds is
      # renamed to that value and dies; one it does not is added, and a
      # write forgets what it may write.
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

      # `i` is the same as the value the table holds for `key`, or the
      # table now holds it, under `bit` when it is a load.
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

      # `{ block => bits }`: what the blocks on a path from a block's
      # immediate dominator to it may write, the dominator's own
      # instructions apart, since those run before the walk enters the
      # block. Every predecessor of a block is dominated by the block's
      # dominator, so a path in from it runs up the predecessor's own
      # dominator chain: the writes of each block on that chain, and of
      # the paths between each and its own dominator. A loop's header
      # meets its latch this way, whose chain passes the header itself:
      # the loop's writes, the header's own among them, are between the
      # header and its dominator, since the path comes round again. A
      # fixpoint over the reverse postorder, since a loop's answers feed
      # each other.
      def between_dominators
        written = {}
        @f.blocks.each { |b| written[b.name] = writes_of(b) }
        idom = @analysis.idom
        preds = @analysis.preds
        between = Hash.new(0)
        loop do
          moved = false
          @analysis.rpo.each do |b|
            name = b.name
            d = idom[name]
            bits = between[name]
            preds[name].each do |p|
              x = p
              while x && x != d
                bits |= written.fetch(x) | between[x]
                x = idom[x]
              end
            end
            next if bits == between[name]

            between[name] = bits
            moved = true
          end
          break unless moved
        end
        between
      end

      # The region bits `b`'s own instructions may write.
      def writes_of(b)
        bits = 0
        insts = b.insts
        n = 0
        while n < insts.size
          i = insts[n]
          n += 1
          case i.op
          when :store then bits |= write_bits(i)
          when :call then bits |= @effects.fetch(i.callee)
          when :call_indirect then bits |= Effects::ALL
          end
        end
        bits
      end

      # What the store `i` may write: its region's bit, or everything.
      def write_bits(i)
        region = region_of(i, i.args[1])
        region ? Effects.bit(region) : Effects::ALL
      end

      # The region of the load or store `i` through `addr`: its own, or
      # the static's or the slot's its address is placed in, or nil.
      def region_of(i, addr)
        return i.region if i.region

        root, at = @placed[addr]
        return nil if root.nil?
        return :slot if root == :slot

        Effects.static_region(root, at + i.offset) || :statics
      end

      # `{ value => [root, offset] }` for every value that is a slot's
      # address (root `:slot`) or a symbol's, or a constant past one.
      def placements
        symbol_of = @f.globals.to_h { |g| [g.gv, g.symbol] }
        const = {}
        placed = {}
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
            case i.op
            when :iconst then const[i.results[0]] = i.args[0]
            when :stack_addr then placed[i.results[0]] = [:slot, 0]
            when :symbol_value then placed[i.results[0]] = [symbol_of.fetch(i.args[0]), 0]
            when :iadd
              a, k = i.args
              a, k = k, a if const.key?(a)
              placed[i.results[0]] = [placed[a][0], placed[a][1] + const.fetch(k)] if placed.key?(a) && const.key?(k)
            end
          end
          bi += 1
        end
        placed
      end
    end
  end
end
