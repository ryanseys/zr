# frozen_string_literal: true

require_relative "makefile"

module Zr
  module Ext
    # One C extension that a build links: the bundle path that `require`
    # finds it at (where ruby would load it, under the gem's lib/), the
    # function that loads it, its objects and the libraries that they
    # need.
    #
    # The record's fields are typed in sig/zr/ext/source.rbs.
    # @rbs skip
    Source = Data.define(:bundle, :init, :objects, :libraries)

    class Source
      # The extensions of an installed gem whose objects the host ruby's
      # install left in place: each directory under its ext/ with mkmf's
      # Makefile and every object that the Makefile lists.
      #: (String gem_dir) -> Array[Source]
      def self.installed(gem_dir)
        Dir[File.join(gem_dir, "ext", "**", "Makefile")].sort.filter_map do |path|
          makefile = Makefile.read(path)
          objects = makefile.objects
          next if objects.empty? || !objects.all? { |object| File.file?(object) }

          new(bundle: File.join(gem_dir, "lib", "#{makefile.feature}.bundle"), init: makefile.init, objects: objects,
              libraries: makefile.libraries)
        end
      end

      # An extension given as a bundle's path and its objects
      # (`ZR_EXT_OBJECTS`): its Init function is named after the bundle.
      #: (String bundle, Array[String] objects) -> Source
      def self.given(bundle, objects)
        new(bundle: bundle, init: "Init_#{File.basename(bundle).sub(/\..*\z/, "")}", objects: objects, libraries: [])
      end
    end
  end
end
