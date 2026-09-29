# frozen_string_literal: true

require_relative "../../../lib/zr/stdlib"
require_relative "../../../lib/zr/ports"

module Zr
  module Harness
    # The ruby that every expected output comes from: ruby 4.0.7 with the
    # gems that a stock install has, except that a gem whose C zr ports
    # comes at zr's version (json 3.0.2, not 2.18.0). Those are the same
    # libraries that a zr build compiles in (stdlib/ and lib/zr/ports.rb).
    #
    # The gems live in their own GEM_HOME, tmp/reference/gems, which
    # `zr-dev reference` fills. GEM_PATH names only that directory, so
    # the gems that the host installed next to ruby's own (a `gem update`,
    # or a bundle without a path) never reach a recording. Default gems
    # still load from ruby's own specifications.
    module Reference
      DIR = File.expand_path("../../../tmp/reference", __dir__)
      GEMS = File.join(DIR, "gems")
      STAMP = File.join(DIR, "STAMP")

      module_function

      # `{ name => version }`: each gem that GEMS must hold.
      def gems
        want = Stdlib::BUNDLED.merge(Stdlib::OTHER_BUNDLED)
        # win32ole builds only on Windows, which zr does not target.
        want.delete("win32ole") unless Gem.win_platform?
        Ports::ALL.each do |name, port|
          want[name] = port.version if want.key?(name) || stock_defaults[name] != port.version
        end
        want.sort.to_h
      end

      # The default gems of this ruby, by name.
      def stock_defaults
        @stock_defaults ||= Dir[File.join(Gem.default_specifications_dir, "*.gemspec")].to_h do |path|
          File.basename(path, ".gemspec").match(/\A(.+)-([^-]+)\z/).captures
        end
      end

      def stamp = gems.map { |name, version| "#{name} #{version}\n" }.join

      def ready? = File.file?(STAMP) && File.read(STAMP) == stamp

      # The environment of a ruby that answers for zr. Stops when GEMS is
      # missing or holds other versions.
      def env
        raise "the reference ruby is not set up (#{STAMP}); run `ruby tool/zr-dev.rb reference`" unless ready?

        { "GEM_HOME" => GEMS, "GEM_PATH" => GEMS, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil,
          "BUNDLE_LOCKFILE" => nil, "BUNDLER_SETUP" => nil, "BUNDLER_VERSION" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil }
      end
    end
  end
end
