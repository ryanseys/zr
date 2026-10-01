# frozen_string_literal: true

require_relative "effects"

module Zr
  module IR
    # Region helpers for a pass that keeps a loaded value across other
    # instructions: the region of a load or a store, and the regions that
    # the instructions of a block can write. `GVN` and `LICM` use them.
    #
    # A load or a store with no region gets one from its address, when the
    # address is a static or a slot plus a constant. A static word gets its
    # region from `Effects.static_region`. A slot is `:slot`, which
    # `Forward` and `Mem2Reg` handle by address. An access with no region
    # and an unknown address can reach any region.
    #
    # The pass that includes this module sets `@f`, `@placed` (from
    # `placements`) and `@effects` (`{ callee => bits }`).
    module Regions
      private

      # `{ value => [root, offset] }` for each value that is the address of a
      # slot (root `:slot`) or of a symbol, or one of these plus a constant.
      def placements
        symbol_of = @f.globals.to_h { |g| [g.gv, g.symbol] }
        const = {}
        placed = {}
        @f.blocks.each do |b|
          b.insts.each do |i|
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
        end
        placed
      end

      # The region of the load or store `i` through `addr`: its own region,
      # or the region of the static or slot at its address, or nil.
      def region_of(i, addr)
        return i.region if i.region

        root, at = @placed[addr]
        return nil if root.nil?
        return :slot if root == :slot

        Effects.static_region(root, at + i.offset) || :statics
      end

      # The regions that the store `i` can write: the bit of its region, or all.
      def write_bits(i)
        region = region_of(i, i.args[1])
        region ? Effects.bit(region) : Effects::ALL
      end

      # The region bits that the instructions of `b` can write.
      def writes_of(b)
        bits = 0
        b.insts.each do |i|
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
