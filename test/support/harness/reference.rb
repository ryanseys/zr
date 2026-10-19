# frozen_string_literal: true

module Zr
  module Harness
    # The ruby that every expected output comes from: the pinned ruby, with
    # the gems that its own install has. This checkout's bundle, RUBYOPT
    # and RUBYLIB never reach it, so a recording sees what a plain `ruby`
    # sees.
    #
    # ZR_REFERENCE_GEM_HOME names a GEM_HOME to use instead, one you fill
    # by hand (docs/how-to/run-the-tests.md).
    module Reference
      module_function

      # The environment of a ruby that answers for zr.
      def env
        home = ENV["ZR_REFERENCE_GEM_HOME"]
        { "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "BUNDLE_LOCKFILE" => nil, "BUNDLER_SETUP" => nil,
          "BUNDLER_VERSION" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil, "GEM_HOME" => home, "GEM_PATH" => home }
      end
    end
  end
end
