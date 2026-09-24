# frozen_string_literal: true

module Zr
  module Harness
    # The environment this process was started in, before bundler.
    #
    # A child of the checks must not inherit this bundle. `bundle exec`
    # puts `-rbundler/setup` in `RUBYOPT` and names it again in
    # `BUNDLER_SETUP`, so a ruby started from here loads bundler before
    # it reads the program. A ruby that has loaded bundler has already
    # handed out fifty-six object ids, and answers 464 where a plain
    # ruby answers 16 -- so `test/programs/reflection_more.rb` asked the
    # oracle a question a compiled program cannot be asked, since a
    # binary has no `RUBYOPT` to read. It also stops a child loading a
    # gem ruby bundles but this Gemfile does not name, which is what
    # kept prism's own test suite from running at all.
    module Unbundled
      ORIGINAL = (defined?(Bundler) ? Bundler.original_env : ENV).to_h.freeze

      # `ORIGINAL` with `overlay` over it. A nil in `overlay` leaves the
      # variable out, and the caller passes `unsetenv_others: true`, so
      # what the child gets is this hash and nothing else.
      def self.env(overlay = {}) = ORIGINAL.merge(overlay).compact
    end
  end
end
