# frozen_string_literal: true

module Zr
  module Harness
    # The environment that this process started with, before bundler.
    #
    # A child of the tests must not inherit this bundle. `bundle exec`
    # puts `-rbundler/setup` in `RUBYOPT` and also in `BUNDLER_SETUP`, so
    # a ruby started from here loads bundler before the program. Bundler
    # uses 56 object ids, so the next object id is 464, not 16 as in a
    # plain ruby. A compiled binary does not read `RUBYOPT`, so the two
    # outputs differ (`test/programs/reflection_more.rb`). Bundler also
    # stops a child from loading a gem that ruby bundles but this Gemfile
    # does not list; prism's own test suite needs such gems.
    module CleanEnv
      ORIGINAL = (defined?(Bundler) ? Bundler.original_env : ENV).to_h.freeze

      # `ORIGINAL` merged with `overlay`. A nil in `overlay` removes the
      # variable. The caller passes `unsetenv_others: true`, so the child
      # gets only this hash.
      def self.env(overlay = {}) = ORIGINAL.merge(overlay).compact
    end
  end
end
