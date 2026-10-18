# frozen_string_literal: true

module Zr
  module Obj
    module Relocs
      # Applies the x86-64 relocations that `Backend::X86_64::Codegen`
      # records to a known address: each is a 32-bit displacement from the
      # place, with the addend that ends the instruction.
      module X86_64
        KINDS = %i[pc32 plt32 gotpcrel].freeze #: Array[reloc_kind]

        module_function

        #: (reloc_kind kind) -> bool
        def handles?(kind) = KINDS.include?(kind)

        # Patches `bytes` for `r` at `place`, with its symbol (and addend)
        # at `target`.
        #: (String bytes, Reloc r, Integer target, Integer place) -> String
        def patch(bytes, r, target, place)
          distance = target - place
          raise RangeError, "#{r.kind} to #{r.symbol} is out of reach" unless distance.between?(-(1 << 31), (1 << 31) - 1)

          bytes[r.offset, 4] = [distance].pack("l<")
        end
      end
    end
  end
end
