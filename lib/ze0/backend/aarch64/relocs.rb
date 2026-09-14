# frozen_string_literal: true

module Ze0
  module Backend
    module Aarch64
      # The arm64 relocations `Codegen` records, applied against an address
      # that is already decided: the bit patterns, once. `Obj::Patch` hands
      # each one here with the address its symbol has.
      module Relocs
        module_function

        # Patches `bytes` for `r` at `place`, its symbol at `target`; false
        # for a kind that is not arm64's.
        def patch(bytes, r, target, place)
          case r.kind
          when :branch26
            word(bytes, r.offset) { |w| (w & ~0x3FFFFFF) | (((target - place) >> 2) & 0x3FFFFFF) }
          when :page21, :got_page21
            delta = ((target & ~0xFFF) - (place & ~0xFFF)) >> 12
            word(bytes, r.offset) { |w| (w & ~0x60FFFFE0) | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5) }
          when :pageoff12
            word(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | ((target & 0xFFF) << 10) }
          when :got_pageoff12
            word(bytes, r.offset) { |w| (w & ~(0xFFF << 10)) | (((target & 0xFFF) >> 3) << 10) }
          else return false
          end
          true
        end

        # One instruction word, rewritten by the block.
        def word(bytes, offset)
          bytes[offset, 4] = [yield(bytes[offset, 4].unpack1("L<"))].pack("L<")
        end
      end
    end
  end
end
