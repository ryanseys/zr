# frozen_string_literal: true

module Ze0
  module Obj
    # Applying an arm64 relocation: the six kinds ze0 emits, each against
    # an address that is already decided.
    #
    # `Obj::JIT` patches for addresses in this process and `Obj::Exe` for
    # addresses in an image it is writing. Where a symbol lives is the
    # only thing the two disagree about, so that is all either one says;
    # the bit patterns are here, once.
    module Patch
      module_function

      # `item`'s bytes with every relocation applied, the item itself
      # placed at `base`. The block is given each relocation and answers
      # the address its symbol has -- the relocation and not just the
      # name, so a caller can tell a GOT slot from the symbol it holds.
      def apply(item, base)
        bytes = item.bytes.b.dup
        item.relocs.each do |r|
          target = yield(r) + r.addend.to_i
          place = base + r.offset
          case r.kind
          when :abs64
            bytes[r.offset, 8] = [target].pack("Q<")
          when :branch26
            word(bytes, r.offset) { |w| (w & ~0x3FFFFFF) | (((target - place) >> 2) & 0x3FFFFFF) }
          when :page21, :got_page21
            delta = ((target & ~0xFFF) - (place & ~0xFFF)) >> 12
            word(bytes, r.offset) { |w| (w & ~0x60FFFFE0) | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5) }
          when :pageoff12
            word(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | ((target & 0xFFF) << 10) }
          when :got_pageoff12
            word(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | (((target & 0xFFF) >> 3) << 10) }
          else raise ArgumentError, "no way to apply a #{r.kind} relocation"
          end
        end
        bytes
      end

      # One instruction word, rewritten by the block.
      def word(bytes, offset)
        bytes[offset, 4] = [yield(bytes[offset, 4].unpack1("L<"))].pack("L<")
      end

      # `items` one after another, each at its own alignment or `least`,
      # whichever is coarser. Answers the offset of each and the size of
      # them all.
      def layout(items, least)
        at = []
        size = 0
        items.each do |item|
          size = align(size, [item.align, least].max)
          at << [item, size]
          size += item.size
        end
        { at: at, size: size }
      end

      def align(n, a) = (n + a - 1) & ~(a - 1)
    end
  end
end
