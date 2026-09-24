# frozen_string_literal: true

module Zr
  module Obj
    # Applies relocations against known addresses. All formats have
    # `abs64`. Instruction relocations are specific to the instruction set;
    # `relocs` (`Backend::Aarch64::Relocs`) contains their bit patterns.
    #
    # `Obj::JIT` patches for addresses in this process, and
    # `Obj::MachO::Executable` for addresses in the image that it writes.
    # The two differ only in the address of a symbol, so each caller gives
    # only that.
    module Patch
      module_function

      # Returns the bytes of `item`, placed at `base`, with all relocations
      # applied. The block gets each relocation and returns the address of
      # its symbol. It gets the full relocation, not only the name, so that
      # a caller can tell a GOT slot from the symbol in that slot.
      def apply(item, base, relocs)
        bytes = item.bytes.b.dup
        item.relocs.each do |r|
          target = yield(r) + r.addend.to_i
          if r.kind == :abs64
            bytes[r.offset, 8] = [target].pack("Q<")
          elsif !relocs.patch(bytes, r, target, base + r.offset)
            raise ArgumentError, "no way to apply a #{r.kind} relocation"
          end
        end
        bytes
      end

      # Places `items` one after another. Each item uses the larger of its
      # own alignment and `least`. Returns the offset of each item and the
      # total size.
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
