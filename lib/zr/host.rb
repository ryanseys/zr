# frozen_string_literal: true

require "rbconfig"

module Zr
  # The process that runs zr's own Ruby: CRuby, or a program that zr
  # compiled.
  module Host
    module_function

    # Whether this process is a program that zr compiled (the compiled
    # compiler, or a program with eval support) and not CRuby. A zr binary
    # gives the same RUBY_ENGINE and RubyVM as ruby 4.0.7, but its RbConfig
    # gives zr as the interpreter (lib/zr/runtime/ext/rbconfig.rb).
    def compiled? = RbConfig::CONFIG["ruby_install_name"] == "zr"
  end
end
