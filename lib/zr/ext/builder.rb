# frozen_string_literal: true

require "digest/sha2"
require "open3"
require "rbconfig"
require_relative "../child_ruby"
require_relative "makefile"
require_relative "source"
require_relative "../refused"
require_relative "../cache/store"
require_relative "../target"
require_relative "../library/layout"
require_relative "c_api"

module Zr
  module Ext
    # Builds a C extension from its source, as `gem install` would, into a
    # directory that the store keeps (`:ext`), for a gem that has no
    # compiled extension to link or that a build configures itself
    # (`ZR_EXT_CONFIG`). The host ruby runs the extension's extconf.rb,
    # which writes mkmf's Makefile; zr reads it and runs cc for each
    # source. A Makefile with rules of its own (`Makefile#standard?`)
    # runs under make instead.
    #
    # For another target than this host (aarch64-linux-musl), mkmf takes
    # that target's RbConfig (`--target-rbconfig`, target_rbconfig.rb):
    # the headers and rbconfig.rb of its ruby, which vendor/ holds, and the
    # target's cross toolchain. mkmf's link checks link against a stand-in
    # libruby that defines each function of zr's C API (`libruby`), so
    # have_func finds what zr has.
    #
    # extconf.rb is the gem's code, so only a user's build runs it, never
    # a gem sweep.
    class Builder
      # @rbs @extconf: String
      # @rbs @args: Array[String]
      # @rbs @ruby: String
      # @rbs @target: Target

      # The child that runs extconf.rb runs outside zr's bundle, which
      # would hide the gems that an extconf requires.
      CLEAN_ENV = ChildRuby::UNBUNDLED

      # The file that mkmf loads as the target's RbConfig.
      TARGET_RBCONFIG = File.expand_path("target_rbconfig.rb", __dir__)

      # The file in a built extension's directory that names the directory
      # extconf.rb ran in, before the store gave the build its own name. An
      # extconf that builds a library there (nokogiri's libgumbo.a) names
      # it in LIBS by that first path.
      BUILT_IN = "zr-built-in"

      # `extconf` is the extension's extconf.rb, and `args` the words it
      # takes (`--use-system-libraries`). `ruby` runs it: zr's host ruby,
      # whose headers the extension compiles against on this host's own
      # target. `target` is the target that the extension is for.
      #: (String extconf, ?args: Array[String], ?ruby: String, ?target: Target) -> void
      def initialize(extconf, args: [], ruby: RbConfig.ruby, target: Target.default)
        @extconf = File.expand_path(extconf)
        @args = args
        @ruby = ruby
        @target = target
      end

      # The extension, built once for its sources, its arguments and this
      # ruby. `gem_dir` is the gem's directory: the bundle that a require
      # finds is under its lib/.
      #: (String gem_dir) -> Source
      def source(gem_dir)
        dir = build
        makefile = Makefile.read(File.join(dir, "Makefile"))
        Source.new(bundle: File.join(gem_dir, "lib", "#{makefile.feature}.#{@target.dlext}"), init: makefile.init,
                   objects: makefile.objects, libraries: moved(makefile.libraries, dir), library: nil, mode: :static)
      end

      # `libraries` with each path under the directory that extconf.rb ran
      # in (BUILT_IN) under `dir`, where the build is now.
      #: (Array[String] libraries, String dir) -> Array[String]
      def moved(libraries, dir)
        record = File.join(dir, BUILT_IN)
        return libraries unless File.file?(record)

        was = "#{File.read(record)}/"
        libraries.map { |word| word.include?(was) ? word.gsub(was) { "#{dir}/" } : word }
      end

      # The directory of the built extension: its Makefile and objects.
      #: () -> String
      def build
        key = Cache::Store.key("ext", ABI, @ruby, RbConfig::CONFIG["ruby_version"], @target.triple, *@args, *inputs, *cross_inputs)
        # Two builds of one extension: one runs extconf, the other waits.
        Cache::Store.once(:ext, key) do
          Cache::Store.write(:ext, key) do |dir|
            File.write(File.join(dir, BUILT_IN), dir)
            run(dir, @ruby, @extconf, *cross_args, *@args, env: env)
            makefile = Makefile.read(File.join(dir, "Makefile"))
            makefile.standard? && makefile.sources.all? { |c, _| File.file?(c) } ? compile(dir, makefile) : run(dir, "make", env: env)
          end
        end
      end

      private

      # Whether the extension is for another target than this host's.
      #: () -> bool
      def cross? = !@target.native?

      # extconf.rb's words for the target's RbConfig, none for this host.
      #: () -> Array[String]
      def cross_args = cross? ? ["--target-rbconfig=#{TARGET_RBCONFIG}"] : []

      # What else a cross build depends on: the target's rbconfig.rb, the
      # file that loads it, and zr's C API.
      #: () -> Array[String]
      def cross_inputs
        return [] unless cross?

        [Digest::SHA256.file(rbconfig).hexdigest, Digest::SHA256.file(TARGET_RBCONFIG).hexdigest, *CApi.names.sort]
      end

      # The rbconfig.rb of the target's ruby, which vendor/ holds.
      #: () -> String
      def rbconfig
        path = Library::Layout.target_rbconfig(@target.triple)
        return path if File.file?(path)

        raise Refused, "#{File.basename(File.dirname(@extconf))}: zr has no ruby headers for #{@target.triple} " \
                       "(#{Paths.shown(path)}), so it builds no C extension for it"
      end

      # The environment of the child that runs extconf.rb, for the target.
      #: () -> Hash[String, String?]
      def env
        return CLEAN_ENV unless cross?

        tools = %w[cc c++ ar].to_h { |name| [name, @target.tool(name)] }
        tools.each do |name, path|
          raise Refused, "#{File.basename(File.dirname(@extconf))}: no #{name} for #{@target.triple} on this host" unless path
        end
        CLEAN_ENV.merge("ZR_TARGET_RBCONFIG" => rbconfig, "ZR_TARGET_CC" => tools["cc"], "ZR_TARGET_CXX" => tools["c++"],
                        "ZR_TARGET_AR" => tools["ar"], "ZR_TARGET_LIBDIR" => libruby)
      end

      # The directory of the stand-in libruby.so for the target: a shared
      # library that defines a function of each name of zr's C API, which
      # mkmf's link checks link against. No program links it.
      #: () -> String
      def libruby
        names = CApi.names.sort
        key = Cache::Store.key("libruby", ABI, @target.triple, *names)
        Cache::Store.once(:ext, key) do
          Cache::Store.write(:ext, key) do |dir|
            File.write(File.join(dir, "libruby.c"), names.map { |name| "void #{name}(void) {}\n" }.join)
            run(dir, @target.tool("cc").to_s, "-shared", "-fPIC", "-o", "libruby.so", "libruby.c", env: CLEAN_ENV)
          end
        end
      end

      # Each source file's name and digest: a change to any rebuilds.
      #: () -> Array[String]
      def inputs
        root = File.dirname(@extconf)
        Dir.glob("**/*", base: root).sort.filter_map do |name|
          path = File.join(root, name)
          "#{name}:#{Digest::SHA256.file(path).hexdigest}" if File.file?(path)
        end
      end

      # Compiles each source as mkmf's rules do: C with CFLAGS, C++ with
      # CXXFLAGS, in the build directory, where the Makefile's
      # `-I.` and `-I$(srcdir)` point.
      #: (String dir, Makefile makefile) -> void
      def compile(dir, makefile)
        makefile.sources.each do |source, object|
          cxx = !source.end_with?(".c", ".m")
          compiler = makefile.words(cxx ? "CXX" : "CC")
          flags = makefile.words("INCFLAGS") + makefile.words("CPPFLAGS") + makefile.words(cxx ? "CXXFLAGS" : "CFLAGS")
          run(dir, *compiler, *flags, "-o", object, "-c", source, env: CLEAN_ENV)
        end
      end

      # Runs `command` in `dir` under `env`, or refuses the build with its
      # output.
      #: (String dir, *String command, env: Hash[String, String?]) -> void
      def run(dir, *command, env:)
        log, status = Open3.capture2e(env, *command, chdir: dir)
        return if status.success?

        raise Refused, "#{File.basename(File.dirname(@extconf))}: `#{command.first(2).map { |word| File.basename(word) }.join(" ")}` " \
                       "failed while zr built the C extension:\n#{log.strip}"
      end
    end
  end
end
