# frozen_string_literal: true

module Ze0
  module Obj
    class JIT
      # The system half of the loader, inside a program the runtime runs.
      # The same libSystem calls the Fiddle host makes.
      class Runtime
        def map(size, exec:, near: 0) = Primitive.zr_jit_map(size, exec, near)
        def symbol(name) = Primitive.zr_jit_symbol(name)
        def write_data(at, bytes) = Primitive.zr_jit_write_data(at, bytes)
        def write_code(at, bytes) = Primitive.zr_jit_write_code(at, bytes)

        # A loaded function, called for the word it answers.
        def call(at) = Primitive.zr_jit_call(at)
      end
    end
  end
end
