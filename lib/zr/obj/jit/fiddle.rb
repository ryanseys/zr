# frozen_string_literal: true

require "fiddle"
require_relative "../jit"

module Zr
  module Obj
    class JIT
      # The system half of the loader, under CRuby.
      class Fiddle
        def initialize
          @lib = ::Fiddle::Handle::DEFAULT
          @mmap = fn("mmap", [:voidp, :size_t, :int, :int, :int, :long], :voidp)
          @munmap = fn("munmap", [:voidp, :size_t], :int)
          @protect = fn("pthread_jit_write_protect_np", [:int], :void)
          @invalidate = fn("sys_icache_invalidate", [:voidp, :size_t], :void)
        end

        # A region of `size` bytes nothing can touch yet, for `map` to
        # place its halves in.
        def reserve(size) = mapped(@mmap.call(0, size, 0, MAP_ANON_PRIVATE, -1, 0))

        # `size` bytes at `at` given back, for a mapping to take by hint.
        def release(at, size) = @munmap.call(at, size)

        # A mapping of `size` bytes: at `at` exactly, where the caller
        # reserved it; else near `near` when the kernel agrees.
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
