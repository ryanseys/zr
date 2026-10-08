# frozen_string_literal: true

require_relative "../prism"
require "set"
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
      # @rbs @names: Set[String]

      # The names that are ruby's: what an extension takes from ruby, not
      # from libc.
      RUBY = /\A(?:rb_|ruby_|st_|onig)/
      DIR = File.join(Paths::RUNTIME, "kernel/capi")

      module_function

      # The names, read once from the kernel's source.
      #: () -> Set[String]
      def names
        @names ||= Dir[File.join(DIR, "*.rb")].each_with_object(Set.new) do |path, found|
          collect(Prism.parse_file(path).value, found)
        end.freeze
      end

      #: (String name) -> bool
      def ruby?(name) = RUBY.match?(name)

      # The ruby names in `imports` (C names) that the C API lacks, sorted.
      #: (Array[String] imports) -> Array[String]
      def missing(imports) = imports.select { |name| ruby?(name) && !names.include?(name) }.uniq.sort

      # The ruby names that the Mach-O object or image at `path` imports.
      #: (String path) -> Array[String]
      def imports(path)
        Obj::MachO::Image.read(File.binread(path)).undefined.map { |name| name.delete_prefix("_") }.select { |name| ruby?(name) }
      end

      # Refuses a build of an extension (`Ext::Source`) that imports a
      # name the C API lacks.
      #: (Array[Source] sources) -> void
      def check!(sources)
        sources.each do |source|
          lacking = missing(source.objects.flat_map { |path| imports(path) })
          next if lacking.empty?

          raise Refused, "#{File.basename(source.bundle)}: zr's C API has no #{lacking.join(", ")} yet " \
                         "(`zr-dev ext imports #{source.objects.join(" ")}` lists what it uses)"
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
