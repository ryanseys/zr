# frozen_string_literal: true

require "rbconfig"
require_relative "paths"

module Zr
  # The pure-Ruby libraries a program's `require` reads: ruby 4.0.6's
  # default and bundled gems, each at the version zr.gemspec pins, read
  # from where rubygems installed it. zr compiles them into the program;
  # it never loads them itself.
  #
  # A build reads one directory, the tree: a link to each file of each
  # pinned gem, and to each file of vendor/lib, which holds the few
  # files of ruby's library that no gem ships. The tree is named after
  # what it holds, not after where the gems are, so two machines with the
  # same gems build the same bytes. It sits beside the checkout (or in
  # the user's cache, for an installed gem), and never under `ZR_CACHE`:
  # the stage ladder builds under two caches and needs the same paths.
  #
  # Only rubygems finds a gem, and neither a compiled compiler nor a
  # `--disable-gems` ruby has it. So a ruby with rubygems resolves the
  # pins in a child (lib/zr/libraries/resolve.rb), and writes the tree
  # and a manifest; a build after it reads the manifest and stats a few
  # directories, and starts no child.
  module Libraries
    # Each gem zr carries, and its version: ruby 4.0.6's own, or, for
    # rubygems and bundler, the one `gem update --system` gave it.
    # rubygems-update holds both: rubygems in lib/, bundler in
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
      "delegate" => "0.6.1", "did_you_mean" => "2.0.0", "english" => "0.8.1", "erb" => "6.0.1.1",
      "error_highlight" => "0.7.2", "fileutils" => "1.8.0", "find" => "0.2.0", "forwardable" => "1.4.0",
      "ipaddr" => "1.2.8", "net-http" => "0.9.1", "net-protocol" => "0.2.2", "open-uri" => "0.5.0",
      "open3" => "0.2.1", "optparse" => "0.8.1", "pp" => "0.6.3", "prettyprint" => "0.2.0", "resolv" => "0.7.0",
      "securerandom" => "0.4.1", "shellwords" => "0.2.2", "singleton" => "0.3.0", "tempfile" => "0.3.1",
      "time" => "0.4.2", "timeout" => "0.6.0", "tmpdir" => "0.3.1", "tsort" => "0.2.0", "un" => "0.3.0",
      "uri" => "1.1.1", "weakref" => "0.1.4",
      # rubygems and bundler.
      "rubygems-update" => "4.0.20"
    }.freeze

    # A gem's directories, where they are not its require_paths:
    # rubygems-update names a directory that hides its lib from `require`.
    DIRS = { "rubygems-update" => %w[lib bundler/lib] }.freeze

    # Files a gem ships that ruby never loads from it: minitest's Hoe
    # plugin.
    EXCLUDE = { "minitest" => %w[hoe/minitest.rb] }.freeze

    # A gem that tells its own frames from a program's by the directory
    # they are in, which must hold that gem alone: its own lib, apart.
    APART = %w[power_assert].freeze

    # The files of ruby's library that no gem ships, which zr carries.
    RESIDUAL = File.join(Paths::VENDOR, "lib")

    # What a build cannot go on without: a pinned gem that is not
    # installed, or one whose files are not that version's.
    class Unresolved < StandardError; end

    module_function

    # Where the trees and their manifests live.
    def dir = Paths.checkout? ? File.join(Paths::ROOT, "tmp/lib") : File.join(Paths.user_cache, "lib")

    # The directory a program requires ruby's library from.
    def root = roots.first

    # The directories of the gems kept apart, in APART's order.
    def apart = roots.last

    def roots
      @roots ||= if (names = carried)
                   [names.first, names.last(APART.size)]
                 else
                   t = tree
                   [File.join(t, "lib"), APART.map { |name| File.join(t, name, "lib") }]
                 end
    end

    # A program that carries the compiler asks the directories it was
    # built against, as its build named them: it may run where no gem
    # is. Only a build that evals writes them (Zr.load_tables); any
    # other compiled compiler finds the tree as ruby does.
    def carried
      return nil unless RbConfig::CONFIG["ruby_install_name"] == "zr" && defined?(::Zr::Eval::Runtime)

      names = ::Zr::Eval::Runtime.library_roots
      names.size > APART.size ? names : nil
    end

    # The tree the manifest names, resolved again where it is stale.
    def tree
      manifest = read
      return manifest[:tree] if fresh?(manifest)

      resolve
      manifest = read
      raise Unresolved, "the pinned gems did not resolve; #{manifest_path} is stale" unless fresh?(manifest)

      manifest[:tree]
    end

    # The environment rubygems reads its directories from. A bundle's
    # own settings are not in it: the child runs without bundler.
    GEM_ENV = %w[GEM_HOME GEM_PATH].freeze

    def manifest_path = File.join(dir, "manifest-#{GEM_ENV.map { |name| ENV[name].to_s }.join("\0").sum.to_s(36)}.marshal")

    def read
      Marshal.load(File.binread(manifest_path)) if File.file?(manifest_path)
    rescue StandardError
      nil
    end

    # A manifest holds while rubygems would read the same directories,
    # none of them has changed (an install or an uninstall touches the
    # directory of specifications), and the tree is there.
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

    # The variables a bundle sets that would make the child's rubygems
    # see the bundle and not the gems.
    UNBUNDLED = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION].to_h { |name| [name, nil] }.freeze

    # The resolve, in a ruby with rubygems. Its refusal is this build's.
    def resolve
      ruby = RbConfig::CONFIG["ruby_install_name"] == "zr" ? ENV.fetch("ZR_RUBY", "ruby") : RbConfig.ruby
      script = File.join(__dir__, "libraries/resolve.rb")
      out = IO.popen(UNBUNDLED, [ruby, script, dir], err: %i[child out], &:read)
      raise Unresolved, out.strip.sub(/\Azr: /, "") unless $?.success?
    rescue SystemCallError => e
      raise Unresolved, "no ruby to resolve the pinned gems with (#{e.message}); ZR_RUBY names one"
    end
  end
end
