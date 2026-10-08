# frozen_string_literal: true

require_relative "../prism"
require_relative "../paths"
require_relative "../refused"
require_relative "../obj/macho/image"

module Zr
  module Ext
    # The C API that zr's kernel gives C extensions (kernel/capi/*.rb), by
    # C name: each function that an extension calls (`def rb_intern`) and
    # each word that it reads (`Machine.global(:rb_cObject)`). A build
    # checks an extension's imports against it, so a missing function
    # stops the build with its name, not the program later.
    module CApi
      # The names that are ruby's: what an extension takes from ruby, not
      # from libc.
      RUBY = /\A(?:rb_|ruby_|st_|onig)/
      DIR = File.join(Paths::RUNTIME, "kernel/capi")

      module_function

      # The names, read once for each build from the kernel's source.
      #: () -> Set[String]
      def names
        Session.current.memo(:capi_names) do
          Dir[File.join(DIR, "*.rb")].each_with_object(Set.new) { |path, found| collect(Prism.parse_file(path).value, found) }.freeze
        end
      end

      #: (String name) -> bool
      def ruby?(name) = RUBY.match?(name)

      # The ruby names in `imports` (C names) that the C API lacks, sorted.
      #: (Array[String] imports) -> Array[String]
      def missing(imports) = imports.select { |name| ruby?(name) && !names.include?(name) }.uniq.sort

      # The ruby names that the Mach-O objects or images at `paths` import
      # from outside them: a name that one of them defines (an extension's
      # own `rb_cCDict`, which its other objects use) is not an import.
      #: (*String paths) -> Array[String]
      def imports(*paths)
        images = paths.map { |path| Obj::MachO::Image.read(File.binread(path)) }
        own = images.flat_map(&:defined).to_set
        images.flat_map(&:undefined).uniq.reject { |name| own.include?(name) }.map { |name| name.delete_prefix("_") }.select { |name| ruby?(name) }
      end

      # Refuses a build of an extension (`Ext::Source`) that imports a
      # name the C API lacks.
      #: (Array[Source] sources) -> void
      def check!(sources)
        sources.each do |source|
          lacking = missing(imports(*source.binaries))
          next if lacking.empty?

          raise Refused, "#{File.basename(source.bundle)}: zr's C API has no #{lacking.join(", ")} yet " \
                         "(`zr-dev ext imports #{source.binaries.join(" ")}` lists what it uses)"
        end
      end

      #: (Prism::node node, Set[String] found) -> void
      def collect(node, found)
        case node
        when Prism::DefNode
          found << node.name.to_s if ruby?(node.name.to_s)
        when Prism::CallNode
          word = node.arguments&.arguments&.first if machine_global?(node)
          found << word.unescaped if word.is_a?(Prism::SymbolNode)
        end
        node.compact_child_nodes.each { |child| collect(child, found) }
      end

      # Whether `call` is `Machine.global(:name)`.
      #: (Prism::CallNode call) -> bool
      def machine_global?(call)
        receiver = call.receiver
        call.name == :global && receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :Machine
      end
    end
  end
end
