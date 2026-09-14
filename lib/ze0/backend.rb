# frozen_string_literal: true

module Ze0
  # The backends: each turns IR into what a target runs. A native backend
  # (`Backend::Aarch64`) answers an `Obj::Unit` an object writer or the JIT
  # takes; the wasm backend (`Backend::Wasm`) answers a module's bytes.
  module Backend
    # A form a backend has no code for. A build answers its message: a
    # refusal by name, never a guess.
    class Refused < StandardError; end
  end
end
