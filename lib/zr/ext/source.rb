# frozen_string_literal: true

require_relative "makefile"
require_relative "c_api"

module Zr
  module Ext
    # The ABI of the C extensions that zr runs: the object layout and the
    # C API of the pinned ruby's series (RUBY_API). A precompiled gem keeps
    # one bundle for each ruby minor version, in a directory of that name
    # (`lib/nokogiri/<RUBY_API>/`).
    ABI = RUBY_API

    # One C extension that a build runs: the bundle path that `require`
    # finds it at (where ruby would load it, under the gem's lib/), the
    # function that loads it, the objects that the link can put in the
    # binary with the libraries that they need, and a precompiled bundle
    # (`library`), when there is one. `mode` says which the build uses:
    #
    # - :static links the objects into a bundle, which then embeds
    #   (`Native::Build.ext_bundle`);
    # - :embed relinks the bundle into the binary (`Obj::MachO::Relink`);
    # - :dynamic loads the bundle with dlopen where the require runs.
    #
    # The record's fields are typed in sig/zr/ext/source.rbs.
    # @rbs skip
    Source = Data.define(:bundle, :init, :objects, :libraries, :library, :mode)

    class Source
      # The extensions of an installed gem: each directory under its ext/
      # with mkmf's Makefile and every object that the Makefile lists, as
      # the host ruby's install left them; else each bundle that the
      # install built in `extension_dir` (`built`); else each bundle that a
      # precompiled gem ships for this ABI.
      #: (String gem_dir, ?String? extension_dir) -> Array[Source]
      def self.installed(gem_dir, extension_dir = nil)
        compiled = Dir[File.join(gem_dir, "ext", "**", "Makefile")].sort.filter_map do |path|
          makefile = Makefile.read(path)
          objects = makefile.objects
          next if objects.empty? || !objects.all? { |object| File.file?(object) }

          new(bundle: File.join(gem_dir, "lib", "#{makefile.feature}.bundle"), init: makefile.init, objects: objects,
              libraries: makefile.libraries, library: nil, mode: :static)
        end
        return compiled unless compiled.empty?

        bundles = extension_dir ? built(gem_dir, extension_dir) : precompiled(gem_dir)
        bundles.empty? ? precompiled(gem_dir) : bundles
      end

      # The bundles that the host ruby's install of a gem built, in the
      # gem's extension directory (`Gem::Specification#extension_dir`):
      # `<extension_dir>/json/ext/parser.bundle` is what `require
      # "json/ext/parser"` loads, from the gem's lib/ for zr.
      #: (String gem_dir, String extension_dir) -> Array[Source]
      def self.built(gem_dir, extension_dir)
        Dir.glob("**/*.bundle", base: extension_dir).sort.reject { |name| name.include?(".dSYM/") }.map do |name|
          path = File.join(extension_dir, name)
          new(bundle: File.join(gem_dir, "lib", name), init: init_of(path), objects: [], libraries: [], library: path, mode: :embed)
        end
      end

      # The bundles of a precompiled gem for this ABI: `lib/x/4.0/x.bundle`
      # is the extension that `require "x/x"` loads.
      #: (String gem_dir) -> Array[Source]
      def self.precompiled(gem_dir)
        lib = File.join(gem_dir, "lib")
        Dir[File.join(lib, "**", ABI, "*.bundle")].sort.map do |path|
          feature = File.join(File.dirname(path, 2), File.basename(path))
          new(bundle: feature, init: init_of(path), objects: [], libraries: [], library: path, mode: :embed)
        end
      end

      # An extension given as a bundle's path and its objects
      # (`ZR_EXT_OBJECTS`), or as the bundle alone, which then embeds: its
      # Init function is named after the bundle.
      #: (String bundle, Array[String] objects) -> Source
      def self.given(bundle, objects)
        if objects.empty?
          return new(bundle: bundle, init: init_of(bundle), objects: [], libraries: [], library: bundle, mode: :embed)
        end

        new(bundle: bundle, init: init_of(bundle), objects: objects, libraries: [], library: nil, mode: :static)
      end

      # The Init function of the bundle at `path`: `Init_` and its name.
      #: (String path) -> String
      def self.init_of(path) = "Init_#{File.basename(path).sub(/\..*\z/, "")}"

      # The Mach-O files whose imports the C API must have: the objects, or
      # the bundle.
      #: () -> Array[String]
      def binaries = mode == :static ? objects : [library].compact

      # The same extension as the build `mode` (`ZR_EXT`) runs it: a bundle
      # loads with dlopen under `dynamic`; objects stay static.
      #: (String mode) -> Source
      def for_mode(mode) = library && mode == "dynamic" ? with(mode: :dynamic) : self

      # The C API's functions that require a feature (`rb_require("oj/bag")`).
      REQUIRERS = %w[rb_require rb_require_string rb_f_require].freeze
      # A string that reads as a feature name: words joined by slashes.
      FEATURE = %r{\A[a-z][a-z0-9_-]*(?:/[a-z0-9_-]+)*\z}

      # The features that the extension's C may require as it runs. The
      # names that C passes to rb_require are C strings (`__cstring`, `.rodata.str1.1`), so
      # they are each such string that reads as a feature name; the build
      # compiles in those that a load path has (`Loader#add`). An
      # extension that imports no require function requires nothing.
      #: () -> Array[String]
      def required_features
        return [] unless CApi.imports(*binaries).intersect?(REQUIRERS)

        binaries.flat_map { |path| Obj::Image.read(File.binread(path)).c_strings }.grep(FEATURE).uniq
      end

      # The C API's functions that hook trace events: a tracer's, a
      # profiler's or a debugger's. A debugger's frames give bindings,
      # which see every local only in a traced build (`Loader#traces?`).
      TRACERS = %w[rb_tracepoint_new rb_add_event_hook rb_add_event_hook2 rb_thread_add_event_hook rb_thread_add_event_hook2
                   rb_debug_inspector_open].freeze

      # Whether the extension's C hooks trace events, so the build must
      # fire them, as for a program that names TracePoint.
      #: () -> bool
      def traces? = CApi.imports(*binaries).intersect?(TRACERS)
    end
  end
end
