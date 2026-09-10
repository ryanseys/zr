# frozen_string_literal: true

require "fiddle"
require_relative "../jit"

module Ze0
  module Obj
    class JIT
      # The system half of the loader, under CRuby.
      class Fiddle
        def initialize
          @lib = ::Fiddle::Handle::DEFAULT
          @mmap = fn("mmap", [:voidp, :size_t, :int, :int, :int, :long], :voidp)
          @protect = fn("pthread_jit_write_protect_np", [:int], :void)
          @invalidate = fn("sys_icache_invalidate", [:voidp, :size_t], :void)
        end

        def map(size, exec:, near: 0)
          at = @mmap.call(near, size, exec ? 7 : 3, MAP_ANON_PRIVATE | (exec ? MAP_JIT : 0), -1, 0).to_i
          at.zero? || at == -1 ? nil : at
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

        def fn(name, params, ret)
          types = { voidp: ::Fiddle::TYPE_VOIDP, size_t: ::Fiddle::TYPE_SIZE_T, int: ::Fiddle::TYPE_INT,
                    long: ::Fiddle::TYPE_LONG, void: ::Fiddle::TYPE_VOID }
          ::Fiddle::Function.new(@lib[name], params.map { |t| types.fetch(t) }, types.fetch(ret))
        end
      end
    end
  end
end
