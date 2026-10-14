# frozen_string_literal: true

module Zr
  # A ruby that zr or its tools start runs outside any bundle that this
  # process runs in: `bundle exec` puts bundler/setup in RUBYOPT and in
  # BUNDLER_SETUP, and Bundler then hides the gems that the Gemfile does
  # not list. It loads nothing, so any tool can read it first.
  module ChildRuby
    # The variables to take out of a child's environment (each one nil).
    UNBUNDLED = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB]
                .to_h { |name| [name, nil] }.freeze #: Hash[String, nil]
  end
end
