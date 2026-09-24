# frozen_string_literal: true

# zr: a Ruby compiler, written in Ruby. `require "zr"` loads only the
# version, the paths and the targets; the compiler loads as a command
# needs it (`zr/runtime`, `zr/native/build`).
require_relative "zr/version"
require_relative "zr/paths"
require_relative "zr/target"
require_relative "zr/clock"

