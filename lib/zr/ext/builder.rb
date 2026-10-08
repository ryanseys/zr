# frozen_string_literal: true

require "digest/sha2"
require "open3"
require "rbconfig"
require_relative "makefile"
require_relative "source"
require_relative "../refused"
require_relative "../cache/store"

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
    # extconf.rb is the gem's code, so only a user's build runs it, never
    # a gem sweep.
    class Builder
      # @rbs @extconf: String
      # @rbs @args: Array[String]
      # @rbs @ruby: String

      # What the child that runs extconf.rb leaves out of zr's
      # environment: Bundler would hide the gems that an extconf requires.
      CLEAN_ENV = %w[BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB]
                  .to_h { |name| [name, nil] }.freeze #: Hash[String, nil]

      # `extconf` is the extension's extconf.rb, and `args` the words it
      # takes (`--use-system-libraries`). `ruby` runs it: zr's host ruby,
      # whose headers the extension compiles against.
      #: (String extconf, ?args: Array[String], ?ruby: String) -> void
      def initialize(extconf, args: [], ruby: RbConfig.ruby)
        @extconf = File.expand_path(extconf)
        @args = args
        @ruby = ruby
      end

      # The extension, built once for its sources, its arguments and this
      # ruby. `gem_dir` is the gem's directory: the bundle that a require
      # finds is under its lib/.
      #: (String gem_dir) -> Source
      def source(gem_dir)
        makefile = Makefile.read(File.join(build, "Makefile"))
        Source.new(bundle: File.join(gem_dir, "lib", "#{makefile.feature}.bundle"), init: makefile.init,
                   objects: makefile.objects, libraries: makefile.libraries, library: nil, mode: :static)
      end

      # The directory of the built extension: its Makefile and objects.
      #: () -> String
      def build
        key = Cache::Store.key("ext", ABI, @ruby, RbConfig::CONFIG["ruby_version"], *@args, *inputs)
        # Two builds of one extension: one runs extconf, the other waits.
        Cache::Store.once(:ext, key) do
          Cache::Store.write(:ext, key) do |dir|
            run(dir, @ruby, @extconf, *@args)
            makefile = Makefile.read(File.join(dir, "Makefile"))
            makefile.standard? && makefile.sources.all? { |c, _| File.file?(c) } ? compile(dir, makefile) : run(dir, "make")
          end
        end
      end

      private

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
          run(dir, *compiler, *flags, "-o", object, "-c", source)
        end
      end

      # Runs `command` in `dir`, or refuses the build with its output.
      #: (String dir, *String command) -> void
      def run(dir, *command)
        log, status = Open3.capture2e(CLEAN_ENV, *command, chdir: dir)
        return if status.success?

        raise Refused, "#{File.basename(File.dirname(@extconf))}: `#{command.first(2).map { |word| File.basename(word) }.join(" ")}` " \
                       "failed while zr built the C extension:\n#{log.strip}"
      end
    end
  end
end
