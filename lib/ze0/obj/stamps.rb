# frozen_string_literal: true

module Ze0
  module Obj
    # What a link writes into a binary that no input decides. `ld` gives
    # every link a fresh UUID, and the ad-hoc signature hashes the pages
    # that UUID sits in, so two links of the same objects differ in these
    # two places and nowhere else. Reading them out of the load commands
    # is what lets the stage ladder compare everything else byte for byte.
    module Stamps
      MH_MAGIC_64 = 0xFEEDFACF
      LC_UUID = 0x1B
      LC_CODE_SIGNATURE = 0x1D
      HEADER = 32

      # The byte ranges of `bytes` that the linker stamps, lowest first.
      def self.of(bytes)
        magic, _cpu, _sub, _type, commands, = bytes.unpack("L<4L<")
        raise ArgumentError, "not a 64-bit Mach-O" unless magic == MH_MAGIC_64

        ranges = []
        at = HEADER
        commands.times do
          cmd, size = bytes.unpack("@#{at}L<2")
          raise ArgumentError, "a load command of #{size} bytes" if size < 8

          case cmd
          when LC_UUID then ranges << ((at + 8)...(at + 24))
          when LC_CODE_SIGNATURE
            off, len = bytes.unpack("@#{at + 8}L<2")
            ranges << (off...(off + len))
          end
          at += size
        end
        ranges.sort_by(&:first)
      end

      # `bytes` with every stamped range blanked, so that what is left is
      # what the compiler decided.
      def self.blank(bytes)
        out = bytes.dup
        of(bytes).each { |r| out[r] = "\0".b * r.size }
        out
      end
    end
  end
end
