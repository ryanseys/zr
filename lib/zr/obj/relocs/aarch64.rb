# frozen_string_literal: true

module Zr
  module Obj
    module Relocs
      # Applies the arm64 relocations that `Backend::Aarch64::Codegen`
      # records to a known address. The bit patterns are in this file only.
      # `Obj::Patch` gives each relocation with the address of its symbol.
      # `Obj::MachO::Block` calls `encode` directly.
      module Aarch64
        KINDS = %i[branch26 page21 got_page21 pageoff12 got_pageoff12].freeze

        module_function

        # Patches `bytes` for `r` at `place`, with its symbol at `target`.
        # Returns false for a kind that is not an arm64 kind.
        def patch(bytes, r, target, place)
          return false unless KINDS.include?(r.kind)

          word = encode(r.kind, bytes[r.offset, 4].unpack1("L<"), target, place)
          raise RangeError, "#{r.kind} to #{r.symbol} is out of reach" unless word

          bytes[r.offset, 4] = [word].pack("L<")
          true
        end

        # Returns the instruction `word` at `place` with its field for `kind`
        # set to reach `target`. Returns nil when the field cannot contain the
        # offset, because a target out of range would encode a different address.
        def encode(kind, word, target, place)
          case kind
          when :branch26
            offset = (target - place) >> 2
            return nil unless fits?(offset, 26)

            (word & ~0x3FFFFFF) | (offset & 0x3FFFFFF)
          when :page21, :got_page21
            delta = ((target & ~0xFFF) - (place & ~0xFFF)) >> 12
            return nil unless fits?(delta, 21)

            (word & ~0x60FFFFE0) | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5)
          when :pageoff12
            (word & ~(0xFFF << 10)) | ((target & 0xFFF) << 10)
          when :got_pageoff12
            (word & ~(0xFFF << 10)) | (((target & 0xFFF) >> 3) << 10)
          end
        end

        # Whether a signed field of `bits` bits can contain `value`. A link
        # asks this about a million times: `between?` cost 4% of a prelink.
        def fits?(value, bits)
          half = 1 << (bits - 1)
          value >= -half && value < half
        end
      end
    end
  end
end
