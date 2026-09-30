# frozen_string_literal: true

require_relative "../../../lib/zr/paths"
require_relative "../../../lib/zr/version"

module Zr
  # The tools that work on a checkout: the generators, the test tools,
  # the benchmarks, the self-compile checks and the cache. `zr-dev help`
  # lists them. Each tool is a Command in `tool/`, loaded only when it
  # runs, so `zr-dev help` loads none of them.
  #
  # `ruby tool/zr-dev.rb <command>` runs a tool under ruby. `rake
  # build:tools` compiles the same file with zr to `bin/zr-dev`.
  module Dev
    ROOT = Paths::ROOT

    # The path of `rel` below the root of the checkout.
    def self.path(rel) = File.join(ROOT, rel)

    # `path` below the root, for a message.
    def self.rel(path) = path.delete_prefix("#{ROOT}/")
  end
end

require_relative "dev/command"
require_relative "dev/files"
require_relative "dev/host"
require_relative "dev/sources"
require_relative "dev/self"
