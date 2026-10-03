# frozen_string_literal: true

module Zr
  module Obj
    class JIT
      # The system half of the loader, inside a program the runtime runs.
      # The same libSystem calls the Fiddle host makes.
      class Runtime
        #: (Integer size) -> Integer?
        def reserve(size) = Primitive.zr_os_jit_reserve(size)
        #: (Integer at, Integer size) -> untyped
        def release(at, size) = Primitive.zr_os_jit_release(at, size)
        # A nonzero address is taken as it is: the caller reserved it.
        #: (Integer size, exec: bool, ?at: Integer?, ?near: Integer) -> Integer?
        def map(size, exec:, at: nil, near: 0) = Primitive.zr_os_jit_map(size, exec, at || near)
        #: (String name) -> Integer
        def symbol(name) = Primitive.zr_os_symbol(name)
        #: (Integer at, String bytes) -> untyped
        def write_data(at, bytes) = Primitive.zr_jit_write_data(at, bytes)
        #: (Integer at, String bytes) -> untyped
        def write_code(at, bytes) = Primitive.zr_os_jit_write(at, bytes)

        # A loaded function, called for the word that it returns.
        #: (Integer at) -> Integer
        def call(at) = Primitive.zr_jit_call(at)
      end
    end
  end
end
