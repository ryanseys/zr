# frozen_string_literal: true

require_relative "wasm/codegen"

module Zr
  module Backend
    # The wasm32 backend: `Codegen` writes one WASI module from IR functions
    # and data, over a prelude the runtime's module was emitted into once.
    module Wasm
      module_function

      # The module's bytes.
      def emit(functions, data, prelude: nil) = Codegen.new(functions, data, prelude: prelude).emit

      # The runtime's prelude, with `pending` the symbols a program defines.
      def prelude(functions, data, pending:) = Codegen.new(functions, data, pending: pending).prelude

      # The libc names a module answers itself where nothing defines them.
      def floor = Codegen::FLOOR.keys
    end
  end
end
