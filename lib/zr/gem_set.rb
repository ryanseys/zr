# frozen_string_literal: true

require "digest/sha2"
require "rbconfig"
require_relative "paths"
require_relative "ports"
require_relative "version"

module Zr
  # The gems that a build reads before zr's standard library, in the order
  # that bundler gives them precedence:
  #
  # 1. each `--gem NAME=VERSION` or `--gem NAME=PATH`;
  # 2. every gem in the Gemfile.lock of `--gemfile PATH`, or of
  #    `BUNDLE_GEMFILE` (which `bundle exec` sets), as `bundle exec ruby`
  #    reads it;
  # 3. zr's standard library (lib/zr/libraries.rb), which is always last.
  #
  # zr never reads another installed gem. The rubygems and bundler that
  # resolve the set are zr's own copies (stdlib/), as JRuby and
  # TruffleRuby ship theirs, so zr needs no bundler of the host and no
  # `bundle exec`. They run in a child of the host ruby
  # (gem_set/resolve.rb): zr itself loads neither, and the compiled
  # compiler has neither. The answer is kept in the cache, keyed on
  # everything the child reads, so a build with the same lock starts no
  # child.
  class GemSet
    # One gem: its name, version, where it came from (`Gemfile.lock` or
    # the flag), its require roots, and why a build cannot use it, or nil.
    Entry = Struct.new(:name, :version, :source, :roots, :refusal, keyword_init: true)

    # The set cannot be resolved: a gem is not installed, a flag names no
    # directory, or the Gemfile does not parse.
    class Unresolved < StandardError; end

    RESOLVE = File.expand_path("gem_set/resolve.rb", __dir__)
    VERSION = 1

    # The environment of the child: the host's gems, without a bundle
    # that this process runs in.
    CHILD_ENV = %w[RUBYOPT RUBYLIB BUNDLER_SETUP BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_VERSION].to_h { |name| [name, nil] }.freeze

    # The variables that change which gems the child finds.
    READS = %w[GEM_HOME GEM_PATH BUNDLE_PATH BUNDLE_APP_CONFIG BUNDLE_WITHOUT BUNDLE_WITH BUNDLE_FROZEN BUNDLE_DEPLOYMENT].freeze

    attr_reader :gems

    def initialize(gems)
      @gems = gems.freeze
      @digest = Digest::SHA256.hexdigest(Marshal.dump(@gems.map(&:to_a)))
      freeze
    end

    EMPTY = new([])

    def empty? = @gems.empty?

    # The require roots, in search order. A refused gem's roots are here
    # too: a require finds its file first, as ruby would, and the build
    # then stops (`refusal`).
    def roots = @gems.flat_map(&:roots)

    # The refusal of the gem whose root holds `path`, or nil. A default
    # gem has no root (its files are ruby's own), so a require of
    # `feature` finds it by the gem's name: `json`, `json/ext`, and
    # `io/console` for io-console.
    def refusal(path, feature = nil)
      name = feature.to_s.delete_suffix(".rb")
      @gems.each do |gem|
        next unless gem.refusal

        return gem.refusal if path && gem.roots.any? { |root| path.start_with?("#{root}/") }
        next unless gem.roots.empty? && !name.empty?

        return gem.refusal if [gem.name, gem.name.tr("-", "/")].any? { |base| name == base || name.start_with?("#{base}/") }
      end
      nil
    end

    # Names the set for a cache key: a build with other gems is another
    # build.
    attr_reader :digest

    # zr's own development Gemfile, in a checkout. `bundle exec rake` sets
    # BUNDLE_GEMFILE to it for every tool, and a build of zr, a spec or a
    # benchmark must not read those gems.
    OWN = File.join(Paths::ROOT, "Gemfile")

    # `flags` are the `--gem` words as [name, value] pairs, and `gemfile`
    # is the path that `--gemfile` gives, or nil.
    def self.resolve(flags, gemfile: nil, env: ENV)
      if gemfile
        gemfile = File.expand_path(gemfile)
        raise Unresolved, "--gemfile #{gemfile}: no such file" unless File.file?(gemfile)
      else
        gemfile = env["BUNDLE_GEMFILE"].to_s.empty? ? nil : File.expand_path(env["BUNDLE_GEMFILE"])
        gemfile = nil if gemfile == OWN
      end
      return EMPTY if flags.empty? && gemfile.nil?

      path = File.join(Paths.cache, "gems", "#{key(flags, gemfile, env)}.set")
      kept(path) || begin
        raise Unresolved, "zr cannot resolve --gem or a Gemfile here. Run zr with ZR_COMPILED=0" if Zr.compiled?

        set = child(flags, gemfile, env)
        Paths.write_atomic(path, Marshal.dump(set.gems.map(&:to_h)))
        set
      end
    end

    # What the child reads: the flags, the Gemfile and its lock, and the
    # variables that move the gems.
    def self.key(flags, gemfile, env)
      key = Digest::SHA256.new
      parts = [VERSION, Zr::VERSION, *flags.flatten, "\0", gemfile.to_s, *READS.map { |name| env[name].to_s }]
      if gemfile
        parts << read(gemfile) << read(lockfile(gemfile))
        parts << read(File.join(File.dirname(gemfile), ".bundle/config"))
      end
      flags.each { |_, value| parts << Paths.stamp(File.expand_path(value)).to_s }
      parts.each { |part| key << part.to_s << "\0" }
      key.hexdigest
    end

    # The lock of `gemfile`, as bundler names it: `gems.locked` for
    # `gems.rb`, else `<gemfile>.lock`.
    def self.lockfile(gemfile) = gemfile.end_with?("gems.rb") ? gemfile.sub(/gems\.rb\z/, "gems.locked") : "#{gemfile}.lock"

    def self.read(path) = File.file?(path) ? File.binread(path) : ""

    # The set that the cache keeps at `path`, while each root is still
    # there. A `gem uninstall` removes a root, and the child runs again.
    def self.kept(path)
      return nil unless File.file?(path)

      set = new(Marshal.load(File.binread(path)).map { |fields| Entry.new(**fields).freeze })
      set.gems.all? { |gem| gem.roots.all? { |root| File.directory?(root) } } ? set : nil
    rescue TypeError, ArgumentError, EOFError
      nil
    end

    def self.child(flags, gemfile, env)
      require "json"
      require_relative "libraries"
      request = JSON.generate(gemfile: gemfile, flags: flags, ports: Ports::ALL.transform_values(&:compat))
      child_env = CHILD_ENV.merge("BUNDLE_GEMFILE" => gemfile)
      READS.each { |name| child_env[name] = env[name] }
      # The child's warnings go to this stderr, where the user sees them.
      command = [RbConfig.ruby, "--disable-gems", "-I", Libraries.root, RESOLVE]
      out = IO.popen(child_env, command, "r+", chdir: gemfile ? File.dirname(gemfile) : Dir.pwd) do |io|
        io.write(request)
        io.close_write
        io.read
      end
      answer = begin
        JSON.parse(out)
      rescue JSON::ParserError
        raise Unresolved, "the gem resolver (#{RbConfig.ruby} #{RESOLVE}) failed with status #{$?.exitstatus}"
      end
      raise Unresolved, answer["error"] if answer["error"]
      if answer["rubygems"] != Libraries.root
        raise Unresolved, "the gem resolver loaded rubygems from #{answer["rubygems"]}, not from zr's own #{Libraries.root}"
      end

      new(answer.fetch("gems").map { |fields| Entry.new(**fields.transform_keys(&:to_sym)).freeze })
    end
  end
end
