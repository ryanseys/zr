# frozen_string_literal: true

require_relative "../../../lib/zr/library/stdlib"
require_relative "../../../lib/zr/library/ports"

module Zr
  module Harness
    # The ruby that every expected output comes from: ruby 4.0.7 with the
    # gems that a stock install has, except that a gem whose C zr ports
    # comes at zr's version (json 3.0.2, not 2.18.0). Those are the same
    # libraries that a zr build compiles in (vendor/ruby and lib/zr/library/ports.rb).
    #
    # The gems live in their own GEM_HOME, tmp/reference/gems, which
    # tool/install_reference_gems.rb fills. GEM_PATH names only that directory, so
    # the gems that the host installed next to ruby's own (a `gem update`,
    # or a bundle without a path) never reach a recording. Default gems
    # still load from ruby's own specifications.
    module Reference
      DIR = File.expand_path("../../../tmp/reference", __dir__)
      GEMS = File.join(DIR, "gems")
      STAMP = File.join(DIR, "STAMP")

      # The other versions of a ported gem that a program test runs with
      # (foo.rb.gems), each in a GEM_HOME of its own below `ports/`, as
      # GEMS holds one version of a gem.
      PORTS = { "json" => %w[2.20.0 2.21.2] }.freeze

      # Gems with a C extension that zr runs as it is (`--native-ext`),
      # among the ones that the most downloaded gems need
      # (`zr-dev ext rank`), each in a GEM_HOME of its own below `native/`.
      # Their install compiles the extension with this ruby, once.
      NATIVE = { "bcrypt" => "3.1.22", "binding_ninja" => "0.2.3", "bson" => "5.2.0", "cgi" => "0.5.2",
                 "ed25519" => "1.4.0", "erb" => "6.0.7", "escape_utils" => "1.3.0", "fast_blank" => "1.0.1",
                 "google-protobuf" => "4.36.2", "gvltools" => "0.5.0", "hiredis" => "0.6.3", "http_parser.rb" => "0.8.1",
                 "jaro_winkler" => "1.7.0", "murmurhash3" => "0.1.7", "nio4r" => "2.7.5", "oj" => "3.17.7",
                 "puma" => "8.0.2", "rbs" => "4.2.0", "rbtree" => "0.4.7", "rbtree3" => "1.1.0", "redcarpet" => "3.6.1", "rinku" => "2.0.6",
                 "thrift" => "0.25.0", "unf_ext" => "0.0.9.1", "yajl-ruby" => "1.4.3", "zstd-ruby" => "2.0.10" }.freeze

      module_function

      # `{ name => version }`: each gem that GEMS must hold.
      def gems
        want = Library::Stdlib::BUNDLED.merge(Library::Stdlib::OTHER_BUNDLED)
        # win32ole builds only on Windows, which zr does not target.
        want.delete("win32ole") unless Gem.win_platform?
        Library::Ports::ALL.each do |name, port|
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

      def stamp
        (gems.map { |name, version| "#{name} #{version}\n" } + ports.map { |name, version| "port #{name} #{version}\n" } +
         NATIVE.map { |name, version| "native #{name} #{version}\n" }).join
      end

      # `[[name, version]]` of each PORTS version.
      def ports = PORTS.flat_map { |name, versions| versions.map { |version| [name, version] } }

      # The GEM_HOME of a PORTS version.
      def port_home(name, version) = File.join(DIR, "ports", "#{name}-#{version}")

      # The unpacked gem of a PORTS version, which a zr build takes with
      # --gem, and the directories that ruby needs on -I for it: its lib/
      # and its compiled extension.
      def port_gem(name, version) = File.join(port_home(name, version), "gems", "#{name}-#{version}")

      def port_load_path(name, version)
        [File.join(port_gem(name, version), "lib"),
         *Dir[File.join(port_home(name, version), "extensions", "*", "*", "#{name}-#{version}")]]
      end

      # The GEM_HOME of a NATIVE gem.
      def native_home(name, version) = File.join(DIR, "native", "#{name}-#{version}")

      def ready? = File.file?(STAMP) && File.read(STAMP) == stamp

      # The environment of a ruby that answers for zr. Stops when GEMS is
      # missing or holds other versions.
      def env
        raise "the reference ruby is not set up (#{STAMP}); run bin/setup or `ruby tool/install_reference_gems.rb`" unless ready?

        { "GEM_HOME" => GEMS, "GEM_PATH" => GEMS, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil,
          "BUNDLE_LOCKFILE" => nil, "BUNDLER_SETUP" => nil, "BUNDLER_VERSION" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil }
      end
    end
  end
end
