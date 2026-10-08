# frozen_string_literal: true

require_relative "makefile"

module Zr
  module Ext
    # The ABI of the C extensions that zr runs: ruby 4.0's object layout
    # and C API. A precompiled gem keeps one bundle for each ruby minor
    # version, in a directory of that name (`lib/nokogiri/4.0/`).
    ABI = "4.0"

    # One C extension that a build runs: the bundle path that `require`
    # finds it at (where ruby would load it, under the gem's lib/), the
    # function that loads it, the objects that the link can put in the
    # binary with the libraries that they need, and a precompiled bundle
    # (`library`), when there is one. `mode` says which the build uses:
    #
    # - :static links the objects in;
    # - :embed relinks the bundle into the binary (`Obj::MachO::Relink`);
    # - :dynamic loads the bundle with dlopen where the require runs.
    #
    # The record's fields are typed in sig/zr/ext/source.rbs.
    # @rbs skip
    Source = Data.define(:bundle, :init, :objects, :libraries, :library, :mode)

    class Source
      # The extensions of an installed gem: each directory under its ext/
      # with mkmf's Makefile and every object that the Makefile lists, as
      # the host ruby's install left them; else each bundle that a
      # precompiled gem ships for this ABI.
      #: (String gem_dir) -> Array[Source]
      def self.installed(gem_dir)
        compiled = Dir[File.join(gem_dir, "ext", "**", "Makefile")].sort.filter_map do |path|
          makefile = Makefile.read(path)
          objects = makefile.objects
          next if objects.empty? || !objects.all? { |object| File.file?(object) }

          new(bundle: File.join(gem_dir, "lib", "#{makefile.feature}.bundle"), init: makefile.init, objects: objects,
              libraries: makefile.libraries, library: nil, mode: :static)
        end
        compiled.empty? ? precompiled(gem_dir) : compiled
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
    end
  end
end
