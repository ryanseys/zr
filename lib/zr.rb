# frozen_string_literal: true

# zr: a Ruby compiler, written in Ruby. `require "zr"` loads the
# version, the paths, the targets and `Zr.build` (lib/zr/api.rb,
# docs/reference/ruby-api.md); the compiler loads as a build needs it
# (`zr/runtime`, `zr/native/build`).
require_relative "zr/version"
require_relative "zr/paths"
require_relative "zr/target"
require_relative "zr/timing"
require_relative "zr/api"

