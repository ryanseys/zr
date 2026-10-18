# frozen_string_literal: true

require_relative "x86_64/codegen"
require_relative "x86_64/stub"
require_relative "native/emitter"

module Zr
  module Backend
    # The x86-64 backend, for the System V ABI. `Codegen` writes each
    # function's machine code with its own `Assembler`, and `Stub` holds
    # the functions that the kernel subset cannot express.
    module X86_64
      extend Native::Emitter

      Spelled = Native::Spelled
    end
  end
end
