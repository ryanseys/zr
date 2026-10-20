# frozen_string_literal: true

require "digest/sha2"
require "rbconfig"
require_relative "child_ruby"
require_relative "paths"
require_relative "library/ports"
require_relative "library/stdlib"
require_relative "cache/store"
require_relative "version"

module Zr
  # The gems that a build reads, as ruby finds them:
  #
  # 1. with `BUNDLE_GEMFILE` (which `bundle exec` sets), every gem in the
  #    Gemfile's lock, before zr's standard library, as `bundle exec ruby`
  #    puts them on the load path;
  # 2. without it, the newest version of each gem that rubygems has
  #    installed on its path (GEM_HOME, GEM_PATH, ~/.gem, the default
  #    directory of the ruby on PATH), after zr's standard library, as
  #    ruby searches its load path first and its gems only then.
  #
  # The rubygems and bundler that resolve the set are zr's own copies
  # (vendor/ruby), as JRuby and TruffleRuby ship theirs, so zr needs no
  # bundler of the host and no `bundle exec`. They run in a child of the
  # host ruby (gem_set/resolve.rb): zr itself loads neither, and the
  # compiled compiler has neither. The answer is kept in the cache, keyed
  # on everything the child reads, so a build with the same gems starts no
  # child.
  class GemSet
    # One gem: its name, version, where it came from (`Gemfile.lock` or
    # the flag), its require roots, and why a build cannot use it, or nil.
    # A gem whose refusal is `native` has a C extension that zr does not
    # port: its Ruby files compile, and a require of its C part, which no
    # root holds, raises LoadError if it runs, as in a ruby where the
    # extension did not build. The build says so (`Hir::Build#gem_refusal`).
    # @rbs skip -- typed in sig/zr/gem_set.rbs
    Entry = Struct.new(:name, :version, :source, :roots, :refusal, :native, :requested) do
      # The root of the gem that holds the file `path`, as given or as its
      # real path, or nil: a require finds a file through a symlinked
      # directory by the real path (`Loader#real_root`).
      def root_of(path) # steep:ignore UndeclaredMethodDefinition
        roots.each do |root|
          real = File.directory?(root) ? File.realpath(root) : root
          [root, real].each { |dir| return dir if path.start_with?("#{dir}/") }
        end
        nil
      end

      # Whether rubygems installed the gem on its path, as opposed to a
      # Gemfile's lock naming it.
      def installed? = source == INSTALLED # steep:ignore UndeclaredMethodDefinition

      def holds?(path) # steep:ignore UndeclaredMethodDefinition
        # @type self: Entry
        !root_of(path).nil?
      end
    end

    # The set cannot be resolved: a gem is not installed, a flag names no
    # directory, or the Gemfile does not parse.
    class Unresolved < StandardError
      include Error
    end

    RESOLVE = File.expand_path("gem_set/resolve.rb", __dir__) #: String
    # The source of a gem from rubygems' path (gem_set/resolve.rb).
    INSTALLED = "installed"
    VERSION = 4

    # The variables that change which gems the child finds.
    READS = %w[GEM_HOME GEM_PATH BUNDLE_PATH BUNDLE_APP_CONFIG BUNDLE_WITHOUT BUNDLE_WITH BUNDLE_FROZEN BUNDLE_DEPLOYMENT].freeze

    attr_reader :gems #: Array[Entry]

    #: (Array[Entry] gems) -> void
    def initialize(gems)
      @gems = gems.freeze
      @digest = Digest::SHA256.hexdigest(Marshal.dump(@gems.map(&:to_a)))
      freeze
    end

    EMPTY = new([]) #: GemSet

    #: () -> bool
    def empty? = @gems.empty?

    # The require roots, in search order. A refused gem's roots are here
    # too: a require finds its file first, as ruby would, and the build
    # then stops (`refusal`).
    # A Gemfile lock's gems come first, as `bundle exec` puts them on the
    # load path, and so do an installed gem that the program asks for by
    # version (`gem "json", "2.19.1"`, which puts it there) and one newer
    # than zr's own copy of it: rubygems' require of a default gem's file
    # runs `gem` with no version, which activates the newest one installed
    # (rubygems/core_ext/kernel_require.rb).
    #: () -> Array[String]
    def roots = @gems.reject { |gem| later?(gem) }.flat_map(&:roots)

    # The roots of the other installed gems, which a require searches
    # after zr's standard library, as rubygems activates a gem only for a
    # file that the load path does not have.
    #: () -> Array[String]
    def installed_roots = @gems.select { |gem| later?(gem) }.flat_map(&:roots)

    # Whether a require finds `gem` only after zr's standard library: an
    # installed gem that the program did not ask for by version (`gem`),
    # and that is not newer than zr's own copy.
    #: (Entry gem) -> bool
    def later?(gem) = gem.installed? && !gem.requested && !newer?(gem)

    # Whether the installed `gem` is newer than the copy of it in zr's
    # standard library (a default or bundled gem, or a port).
    #: (Entry gem) -> bool
    def newer?(gem)
      own = Library::Stdlib::DEFAULT[gem.name] || Library::Stdlib::BUNDLED[gem.name] || Library::Stdlib::OTHER_BUNDLED[gem.name] ||
            Library::Ports::ALL[gem.name]&.version
      own && gem.version ? GemSet.compare(gem.version, own) == 1 : false
    end

    # `a <=> b` as Gem::Version orders versions, since zr itself loads no
    # rubygems: numbers part by part, a missing part as 0, and a
    # prerelease part (letters) below any number, so "3.1.0.pre" is
    # below "3.1".
    #: (String a, String b) -> Integer
    def self.compare(a, b)
      x = segments(a)
      y = segments(b)
      [x.size, y.size].max.times do |i|
        p = x[i] || 0
        q = y[i] || 0
        next if p == q
        # A word sorts before a number, as Gem::Version sorts a prerelease.
        return p <=> q if p.is_a?(String) == q.is_a?(String)
        return p.is_a?(String) ? -1 : 1
      end
      0
    end

    # The parts of a version: its numbers until the first prerelease part,
    # without trailing zeros, then the rest (Gem::Version's canonical
    # segments).
    #: (String version) -> Array[Integer | String]
    def self.segments(version)
      parts = version.scan(/\d+|[a-z]+/i).map { |part| part.match?(/\A\d/) ? part.to_i : part }
      cut = parts.index { |part| part.is_a?(String) } || parts.size
      head = parts.take(cut)
      head.pop while head.last == 0
      head + parts.drop(cut)
    end

    # The refusal of the gem whose root holds `path`, or nil. A default
    # gem has no root (its files are ruby's own), so a require of
    # `feature` finds it by the gem's name: `json`, `json/ext`, and
    # `io/console` for io-console.
    #: (String? path, ?String? feature) -> String?
    def refusal(path, feature = nil) = refused(path, feature)&.refusal

    # The gem whose refusal `refusal` gives, or nil.
    #: (String? path, ?String? feature) -> Entry?
    def refused(path, feature = nil)
      name = feature.to_s.delete_suffix(".rb")
      @gems.find do |gem|
        next false unless gem.refusal
        next true if path && gem.holds?(path)

        gem.roots.empty? && !name.empty? && [gem.name, gem.name.tr("-", "/")].any? { |base| name == base || name.start_with?("#{base}/") }
      end
    end

    # Names the set for a cache key: a build with other gems is another
    # build.
    attr_reader :digest #: String

    # zr's own development Gemfile, in a checkout. `bundle exec rake` sets
    # BUNDLE_GEMFILE to it for every tool, and a build of zr, a spec or a
    # benchmark must not read those gems.
    OWN = File.join(Paths::ROOT, "Gemfile") #: String

    # A literal `gem "name", "requirement", ...` at the start of a line of
    # `source`: the versions that a program asks rubygems for before it
    # requires the gem. A scan of lines, not a parse, so a run that its
    # cache answers loads no parser.
    REQUEST = /^[ \t]*gem[ \t(]+(["'])([\w.-]+)\1((?:[ \t]*,[ \t]*(["'])[^"'\n]+\4)*)/

    # The gems that `source` asks for by version, by name, each with its
    # requirements ([] for none): `gem "json", "2.19.1"` is
    # {"json" => ["2.19.1"]}. A call with an interpolated argument (such
    # as a line of a heredoc that writes a Gemfile) names no version that
    # a build can know, so it asks for none.
    #: (String source) -> Hash[String, Array[String]]
    def self.requests(source)
      source.scan(REQUEST).filter_map do |_, name, rest|
        next if rest.include?('#{')

        [name, rest.scan(/(["'])([^"'\n]+)\1/).map(&:last)] #: [String, Array[String]]
      end.to_h
    end

    # The gems of the environment `env`: a Gemfile's lock when
    # BUNDLE_GEMFILE names one (but zr's own), else rubygems' path, with
    # the versions that `requests` asks for. A gem whose own C the build
    # links (`--native-ext`) is asked for too, so that its Ruby half comes
    # from the same install as its C.
    #: (?env: RBS::Unnamed::ENVClass, ?requests: Hash[String, Array[String]]) -> GemSet
    def self.resolve(env: ENV, requests: {})
      requests = Config.current.native_ext.each_with_object(requests.dup) do |(name, version), all|
        all[name] ||= [*version] unless version == false
      end
      named = env["BUNDLE_GEMFILE"].to_s
      gemfile = named.empty? ? nil : File.expand_path(named)
      gemfile = nil if gemfile == OWN
      raise Unresolved, "BUNDLE_GEMFILE names #{gemfile}, which does not exist" if gemfile && !File.file?(gemfile)

      key = key(gemfile, env, requests)
      kept(Cache::Store.read(:gems, key)) || begin
        set = child(gemfile, env, requests)
        Cache::Store.write(:gems, key, set.gems.map(&:to_h))
        set
      end
    end

    # What the child reads: the Gemfile and its lock, the variables that
    # move the gems, and each directory of rubygems' path, whose
    # `specifications` a `gem install` or `gem uninstall` changes.
    #: (String? gemfile, RBS::Unnamed::ENVClass env, Hash[String, Array[String]] requests) -> String
    def self.key(gemfile, env, requests)
      parts = [VERSION, Zr::VERSION, gemfile.to_s, *READS.map { |name| env[name].to_s }, requests.sort.inspect]
      # The child refuses a port's gem outside the port's range.
      parts.concat(Library::Ports::ALL.map { |name, port| "#{name} #{port.compat}" })
      if gemfile
        parts << read(gemfile) << read(lockfile(gemfile))
        parts << read(File.join(File.dirname(gemfile), ".bundle/config"))
      else
        gem_path(env).each { |dir| parts << dir << Paths.stamp(File.join(dir, "specifications")).to_s }
      end
      Cache::Store.key(*parts)
    end

    # The directories of rubygems' path in `env`, as Gem::PathSupport and
    # Gem.default_path make it: GEM_PATH (else the user's directory and
    # the default one), then GEM_HOME (else the default one).
    #: (RBS::Unnamed::ENVClass env) -> Array[String]
    def self.gem_path(env)
      config = RbConfig::CONFIG
      default = File.join(config["rubylibprefix"], "gems", config["ruby_version"])
      home = env["HOME"].to_s
      path = if env["GEM_PATH"].to_s.empty?
               [*(File.join(home, ".gem", "ruby", config["ruby_version"]) unless home.empty?), default]
             else
               env["GEM_PATH"].split(File::PATH_SEPARATOR)
             end
      [*path, env["GEM_HOME"].to_s.empty? ? default : env["GEM_HOME"]].uniq
    end

    # The lock of `gemfile`, as bundler names it: `gems.locked` for
    # `gems.rb`, else `<gemfile>.lock`.
    #: (String gemfile) -> String
    def self.lockfile(gemfile) = gemfile.end_with?("gems.rb") ? gemfile.sub(/gems\.rb\z/, "gems.locked") : "#{gemfile}.lock"

    #: (String path) -> String
    def self.read(path) = File.file?(path) ? File.binread(path) : ""

    # The set of the kept `rows`, while each root is still there. A
    # `gem uninstall` removes a root, and the child runs again.
    #: (Array[Hash[Symbol, untyped]]? rows) -> GemSet?
    def self.kept(rows)
      return nil unless rows

      set = new(rows.map { |fields| Entry.new(**fields).freeze })
      set.gems.all? { |gem| gem.roots.all? { |root| File.directory?(root) } } ? set : nil
    rescue TypeError, ArgumentError
      nil
    end

    # The ruby that runs the resolver (`Config#host_ruby`).
    #: () -> String
    def self.ruby = Config.current.host_ruby

    #: (String? gemfile, RBS::Unnamed::ENVClass env, Hash[String, Array[String]] requests) -> GemSet
    def self.child(gemfile, env, requests)
      require "json"
      require_relative "library/roots"
      request = JSON.generate(gemfile: gemfile, requests: requests, ports: Library::Ports::ALL.transform_values(&:compat))
      # The host's gems, without a bundle that this process runs in.
      child_env = ChildRuby::UNBUNDLED.merge("BUNDLE_GEMFILE" => gemfile) #: Hash[String, String?]
      READS.each { |name| child_env[name] = env[name] }
      # The child's warnings go to this stderr, where the user sees them.
      command = [ruby, "--disable-gems", "-I", Library::Roots.pure, RESOLVE]
      out = IO.popen(child_env, command, "r+", chdir: gemfile ? File.dirname(gemfile) : Dir.pwd) do |io|
        io.write(request)
        io.close_write
        io.read
      end
      answer = begin
        JSON.parse(out)
      rescue JSON::ParserError
        # `IO.popen` with a block waits for the child, so `$?` is set.
        status = $? #: Process::Status
        raise Unresolved, "the gem resolver (#{ruby} #{RESOLVE}) failed with status #{status.exitstatus}"
      end #: Hash[String, untyped]
      raise Unresolved, answer["error"] if answer["error"]
      if answer["rubygems"] != Library::Roots.pure
        raise Unresolved, "the gem resolver loaded rubygems from #{answer["rubygems"]}, not from zr's own #{Library::Roots.pure}"
      end

      new(answer.fetch("gems").map { |fields| Entry.new(**fields.transform_keys(&:to_sym)).freeze })
    end
  end
end
