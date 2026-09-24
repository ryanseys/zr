# frozen_string_literal: true

require "fiddle"
require_relative "../jit"

module Zr
  module Obj
    class JIT
      # The system calls of the loader, under CRuby.
      class Fiddle
        def initialize
          @lib = ::Fiddle::Handle::DEFAULT
          @mmap = fn("mmap", [:voidp, :size_t, :int, :int, :int, :long], :voidp)
          @munmap = fn("munmap", [:voidp, :size_t], :int)
          @protect = fn("pthread_jit_write_protect_np", [:int], :void)
          @invalidate = fn("sys_icache_invalidate", [:voidp, :size_t], :void)
        end

        # Reserves `size` bytes with no access, where `map` places its two
        # parts.
        def reserve(size) = mapped(@mmap.call(0, size, 0, MAP_ANON_PRIVATE, -1, 0))

        # Unmaps `size` bytes at `at`, so that a mapping can use them by hint.
        def release(at, size) = @munmap.call(at, size)

        # Maps `size` bytes: exactly at `at` when the caller reserved it,
        # else near `near` if the kernel accepts the hint.
        def map(size, exec:, at: nil, near: 0)
          flags = MAP_ANON_PRIVATE | (exec ? MAP_JIT : 0) | (at ? MAP_FIXED : 0)
          mapped(@mmap.call(at || near, size, exec ? 7 : 3, flags, -1, 0))
        end

        def symbol(name) = @lib[name]

        def write_data(at, bytes)
          ::Fiddle::Pointer.new(at)[0, bytes.bytesize] = bytes
        end

        def call(at) = ::Fiddle::Function.new(at, [], ::Fiddle::TYPE_LONG).call

        def write_code(at, bytes)
          @protect.call(0)
          ::Fiddle::Pointer.new(at)[0, bytes.bytesize] = bytes
          @protect.call(1)
          @invalidate.call(at, bytes.bytesize)
        end

        private

        def mapped(pointer)
          at = pointer.to_i
          at.zero? || at == -1 ? nil : at
        end

        def fn(name, params, ret)
          types = { voidp: ::Fiddle::TYPE_VOIDP, size_t: ::Fiddle::TYPE_SIZE_T, int: ::Fiddle::TYPE_INT,
                    long: ::Fiddle::TYPE_LONG, void: ::Fiddle::TYPE_VOID }
          ::Fiddle::Function.new(@lib[name], params.map { |t| types.fetch(t) }, types.fetch(ret))
        end
      end
    end
  end
end
