# frozen_string_literal: true

# The IR: CLIF's model, restricted to what ze0 emits, as Ruby objects.
# Today it is built from the text the lowering writes and rendered back to
# that text; the structure is what the native backends and the wasm
# emitter will read.
require_relative "ir/function"
