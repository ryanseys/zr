# frozen_string_literal: true

require_relative "../../../../lib/zr/bootstrap/binary"

module Zr
  module Dev
    # The tools as a Bootstrap::Binary: `tool/zr-dev.rb`, compiled by zr to
    # `bin/zr-dev` (`rake build:tools`). The binary holds a copy of lib/zr,
    # so it must not run once a source changed: a stale `cache prune`
    # would compute the old digests and remove the live runtime.
    def self.tools
      dirs = ["lib", "runtime", *Layout::UPSTREAM, "tool", "test/support"]
      Bootstrap::Binary.new(entry: "tool/zr-dev.rb", binary: path("bin/zr-dev"), dirs: dirs) do
        [path("Gemfile.lock"), path("zr.gemspec")]
      end
    end

    # The variables of a bundle. The tools need no bundle. A zr binary
    # reads RUBYOPT as ruby does, and bundler's setup does not run in a
    # zr binary, so run `bin/zr-dev` outside `bundle exec`; a ruby that it
    # starts also runs outside the bundle.
    BUNDLE = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION].freeze

    # Runs the command under ruby in place of this process: the tools in a
    # zr binary do so for a stale binary and for a `host_ruby!` command.
    def self.hand_to_ruby!(argv)
      exec(BUNDLE.to_h { |name| [name, nil] }, ruby, path("tool/zr-dev.rb"), *argv)
    end
  end
end
