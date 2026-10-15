# frozen_string_literal: true

require_relative "wasm/codegen"

module Zr
  module Backend
    # The wasm32 backend. `Codegen` writes one WASI module from IR functions
    # and data. It adds them to a prelude that contains the runtime, emitted one time.
    module Wasm
      module_function

      # Returns the module's bytes.
      #: (Array[IR::Function] functions, Array[Obj::Datum] data, ?prelude: Codegen::Prelude?) -> String
      def emit(functions, data, prelude: nil) = Codegen.new(functions, data, prelude: prelude).emit

      # Returns the runtime's prelude. `pending` gives the symbols that a
      # program defines. A block can make the bodies (`Codegen#prelude`).
      # @rbs functions: Array[IR::Function]
      # @rbs data: Array[Obj::Datum]
      # @rbs pending: Codegen::pending
      # @rbs &bodies: ? (Array[IR::Function], Codegen) -> Array[Array[String | Codegen::reference]]
      # @rbs return: Codegen::Prelude
      def prelude(functions, data, pending:, &bodies) = Codegen.new(functions, data, pending: pending).prelude(&bodies)

      # The libc names that the module defines itself when no other code defines them.
      #: () -> Array[String]
      def libc_shims = Codegen::LIBC_SHIMS.keys
    end
  end
end
