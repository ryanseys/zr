# frozen_string_literal: true

require_relative "../lowering"
require_relative "../unit"

module Zr
  module Cache
    class Lowering
      # The files of eval support as the pieces of a `Lowering`. Eval
      # support is one lowering of about 400 files (the compiler, prism, the
      # libraries that an eval can require). After an edit to one of them, a
      # build lowered them all again (17 s) and took every fingerprint (13 s),
      # though the code of most came from the code cache.
      #
      # Each unit of a lowering uses its own names and counters
      # (`Lower#open_unit`), so `Lower#lower_unit` lowers it alone with the code
      # it has in the whole lowering. A unit calls another only at its entry,
      # when it requires it. The fixed part is the program's own toplevel.
      # A unit's key has its file, its bytes, its flags, and the path and
      # entry of each unit that it requires. A unit that activates a
      # refinement has the number of its activation in its HIR, which depends
      # on the units before it; its key also has each such number.
      class EvalSupport < Lowering
        # The cache for eval support of `target`, or nil: only a native object
        # has a code cache to take the code from.
        def self.for(target, kind)
          code = Native::CodeCache.for("eval", target)
          code && new("eval-#{kind}", target, code)
        end

        # Lowers `program` (eval support's) with `lower`, taking each unit it
        # can from an entry. Returns `[functions, data]`: the toplevel's IR,
        # inlined, then the machine code of each unit; so the object build
        # must not inline again.
        def lower(lower, description)
          @lower = lower
          @program = lower.program
          @description = description
          # The code has the kernel's ids.
          @base = base_key(@program.file, *lower.fixed.keys)
          entry_functions, entry_data = lower.lower_entry
          pieces = @program.units.each_index.map do |i|
            u = @program.units[i]
            entry = lower.unit_entry(i)
            Piece.new(u.file, entry, unit_key(u, entry), u.source.to_s.bytesize + 1, -> { lower.lower_unit(i) })
          end
          names = entry_functions.map(&:name) + entry_data.map(&:name) + pieces.map(&:entry)
          functions, data = build(pieces, entry_functions, names.to_set, "eval cache")
          [entry_functions + functions, entry_data + data]
        end

        private

        def unit_key(unit, entry)
          return nil if unit.source.nil?

          usings = unit.activates ? usings(unit.body) : []
          key_of(unit.file, entry, *Unit.parts(unit) { |reached| @lower.unit_entry(reached) }, "usings", *usings)
        end

        # The activation numbers in `body`: each `using`'s entry, and the
        # refinement scope of each call under one.
        def usings(body, out = [])
          case body
          when Hir::Using then out << body.id
          when Hir::Send, Hir::Super, Hir::AttrOpAssign, Hir::IndexOpAssign then out << body.using.inspect
          end
          body.each { |child| usings(child, out) if child.is_a?(Hir::Node) || child.is_a?(Array) } if body.is_a?(Hir::Node) || body.is_a?(Array)
          out
        end
      end
    end
  end
end
