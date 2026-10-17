# frozen_string_literal: true

require "rbconfig"

module Zr
  # A binary that zr built, as the process that runs zr's own Ruby.
  module Binary
    module_function

    # Whether a zr binary runs this code (the compiled compiler, or a
    # program with eval support), and not CRuby. Each build of this file
    # ends with lib/zr/runtime/lib/zr/binary.rb (`Hir::Build::Loader.tails`),
    # which sets BUILT. RbConfig cannot tell: a zr binary gives the pinned
    # ruby's RUBY_ENGINE and RubyVM, and an RbConfig that names the
    # launcher that started it (lib/zr/runtime/ext/rbconfig.rb).
    def running? = defined?(BUILT) ? true : false
  end
end
