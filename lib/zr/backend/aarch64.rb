# frozen_string_literal: true

require_relative "aarch64/codegen"
require_relative "aarch64/stub"
require_relative "../obj/model"

module Zr
  module Backend
    # The aarch64 backend. `Codegen` writes each function's machine code
    # with our own `Assembler`. `Obj::Relocs::Aarch64` patches the
    # relocations that it records. `Stub` contains the functions that the kernel subset cannot express.
    module Aarch64
      module_function

      # Returns one `Obj::Unit` from the compiled `functions`, the `raw`
      # functions without change, and `data`. `export` makes every data object
      # visible to the linker, for an object that another object refers to.
      # A given block assembles the functions, in order, from the functions and
      # the unit's defined names (`Native::Build.unit` assembles in workers).
      # @rbs functions: Array[IR::Function]
      # @rbs data: Array[Obj::Datum]
      # @rbs raw: Array[Obj::Code]
      # @rbs export: bool
      # @rbs allocate: bool
      # @rbs &: ? (Array[IR::Function], Set[String]) -> Array[Obj::Code]
      # @rbs return: Obj::Unit
      def unit(functions, data, raw: [], export: false, allocate: true)
        out = Obj::Unit.new
        defined = (functions.map(&:name) + data.map(&:name) + raw.map(&:name)).to_set
        out.functions.concat(block_given? ? yield(functions, defined) : functions.map { |f| assemble(f, defined, allocate: allocate) })
        raw.each { |r| out.functions << r }
        data.each { |d| out.data << (export ? exported(d) : d) }
        out
      end

      # Returns one function's machine code. `defined` returns true when a
      # symbol is defined in this unit.
      #: (IR::Function function, Set[String] | Spelled defined, ?allocate: bool) -> Obj::Code
      def assemble(function, defined, allocate: true)
        imported = function.callees.find(&:from)
        raise Refused, "#{imported.symbol} is a wasm import from #{imported.from}, which no native link has" if imported

        Codegen.new(function, defined: defined, allocate: allocate).compile
      end

      # The names that a lowering gives to its output: its entry, and every
      # name that it makes from the entry. A unit that is assembled during
      # lowering uses these to know its own symbols before all of them exist.
      class Spelled
        attr_reader :entry #: String

        #: (String entry) -> void
        def initialize(entry)
          @entry = entry
          freeze
        end

        #: (String name) -> bool
        def include?(name) = name == entry || name.start_with?("#{entry}_")

        #: () -> self
        def to_set = self
      end

      #: (Obj::Datum d) -> Obj::Datum
      def exported(d)
        d.linkage == :export ? d : Obj::Datum.new(d.name, d.section, d.bytes, relocs: d.relocs, align: d.align, linkage: :export)
      end
    end
  end
end
