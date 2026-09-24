# frozen_string_literal: true

module Zr
  module Obj
    # Applying relocations against addresses that are already decided.
    # `abs64` is every format's own; an instruction's relocations belong to
    # its instruction set, and `relocs` (`Backend::Aarch64::Relocs`) holds
    # their bit patterns.
    #
    # `Obj::JIT` patches for addresses in this process and
    # `Obj::MachO::Executable` for addresses in an image it is writing.
    # Where a symbol lives is the only thing the two disagree about, so that
    # is all either one says.
    module Patch
      module_function

      # `item`'s bytes with every relocation applied, the item itself
      # placed at `base`. The block is given each relocation and answers
      # the address its symbol has -- the relocation and not just the
      # name, so a caller can tell a GOT slot from the symbol it holds.
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
