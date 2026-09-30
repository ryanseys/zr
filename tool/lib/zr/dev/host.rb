# frozen_string_literal: true

require "rbconfig"
require_relative "../../../../lib/zr/config"

module Zr
  module Dev
    # The ruby that runs a child (`Config#host_ruby`).
    def self.ruby = Config.current.host_ruby

    # Stops a tool that reads a table from the running ruby, unless that
    # ruby is CRuby at the version that `.ruby-version` pins. A table
    # from another ruby, or from zr's copy of ruby's answers, is not
    # correct for zr.
    def self.pinned!(tool)
      abort("zr-dev #{tool}: runs under ruby #{RUBY}, not in a zr binary") if Zr.compiled?
      abort("zr-dev #{tool}: ruby #{RUBY} writes this table; this is ruby #{RUBY_VERSION}") unless RUBY_VERSION == RUBY
    end

    # Sets the collector limits and YJIT for a compile (`Zr::CLI.tune!`).
    # A tool cannot restart itself, so the limits apply only to the
    # children it starts.
    def self.tune!
      require_relative "../../../../lib/zr/cli"
      CLI.tune!
    end

    # Runs `argv` and stops the tool when it fails.
    def self.run!(*argv, **options)
      system(*argv, **options) or abort("zr-dev: #{argv.join(" ")} failed")
    end
  end
end
