# frozen_string_literal: true

# ze0: a Ruby compiler, written in Ruby. `require "ze0"` loads only the
# version, the paths and the targets; the compiler loads as a command
# needs it (`ze0/zr`, `ze0/native/build`).
require_relative "ze0/version"
require_relative "ze0/paths"
require_relative "ze0/target"
