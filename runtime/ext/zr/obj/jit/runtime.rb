# frozen_string_literal: true

module Zr
  module Obj
    class JIT
      # The system half of the loader, inside a program the runtime runs.
      # The same libSystem calls the Fiddle host makes.
      class Runtime
        def reserve(size) = Primitive.zr_os_jit_reserve(size)
        def release(at, size) = Primitive.zr_os_jit_release(at, size)
        # A nonzero address is taken as it is: the caller reserved it.
        def map(size, exec:, at: nil, near: 0) = Primitive.zr_os_jit_map(size, exec, at || near)
        def symbol(name) = Primitive.zr_os_symbol(name)
        def write_data(at, bytes) = Primitive.zr_jit_write_data(at, bytes)
        def write_code(at, bytes) = Primitive.zr_os_jit_write(at, bytes)

        # A loaded function, called for the word it answers.
        def call(at) = Primitive.zr_jit_call(at)
      end
    end
  end
end
