# frozen_string_literal: true

module Zr
  module Obj
    module MachO
      # Finds the bytes of a binary that do not depend on the link inputs.
      # `ld` gives every link a new UUID, and the ad-hoc signature hashes
      # the pages that contain the UUID. Thus two links of the same objects
      # differ only in these two ranges. With these ranges from the load
      # commands, the stage builds can compare all other bytes.
      module Stamps
        MH_MAGIC_64 = 0xFEEDFACF
        LC_UUID = 0x1B
        LC_CODE_SIGNATURE = 0x1D
        HEADER = 32

        # The byte ranges of `bytes` that differ for each link, lowest first.
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
      end
    end
  end
end
