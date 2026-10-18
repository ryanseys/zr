# frozen_string_literal: true

require_relative "aarch64/codegen"
require_relative "aarch64/stub"
require_relative "native/emitter"

module Zr
  module Backend
    # The aarch64 backend. `Codegen` writes each function's machine code
    # with our own `Assembler`. `Obj::Relocs::Aarch64` patches the
    # relocations that it records. `Stub` contains the functions that the kernel subset cannot express.
    module Aarch64
      extend Native::Emitter

      Spelled = Native::Spelled
    end
  end
end
