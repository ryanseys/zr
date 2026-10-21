# frozen_string_literal: true

# Derived from CRuby's ext/digest (each algorithm's own license, and Ruby or
# BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# crc32init.c, in ruby: Digest::CRC32, the CRC-32 of zlib (reflected,
# polynomial 0xedb88320), its digest the four bytes big-endian.
require "digest"

module Digest
  class CRC32 < Base
    # CRC32_Init, CRC32_Update and CRC32_Finish over the kernel's CRC.
    module Hasher
      module_function

      def init = 0
      def copy(crc) = crc
      def update(crc, input) = Primitive.zr_zlib_checksum(0, crc, Primitive.zr_str_operand(input))
      def finish(crc) = [crc].pack("N")
    end
    private_constant :Hasher

    Primitive.zr_hidden_set(self, :metadata, Digest.send(:metadata, nil, 0, 4, 8, false, Hasher))
  end
end
