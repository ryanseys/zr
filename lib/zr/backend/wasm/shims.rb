# frozen_string_literal: true

module Zr
  module Backend
    module Wasm
      class Codegen
        # The libc calls that the module defines itself when no function has
        # the name: memory calls, because only the module can own memory, and
        # the write, exit and abort calls of a unit with no OS layer.
        #
        # A type annotation does not reach the empty arrays through `.freeze`.
        LIBC_SHIMS = { "write" => [[0x7F, 0x7E, 0x7E], [0x7E]],
                       "exit" => [[0x7F], []], "_exit" => [[0x7F], []], "abort" => [[], []], # steep:ignore UnannotatedEmptyCollection
                       "malloc" => [[0x7E], [0x7E]], "free" => [[0x7E], []], # steep:ignore UnannotatedEmptyCollection
                       "posix_memalign" => [[0x7E, 0x7E, 0x7E], [0x7F]],
                            "memmove" => [[0x7E, 0x7E, 0x7E], [0x7E]], "memset" => [[0x7E, 0x7F, 0x7E], [0x7E]] }.freeze #: Hash[String, signature]

        # How many i32 locals a shim body declares.
        LOCALS = { "malloc" => 1 }.freeze #: Hash[String, Integer]

        private

        # `write(fd, ptr, len)`: an iovec in the scratch area, then fd_write.
        #: (String name) -> String
        def shim(name)
          code = +"".b
          case name
          when "write"
            # iov.buf = ptr, iov.len = len (both i32 in memory)
            code << i32c(SCRATCH) << "\x20\x01".b << "\xA7".b << "\x36\x02\x00".b
            code << i32c(SCRATCH) << "\x20\x02".b << "\xA7".b << "\x36\x02\x04".b
            code << "\x20\x00".b << i32c(SCRATCH) << i32c(1) << i32c(SCRATCH + 8) << "\x10".b << leb(function_index("fd_write")) << "\x1A".b
            code << i32c(SCRATCH + 8) << "\x28\x02\x00".b << "\xAD".b
          when "exit", "_exit"
            code << "\x20\x00".b << "\x10".b << leb(function_index("proc_exit"))
          when "abort"
            code << "\x00".b
          when "malloc"
            # r = heap; heap += n rounded to 16; grow when heap passes the
            # memory's end; return r. When the memory cannot grow (its
            # limit), heap = r and return 0, as libc's malloc does: then
            # `zr_xmalloc` ends the program with ruby's message, where an
            # address past the end would trap at its first write.
            code << "\x23\x01".b << "\x21\x01".b
            code << "\x23\x01".b << "\x20\x00".b << "\xA7".b << i32c(15) << "\x6A".b << i32c(-16) << "\x71".b << "\x6A".b << "\x24\x01".b
            code << "\x23\x01".b << "\x3F\x00".b << i32c(16) << "\x74".b << "\x4B".b
            code << "\x04\x40".b
            code << "\x23\x01".b << "\x3F\x00".b << i32c(16) << "\x74".b << "\x6B".b << i32c(PAGE - 1) << "\x6A".b << i32c(16) << "\x76".b
            code << "\x40\x00".b << i32c(-1) << "\x46".b
            code << "\x04\x40".b << "\x20\x01".b << "\x24\x01".b << "\x42\x00".b << "\x0F".b << "\x0B".b
            code << "\x0B".b
            code << "\x20\x01".b << "\xAD".b
          when "posix_memalign"
            # *slot = (malloc(size + align) + align - 1) & -align; return 0.
            # The heap never frees memory, so the extra bytes cost nothing.
            code << "\x20\x00".b << "\xA7".b
            code << "\x20\x01".b << "\x20\x02".b << "\x7C".b << "\x10".b << leb(function_index("malloc"))
            code << "\x20\x01".b << "\x7C".b << "\x42\x01".b << "\x7D".b
            code << "\x42\x00".b << "\x20\x01".b << "\x7D".b << "\x83".b
            code << "\x37\x03\x00".b << "\x41\x00".b
          when "free"
            code << "".b
          when "memmove"
            # memory.copy handles ranges that overlap; return the destination.
            code << "\x20\x00\xA7\x20\x01\xA7\x20\x02\xA7".b << "\xFC\x0A\x00\x00".b << "\x20\x00".b
          when "memset"
            # memory.fill with the low byte of c; return the destination.
            code << "\x20\x00\xA7\x20\x01\x20\x02\xA7".b << "\xFC\x0B\x00".b << "\x20\x00".b
          end
          code << "\x0B".b
          n = LOCALS[name]
          vec_bytes(vec(n ? [leb(n) + "\x7F".b] : []) + code)
        end
      end
    end
  end
end
