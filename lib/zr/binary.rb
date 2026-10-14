# frozen_string_literal: true

require "rbconfig"

module Zr
  # A binary that zr built, as the process that runs zr's own Ruby.
  module Binary
    module_function

    # Whether a zr binary runs this code (the compiled compiler, or a
    # program with eval support), and not CRuby. A zr binary gives the same
    # RUBY_ENGINE and RubyVM as the pinned ruby, but its RbConfig gives zr
    # as the interpreter (lib/zr/runtime/ext/rbconfig.rb).
    def running? = RbConfig::CONFIG["ruby_install_name"] == "zr"
  end
end
