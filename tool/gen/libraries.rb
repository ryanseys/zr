# frozen_string_literal: true

require_relative "../gen"

module Zr
  module Dev
    class Gen
      # The digest of each pinned gem's files. rubygems finds the gems
      # without the bundle, as a build does (lib/zr/libraries/resolve.rb).
      class Libraries < Generator
        host_ruby!
        writes "lib/zr/library_digests.rb"

        BUNDLE = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION].freeze

        def write(io)
          env = BUNDLE.to_h { |name| [name, nil] }
          text = IO.popen(env, [Dev.ruby, Dev.path("lib/zr/libraries/resolve.rb"), "--digests"], &:read)
          fail!("a pinned gem did not resolve") unless $?.success?
          io.print text
        end
      end
    end
  end
end
