# frozen_string_literal: true

require "rbconfig"
require_relative "../../../../lib/zr/config"

module Zr
  module Dev
    # The ruby that runs a child (`Config#host_ruby`).
    def self.ruby = Config.current.host_ruby

    # Stops the tool with `message` and status 1. A command calls
    # `Command#fail!`, which adds its name and comes here.
    def self.fail!(message)
      warn message
      exit 1
    end

    # Stops a tool that reads a table from the running ruby, unless that
    # ruby is CRuby at the version that `.ruby-version` pins. A table
    # from another ruby is not correct for zr.
    def self.pinned!(tool)
      fail!("zr-dev #{tool}: ruby #{RUBY} writes this table; this is ruby #{RUBY_VERSION}") unless RUBY_VERSION == RUBY
    end

    # Sets the collector limits and YJIT for a compile (`Zr::CLI.tune!`).
    # A tool cannot restart itself, so the limits apply only to the
    # children it starts.
    def self.tune!
      require_relative "../../../../lib/zr/cli"
      CLI.tune!
    end

    # The output of `git` with `args` in `dir`, or nil when it fails.
    # `args` are an argument list, never a shell string.
    def self.git(*args, dir: ROOT, err: File::NULL)
      out = IO.popen(["git", "-C", dir, *args], err: err, &:read)
      out if $?.success?
    end

    # The short hash of HEAD in `dir` (`length` digits, or git's own
    # length), or nil outside a checkout.
    def self.revision(dir: ROOT, length: nil)
      git("rev-parse", length ? "--short=#{length}" : "--short", "HEAD", dir: dir)&.strip
    end

    # Runs the block. Returns its value and the seconds it took.
    def self.timed
      began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began]
    end
  end
end
