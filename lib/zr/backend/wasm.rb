# frozen_string_literal: true

require_relative "wasm/codegen"

module Zr
  module Backend
    # The wasm32 backend. `Codegen` writes one WASI module from IR functions
    # and data. It adds them to a prelude that contains the runtime, emitted one time.
    module Wasm
      module_function

      # Returns the module's bytes. With `split`, the program module that
      # imports the runtime module of `prelude`, whose file name `split` is
      # (`runtime_module`).
      #: (Array[IR::Function] functions, Array[Obj::Datum] data, ?prelude: Codegen::Prelude?, ?split: String?) -> String
      def emit(functions, data, prelude: nil, split: nil) = Codegen.new(functions, data, prelude: prelude).emit(split: split)

      # The runtime module of `prelude`: the bytes that a program module of
      # it preloads (`wasmtime run --preload zr=<file>`).
      # `link` is the text of its LINK_SECTION.
      #: (Codegen::Prelude prelude, ?link: String?) -> String
      def runtime_module(prelude, link: nil) = Codegen.new([], [], prelude: prelude).runtime_module(link: link)

      # The file name of the runtime module that the program module `bytes`
      # imports, or nil for a whole module.
      #: (String bytes) -> String?
      def runtime_of(bytes) = Codegen.runtime_of(bytes)

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
