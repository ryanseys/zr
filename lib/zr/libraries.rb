# frozen_string_literal: true

require "rbconfig"
require_relative "paths"
require_relative "config"

module Zr
  # The pure-Ruby libraries that a program's `require` reads: ruby 4.0.7's
  # default and bundled gems, each at the version that zr.gemspec pins,
  # read from where rubygems installed it. zr compiles them into the
  # program. It never loads them itself.
  #
  # A build reads one directory, the tree. It contains a link to each file
  # of each pinned gem, and to each file of vendor/lib (the few files of
  # ruby's library that no gem ships). The tree's name comes from its
  # contents, not from the gem location, so two machines with the same
  # gems build the same bytes. The tree is next to the checkout (or in
  # the user's cache, for an installed gem), and never under `ZR_CACHE`:
  # the stage builds use two caches and need the same paths.
  #
  # Only rubygems can find a gem, and a compiled compiler and a
  # `--disable-gems` ruby do not have it. So a ruby with rubygems resolves
  # the pins in a child process (lib/zr/libraries/resolve.rb) and writes
  # the tree and a manifest. Later builds read the manifest, stat a few
  # directories, and start no child.
  module Libraries
    # Each gem that zr supports, and its version: ruby 4.0.7's own, or,
    # for rubygems and bundler, the version from `gem update --system`.
    # rubygems-update contains both: rubygems in lib/, bundler in
    # bundler/lib/.
    PINS = {
      # Bundled gems.
      "abbrev" => "0.1.2", "base64" => "0.3.0", "benchmark" => "0.5.0", "csv" => "3.3.6", "drb" => "2.2.3",
      "fiddle" => "1.1.8", "getoptlong" => "0.2.1", "irb" => "1.18.0", "logger" => "1.7.0", "matrix" => "0.4.3",
      "minitest" => "6.0.6", "mutex_m" => "0.3.0", "net-ftp" => "0.3.9", "net-imap" => "0.6.6", "net-pop" => "0.1.2",
      "net-smtp" => "0.5.1", "nkf" => "0.3.0", "observer" => "0.1.2", "ostruct" => "0.6.3", "power_assert" => "3.0.1",
      "prime" => "0.1.4", "pstore" => "0.2.1", "racc" => "1.8.1", "rake" => "13.4.2", "readline" => "0.0.4",
      "reline" => "0.7.0", "resolv-replace" => "0.2.0", "rexml" => "3.4.4", "rinda" => "0.2.0", "rss" => "0.3.3",
      "syntax_suggest" => "3.0.0", "test-unit" => "3.7.8",
      # Default gems.
      "delegate" => "0.6.1", "did_you_mean" => "2.0.0", "english" => "0.8.1", "erb" => "6.0.7",
      "error_highlight" => "0.7.2", "fileutils" => "1.8.0", "find" => "0.2.0", "forwardable" => "1.4.0",
      "ipaddr" => "1.2.8", "net-http" => "0.9.1", "net-protocol" => "0.2.2", "open-uri" => "0.5.0",
      "open3" => "0.2.1", "optparse" => "0.8.1", "pp" => "0.6.3", "prettyprint" => "0.2.0", "resolv" => "0.7.2",
      "securerandom" => "0.4.1", "shellwords" => "0.2.2", "singleton" => "0.3.0", "tempfile" => "0.3.1",
      "time" => "0.4.2", "timeout" => "0.6.0", "tmpdir" => "0.3.1", "tsort" => "0.2.0", "un" => "0.3.0",
      "uri" => "1.1.1", "weakref" => "0.1.4",
      # rubygems and bundler.
      "rubygems-update" => "4.0.20"
    }.freeze

    # A gem's directories, when they are not its require_paths.
    # rubygems-update gives a directory that hides its lib from `require`.
    DIRS = { "rubygems-update" => %w[lib bundler/lib] }.freeze

    # Files a gem ships that ruby never loads from it: minitest's Hoe
    # plugin.
    EXCLUDE = { "minitest" => %w[hoe/minitest.rb] }.freeze

    # A gem that identifies its own frames by their directory. That
    # directory must contain only this gem, so the gem gets its own lib.
    APART = %w[power_assert].freeze

    # The files of ruby's library that no gem ships. zr includes them.
    RESIDUAL = File.join(Paths::VENDOR, "lib")

    # A build cannot continue: a pinned gem is not installed, or its files
    # are not from the pinned version.
    class Unresolved < StandardError; end

    module_function

    # The directory of the trees and their manifests.
    def dir = Paths.checkout? ? File.join(Paths::ROOT, "tmp/lib") : File.join(Paths.user_cache, "lib")

    # The directory a program requires ruby's library from.
    def root = roots.first

    # The directories of the APART gems, in APART's order.
    def apart = roots.last

    def roots
      @roots ||= if (names = carried)
                   [names.first, names.last(APART.size)]
                 else
                   t = tree
                   [File.join(t, "lib"), APART.map { |name| File.join(t, name, "lib") }]
                 end
    end

    # A program that includes the compiler uses the directories from its
    # build, because it can run on a machine with no gems. Only a build
    # with eval support writes them (Zr.load_tables). Other compiled
    # compilers find the tree as ruby does.
    def carried
      return nil unless Zr.compiled? && defined?(::Zr::Eval::Runtime)

      names = ::Zr::Eval::Runtime.library_roots
      names.size > APART.size ? names : nil
    end

    # The tree that the manifest gives. Resolves it again if it is stale.
    def tree
      manifest = read
      return manifest[:tree] if fresh?(manifest)

      resolve
      manifest = read
      raise Unresolved, "the pinned gems did not resolve; #{manifest_path} is stale" unless fresh?(manifest)

      manifest[:tree]
    end

    # The environment variables that give rubygems its directories. The
    # bundle's settings are not included, because the child runs without
    # bundler.
    GEM_ENV = %w[GEM_HOME GEM_PATH].freeze

    def manifest_path = File.join(dir, "manifest-#{GEM_ENV.map { |name| ENV[name].to_s }.join("\0").sum.to_s(36)}.marshal")

    # The manifest, or nil if it does not load (a partial or an old file).
    def read
      Marshal.load(File.binread(manifest_path)) if File.file?(manifest_path)
    rescue SystemCallError, TypeError, ArgumentError, EOFError
      nil
    end

    # A manifest is fresh if rubygems reads the same directories, none of
    # them changed (an install or uninstall changes the specifications
    # directory), and the tree exists.
    def fresh?(manifest)
      manifest.is_a?(Hash) && manifest[:env] == GEM_ENV.map { |name| ENV[name] } &&
        File.directory?(manifest[:tree].to_s) &&
        manifest[:stamps].all? { |path, stamp| stamp_of(path) == stamp }
    end

    def stamp_of(path)
      s = File.stat(path)
      [s.mtime.to_r, s.ino]
    rescue SystemCallError
      nil
    end

    # The variables that a bundle sets. They would make the child's
    # rubygems see the bundle and not the gems.
    UNBUNDLED = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION].to_h { |name| [name, nil] }.freeze

    # Resolves the pins in a ruby with rubygems. If it fails, this build
    # fails with its message.
    def resolve
      ruby = Zr.compiled? ? Config.current.host_ruby : RbConfig.ruby
      script = File.join(__dir__, "libraries/resolve.rb")
      out = IO.popen(UNBUNDLED, [ruby, script, dir], err: %i[child out], &:read)
      raise Unresolved, out.strip.sub(/\Azr: /, "") unless $?.success?
    rescue SystemCallError => e
      raise Unresolved, "no ruby to resolve the pinned gems with (#{e.message}); ZR_HOST_RUBY names one"
    end
  end
end
