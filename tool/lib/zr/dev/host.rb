# frozen_string_literal: true

require "rbconfig"

module Zr
  module Dev
    # The ruby that runs a child: this ruby, or in a binary that zr built,
    # the ruby that `ZR_HOST_RUBY` names or the one on PATH. In a zr binary
    # `RbConfig.ruby` names zr itself.
    def self.ruby
      return RbConfig.ruby unless Zr.compiled?

      ENV.fetch("ZR_HOST_RUBY", "ruby")
    end

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
