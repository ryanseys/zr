# frozen_string_literal: true

require_relative "../../lib/zr/child_ruby"
require_relative "flag"
require_relative "harness/child"
require "digest/sha2"
require "fileutils"
require "rbconfig"
require_relative "../../lib/zr/config"
require_relative "../../lib/zr/gem_set"
require_relative "../../lib/zr/target"

module Zr
  module Test
    # A C extension that a test gives as C source in a heredoc, so the
    # repository holds no C file. It is built as mkmf builds one, with the
    # host ruby's headers and flags: an object for zr to link
    # (`ZR_EXT_OBJECTS`) and a bundle for ruby to load. Each source is
    # built once, in tmp/test-ext/<arch>/<digest>. A program's binary goes
    # after its runs, and `sweep` removes what no run used for KEEP_DAYS.
    #
    # `outputs` runs one program under ruby with the bundle, and as a
    # binary that zr builds with the object, and gives both outputs, so a
    # test checks that zr gives ruby's answer.
    module CExt
      ROOT = File.expand_path("../..", __dir__)
      # One directory for each host's ruby: a darwin run and a linux run
      # of one checkout (in a container) build apart.
      DIR = File.join(ROOT, "tmp", "test-ext", RbConfig::CONFIG["arch"])
      # A built extension that no run used for this many days goes, and so
      # does the directory of a host whose ruby no longer runs the tests.
      KEEP_DAYS = 30
      DAY = 86_400

      # Sweeps once, in the parent, as a run starts (a minitest plugin).
      def self.minitest_plugin_init(_options) = sweep

      # A built extension: its directory, which a program's require
      # searches, and its bundle and object.
      Built = Data.define(:dir, :bundle, :object)

      # The output of one run: stdout, then stderr, then the exit status.
      Output = Data.define(:stdout, :stderr, :status)

      # The hosts where zr runs C extensions: each target that builds a
      # binary (`Target#native_ext?`). A test runs on the host's own
      # target, as ruby there gives each answer.
      HOSTS = Target.all.select(&:native_ext?).freeze
      UNSUPPORTED = "needs a host of #{HOSTS.map(&:triple).join(", ")}"

      module_function

      # Whether this host runs zr's C extensions.
      #: () -> bool
      def supported? = HOSTS.any?(&:native?)

      # `libruby` links the bundle with ruby's shared library, as mkmf
      # does under a ruby built with --enable-shared.
      #: (String name, String source, ?libruby: bool) -> Built
      def build(name, source, libruby: false)
        config = RbConfig::CONFIG
        dir = File.join(DIR, Digest::SHA256.hexdigest([name, source, config["ruby_version"], libruby].join("\0"))[0, 16])
        built = Built.new(dir: dir, bundle: File.join(dir, "#{name}.#{config["DLEXT"]}"), object: File.join(dir, "#{name}.o"))
        return used(built) if File.exist?(built.bundle)

        FileUtils.mkdir_p(dir)
        # Test workers run in parallel; one builds, and the others wait.
        File.open(File.join(dir, "lock"), File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          compile(config, name, source, built, libruby) unless File.exist?(built.bundle)
        end
        built
      end

      # Marks the directory of `built` as used, at most once a day, so the
      # sweep keeps it. Returns `built`.
      #: (Built built) -> Built
      def used(built, now = Time.now)
        File.utime(now, now, built.dir) if File.mtime(built.dir) < now - DAY
        built
      end

      # Removes each entry below `root` (`<arch>/<entry>`) that no run used
      # for KEEP_DAYS, then each host directory that is left empty.
      #: (?String root, ?Time now) -> void
      def sweep(root = File.dirname(DIR), now = Time.now)
        cutoff = now - (KEEP_DAYS * DAY)
        Dir.glob("*/*", base: root).each do |rel|
          path = File.join(root, rel)
          FileUtils.rm_rf(path) if File.mtime(path) < cutoff
        end
        Dir.glob("*", base: root).each do |host|
          path = File.join(root, host)
          Dir.rmdir(path) if File.directory?(path) && Dir.empty?(path)
        end
      end

      #: (Hash[String, String] config, String name, String source, Built built, bool libruby) -> void
      def compile(config, name, source, built, libruby)
        c = File.join(built.dir, "#{name}.c")
        File.write(c, source)
        flags = config["CFLAGS"].split + config["CPPFLAGS"].split + config["ARCH_FLAG"].split
        includes = ["-I#{config["rubyhdrdir"]}", "-I#{config["rubyarchhdrdir"]}"]
        run!("cc", *flags, *includes, "-fPIC", "-c", c, "-o", built.object)
        shared = libruby ? ["-L#{config["libdir"]}", *config["LIBRUBYARG_SHARED"].split] : []
        run!(*config["LDSHARED"].split, *config["DLDFLAGS"].split, *config["ARCH_FLAG"].split, built.object, *shared, "-o", "#{built.bundle}.part")
        File.rename("#{built.bundle}.part", built.bundle)
      end

      # Runs `program` (which requires the extension by name) under ruby
      # and as a zr binary. Returns `[ruby, zr]`. The program finds the
      # extension through a literal $LOAD_PATH entry, which zr reads as it
      # builds.
      #: (Built ext, String program, ?env: Hash[String, String]) -> [Output, Output]
      def outputs(ext, program, env: {})
        ruby, runs = outputs_under(ext, program, [{}], env: env)
        [ruby, runs.fetch(0)]
      end

      # The same, but runs the binary once in each of `binary_envs`: the
      # collector's switches (ZR_GC_STRESS), which ruby does not read.
      # Returns `[ruby, [zr...]]`; a failed build stands for every run.
      # `mode` is how the binary runs the extension (`ZR_EXT`): static
      # links its object, and embed and dynamic take its bundle.
      #: (Built ext, String program, Array[Hash[String, String]] binary_envs, ?env: Hash[String, String], ?mode: String) -> [Output, Array[Output]]
      def outputs_under(ext, program, binary_envs, env: {}, mode: "static")
        source = "$LOAD_PATH.unshift(File.expand_path(\".\", __dir__))\n#{program}"
        path = File.join(ext.dir, "prog_#{Digest::SHA256.hexdigest(source)[0, 12]}.rb")
        File.write(path, source)
        ruby = run(env, RbConfig.ruby, path)
        # Each set of runs has its own binary: two tests of one program
        # build at the same time.
        bin = "#{path.delete_suffix(".rb")}-#{Digest::SHA256.hexdigest([binary_envs, mode].inspect)[0, 8]}"
        given = mode == "static" ? "#{ext.bundle}=#{ext.object}" : ext.bundle
        zr_env = env.merge("ZR_EXT_OBJECTS" => given, "ZR_EXT" => mode)
        built = run(zr_env, File.join(ROOT, "bin", "zr"), "build", path, "-o", bin)
        return [ruby, binary_envs.map { built }] unless built.status.zero?

        [ruby, binary_envs.map { |extra| run(env.merge(extra), bin) }]
      ensure
        FileUtils.rm_f(bin) if bin
      end

      # Runs `program` with several extensions under ruby, and as one zr
      # binary that links the extensions in `static` from their objects and
      # embeds the others' bundles. Returns `[ruby, zr]`.
      #: (Array[Built] exts, String program, static: Array[Built]) -> [Output, Output]
      def outputs_together(exts, program, static:)
        paths = exts.map { |ext| "$LOAD_PATH.unshift(#{ext.dir.inspect})\n" }.join
        dir = File.join(DIR, "together")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "prog_#{Digest::SHA256.hexdigest([paths, program, static.map(&:bundle)].inspect)[0, 12]}.rb")
        File.write(path, paths + program)
        ruby = run({}, RbConfig.ruby, path)
        given = exts.map { |ext| static.include?(ext) ? "#{ext.bundle}=#{ext.object}" : ext.bundle }.join(" ")
        bin = path.delete_suffix(".rb")
        built = run({ "ZR_EXT_OBJECTS" => given }, File.join(ROOT, "bin", "zr"), "build", path, "-o", bin)
        [ruby, built.status.zero? ? run({}, bin) : built]
      ensure
        FileUtils.rm_f(bin) if bin
      end

      # The environment of a child that sees the gems installed in this
      # ruby, as a user's ruby and zr do: the test runs under Bundler,
      # which hides every gem outside the bundle.
      UNBUNDLED = ChildRuby::UNBUNDLED

      # The installed gem `name`'s newest version, or nil. It looks where
      # an UNBUNDLED child looks: ruby's own gems and GEM_HOME (the
      # docker ruby images install gems in /usr/local/bundle).
      #: (String name) -> String?
      def installed(name)
        (Gem.path | [Gem.default_dir])
          .flat_map { |dir| Dir[File.join(dir, "specifications", "#{name}-*.gemspec")] }
          .filter_map { |path| Gem::Specification.load(path) }
          .select { |spec| spec.name == name }
          .max_by(&:version)&.version&.to_s
      end

      # Runs `program`, which requires the installed gem `name` at
      # `version`, under ruby and as a zr binary that links the gem's real
      # C extension (`--native-ext`), once in each of `binary_envs`. The
      # program asks for the version as any program does, with `gem`. The
      # build runs under `build_env` too (`ZR_EXT_CONFIG`). `home` is the
      # gem home that holds the gem, or the homes of the gem and of its
      # dependencies, or nil for this ruby's own.
      # @rbs name: String
      # @rbs version: String
      # @rbs program: String
      # @rbs binary_envs: Array[Hash[String, String]]
      # @rbs build_env: Hash[String, String]
      # @rbs home: String | Array[String] | nil
      # @rbs return: [Output, Array[Output]]
      def gem_outputs(name, version, program, binary_envs, build_env: {}, home: nil)
        # The gem's homes come first; ruby's own gems stay, for zr itself
        # and for the gem's other dependencies.
        env = home ? UNBUNDLED.merge("GEM_PATH" => [*home, *Gem.path].join(File::PATH_SEPARATOR)) : UNBUNDLED
        program = %(gem #{name.inspect}, #{version.inspect}\n#{program}) unless GemSet.requests(program).key?(name)
        dir = File.join(DIR, "gem-#{name}-#{version}")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "prog_#{Digest::SHA256.hexdigest(program)[0, 12]}.rb")
        File.write(path, program)
        ruby = run(env, RbConfig.ruby, path)
        # Each set of runs has its own binary: two tests of one program
        # build at the same time.
        bin = "#{path.delete_suffix(".rb")}-#{Digest::SHA256.hexdigest([binary_envs, build_env, home].inspect)[0, 8]}"
        built = run(env.merge(build_env), File.join(ROOT, "bin", "zr"), "build", "--native-ext", "#{name}=#{version}", path, "-o", bin)
        return [ruby, binary_envs.map { built }] unless built.status.zero?

        [ruby, binary_envs.map { |extra| run(env.merge(extra), bin) }]
      ensure
        FileUtils.rm_f(bin) if bin
      end

      #: (Hash[String, String] env, *String command) -> Output
      def run(env, *command)
        answer, = Harness::Child.run(command, cwd: Dir.pwd, seconds: nil, megabytes: nil, env: env)
        Output.new(stdout: answer.stdout, stderr: answer.stderr, status: answer.code)
      end

      #: (*String command) -> void
      def run!(*command)
        answer, = Harness::Child.run(command, cwd: Dir.pwd, seconds: nil, megabytes: nil, merge: true)
        raise "#{command.first} failed:\n#{answer.stdout}" unless answer.code.zero?
      end
    end
  end
end

Minitest.register_plugin(Zr::Test::CExt)
