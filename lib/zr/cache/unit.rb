# frozen_string_literal: true

require_relative "../paths"
require_relative "store"

module Zr
  module Cache
    # A file's assembled machine code, kept between builds in the store
    # (lib/zr/cache/store.rb) as kind `unit`.
    #
    # A unit's code does not depend on the compile order. Its names come
    # from its source file, and its symbol ids and literal slots are words
    # that the link fills (`Zr.number_symbols`). So the same file gives the
    # same bytes in any program, and a build can read them back instead of
    # making them again. This saves most of a large build's time (about
    # four fifths).
    #
    # **The cache fails closed.** The key contains every input of a unit's
    # bytes. zr does not cache a program with numbers that the key cannot
    # contain: a program that measures coverage (a def site's entry comes
    # from a counter that the whole program shares), and a file that
    # activates a refinement (a `using` contains the entry it took). Both
    # are rare, and both would give wrong code without an error.
    #
    # The names of the other units are also an input. A `require` or an
    # `autoload` refers to the entry of the unit it runs
    # (`Zr::Lower#unit_entry`), and to that unit's path as the program
    # shows it. The entry is made from the file path when the path is
    # absolute, else from the unit's position in the program. So the key
    # contains the path and the entry of each unit that this unit's
    # requires and autoloads reach, and no other entry: a `require` added
    # to one file lowers only that file again, not every unit.
    class Unit
      # The format of the cache entries. Increase it to make every entry
      # from an older zr a miss.
      VERSION = 4

      # The cache for `program`, or nil if no key can describe this
      # program. `entries` are the program's unit entries, in order.
      def self.for(program, runtime:, entries:)
        return nil if program.coverable&.any?

        new(runtime: runtime, traced: program.traced ? 1 : 0, entries: entries)
      end

      def initialize(runtime:, traced:, entries:)
        # `runtime` is the runtime's ABI digest (`RuntimeSources#abi_digest`):
        # the compiler, the kernel's description and the kernel's names. A
        # unit's code has only the kernel's ids and calls the core only by
        # name, so no core edit changes it.
        @stamp = "#{VERSION}\0#{runtime}\0#{traced}"
        @entries = entries
      end

      # `[functions, data]` an earlier build left for `unit`, or nil.
      def take(unit, prefix)
        key = key(unit, prefix) or return nil

        Store.read(:unit, key)
      end

      # Stores the code that this build made for `unit`, for the next build.
      # Stores nothing if a source changed during the build (`Zr.settled!`).
      def keep(unit, prefix, functions, data)
        key = key(unit, prefix) or return nil

        Store.write(:unit, key, [functions, data])
      rescue SystemCallError
        nil
      end

      # The inputs of a unit's bytes after its file: its flags, its source,
      # and what `reached` gives. The block gives the entry of a unit.
      def self.parts(unit, &) = [unit.internal ? 1 : 0, unit.hidden ? 1 : 0, unit.source.b, *reached(unit.body, &)]

      # The path and the entry of each unit that a require or an autoload
      # in `body` runs, in the order of the tree. The block gives the entry
      # of a unit; a require that runs no unit adds "-". Lowering::EvalSupport keys its
      # pieces the same way.
      def self.reached(body, out = [], &)
        case body
        when Hir::Require, Hir::Autoload
          out << Paths.shown(body.path.to_s) << (body.unit.nil? ? "-" : yield(body.unit))
          body.each { |child| reached(child, out, &) if child.is_a?(Hir::Node) || child.is_a?(Array) }
        when Hir::Node, Array
          # No array per node: a walk of a large program visits millions.
          body.each { |child| reached(child, out, &) if child.is_a?(Hir::Node) || child.is_a?(Array) }
        end
        out
      end

      private

      # A digest of every input of the unit's bytes, or nil if one input is
      # a number that this key cannot contain.
      def key(unit, prefix)
        return nil if unit.source.nil? || unit.activates

        Store.key(@stamp, prefix, unit.file, *Unit.parts(unit) { |reached| entry(reached) })
      end

      # A unit's entry: a String names it already (a unit of eval support).
      def entry(unit)
        unit.is_a?(String) ? unit : @entries.fetch(unit)
      end
    end
  end
end
