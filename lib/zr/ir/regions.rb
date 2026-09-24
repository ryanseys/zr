# frozen_string_literal: true

require_relative "effects"

module Zr
  module IR
    # What a pass that keeps a value read from memory across other
    # instructions asks of them: the region a load or a store reaches,
    # and the regions a block's instructions may write. `GVN` and
    # `LICM` share it.
    #
    # A load or a store with no region of its own is placed by its
    # address where that is a static's or a slot's, with a constant
    # added: a static's word has its region (`Effects.static_region`),
    # a slot is `:slot`, which `Forward` and `Mem2Reg` reason about by
    # address. One placed nowhere may reach anything.
    #
    # The including pass sets `@f`, `@placed` (from `placements`) and
    # `@effects`, `{ callee => bits }`.
    module Regions
      private

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

      # The region of the load or store `i` through `addr`: its own, or
      # the static's or the slot's its address is placed in, or nil.
      def region_of(i, addr)
        return i.region if i.region

        root, at = @placed[addr]
        return nil if root.nil?
        return :slot if root == :slot

        Effects.static_region(root, at + i.offset) || :statics
      end

      # What the store `i` may write: its region's bit, or everything.
      def write_bits(i)
        region = region_of(i, i.args[1])
        region ? Effects.bit(region) : Effects::ALL
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
    end
  end
end
