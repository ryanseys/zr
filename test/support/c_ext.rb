# frozen_string_literal: true

require "digest/sha2"
require "fileutils"
require "open3"
require "rbconfig"

module Zr
  module Test
    # A C extension that a test gives as C source in a heredoc, so the
    # repository holds no C file. It is built as mkmf builds one, with the
    # host ruby's headers and flags: an object for zr to link
    # (`ZR_EXT_OBJECTS`) and a bundle for ruby to load. Each source is
    # built once, in tmp/test-ext/<digest>.
    #
    # `outputs` runs one program under ruby with the bundle, and as a
    # binary that zr builds with the object, and gives both outputs, so a
    # test checks that zr gives ruby's answer.
    module CExt
      ROOT = File.expand_path("../..", __dir__)
      DIR = File.join(ROOT, "tmp", "test-ext")

      # A built extension: its directory, which a program's require
      # searches, and its bundle and object.
      Built = Data.define(:dir, :bundle, :object)

      # The output of one run: stdout, then stderr, then the exit status.
      Output = Data.define(:stdout, :stderr, :status)

      module_function

      #: (String name, String source) -> Built
      def build(name, source)
        config = RbConfig::CONFIG
        dir = File.join(DIR, Digest::SHA256.hexdigest([name, source, config["ruby_version"]].join("\0"))[0, 16])
        built = Built.new(dir: dir, bundle: File.join(dir, "#{name}.bundle"), object: File.join(dir, "#{name}.o"))
        return built if File.exist?(built.bundle)

        FileUtils.mkdir_p(dir)
        # Test workers run in parallel; one builds, and the others wait.
        File.open(File.join(dir, "lock"), File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX)
          compile(config, name, source, built) unless File.exist?(built.bundle)
        end
        built
      end

      #: (Hash[String, String] config, String name, String source, Built built) -> void
      def compile(config, name, source, built)
        c = File.join(built.dir, "#{name}.c")
        File.write(c, source)
        flags = config["CFLAGS"].split + config["CPPFLAGS"].split + config["ARCH_FLAG"].split
        includes = ["-I#{config["rubyhdrdir"]}", "-I#{config["rubyarchhdrdir"]}"]
        run!("cc", *flags, *includes, "-fPIC", "-c", c, "-o", built.object)
        run!(*config["LDSHARED"].split, *config["DLDFLAGS"].split, *config["ARCH_FLAG"].split, built.object, "-o", "#{built.bundle}.part")
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
      end

      # The environment of a child that sees the gems installed in this
      # ruby, as a user's ruby and zr do: the test runs under Bundler,
      # which hides every gem outside the bundle.
      UNBUNDLED = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB]
                  .to_h { |name| [name, nil] }.freeze

      # The installed gem `name`'s newest version, or nil.
      #: (String name) -> String?
      def installed(name)
        Dir[File.join(Gem.default_dir, "specifications", "#{name}-*.gemspec")]
          .filter_map { |path| Gem::Specification.load(path) }
          .select { |spec| spec.name == name }
          .max_by(&:version)&.version&.to_s
      end

      # Runs `program`, which requires the installed gem `name` at
      # `version`, under ruby and as a zr binary that links the gem's real
      # C extension (`--native-ext`), once in each of `binary_envs`. The
      # build runs under `build_env` too (`ZR_EXT_CONFIG`).
      # @rbs name: String
      # @rbs version: String
      # @rbs program: String
      # @rbs binary_envs: Array[Hash[String, String]]
      # @rbs build_env: Hash[String, String]
      # @rbs return: [Output, Array[Output]]
      def gem_outputs(name, version, program, binary_envs, build_env: {})
        dir = File.join(DIR, "gem-#{name}-#{version}")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "prog_#{Digest::SHA256.hexdigest(program)[0, 12]}.rb")
        File.write(path, program)
        ruby = run(UNBUNDLED, RbConfig.ruby, path)
        # Each set of runs has its own binary: two tests of one program
        # build at the same time.
        bin = "#{path.delete_suffix(".rb")}-#{Digest::SHA256.hexdigest([binary_envs, build_env].inspect)[0, 8]}"
        gem = "#{name}=#{version}"
        built = run(UNBUNDLED.merge(build_env), File.join(ROOT, "bin", "zr"), "build", "--native-ext", gem, "--gem", gem, path, "-o", bin)
        return [ruby, binary_envs.map { built }] unless built.status.zero?

        [ruby, binary_envs.map { |extra| run(UNBUNDLED.merge(extra), bin) }]
      end

      #: (Hash[String, String] env, *String command) -> Output
      def run(env, *command)
        out, err, status = Open3.capture3(env, *command)
        Output.new(stdout: out, stderr: err, status: status.exitstatus || -1)
      end

      #: (*String command) -> void
      def run!(*command)
        out, status = Open3.capture2e(*command)
        raise "#{command.first} failed:\n#{out}" unless status.success?
      end
    end
  end
end
