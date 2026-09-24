# frozen_string_literal: true

module Zr
  module Backend
    module Aarch64
      # The arm64 relocations `Codegen` records, applied against an address
      # that is already decided: the bit patterns, once. `Obj::Patch` hands
      # each one here with the address its symbol has, and
      # `Obj::MachO::Executable` asks for the word itself.
      module Relocs
        KINDS = %i[branch26 page21 got_page21 pageoff12 got_pageoff12].freeze

        module_function

        # Patches `bytes` for `r` at `place`, its symbol at `target`; false
        # for a kind that is not arm64's.
        def patch(bytes, r, target, place)
          return false unless KINDS.include?(r.kind)

          word = encode(r.kind, bytes[r.offset, 4].unpack1("L<"), target, place)
          raise RangeError, "#{r.kind} to #{r.symbol} is out of reach" unless word

          bytes[r.offset, 4] = [word].pack("L<")
          true
        end

        # The instruction `word` at `place` with its field for `kind` set to
        # reach `target`, or nil when the field cannot hold it: a target out
        # of reach would be written as some other address.
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

        # Whether a field of `bits` signed bits holds `value`.
        def fits?(value, bits) = value.between?(-(1 << (bits - 1)), (1 << (bits - 1)) - 1)
      end
    end
  end
end
