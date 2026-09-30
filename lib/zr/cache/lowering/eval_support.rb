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
      # it has in the whole lowering. The fixed part is the program's own
      # toplevel. A unit's key has its file, its bytes, its flags, and the path
      # and entry of each unit that it requires. A unit that activates a
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
        # can from an entry. Returns `[functions, data]`, with `Obj::Code`
        # for each unit that it took, and inlined, so the object build must not
        # inline again.
        def lower(lower, symbols, description)
          @lower = lower
          @symbols = symbols
          @program = lower.program
          @description = description
          @base = Store.key(VERSION, @target.triple, Paths.root.to_s, Zr.compiler_digest(@target), @program.file)
          @entry_functions, @entry_data = lower.lower_entry
          pieces = Zr.clock("eval cache: units") do
            @program.units.each_index.map do |i|
              u = @program.units[i]
              entry = lower.unit_entry(i)
              piece(u.file, entry, unit_key(u, entry)) { lower.lower_unit(i) }
            end
          end
          @index = pieces.each_with_index.to_h { |piece, i| [piece.entry, i] }
          pieces = Zr.clock("eval cache: checked") { settle(pieces) }
          @pieces = pieces
          report("eval cache", pieces)
          Zr.clock("eval cache: inlined") { inline(pieces, @entry_functions) }
          functions = Zr.clock("eval cache: code read") { pieces.flat_map { |piece| piece.is_a?(Kept) ? kept_code(piece) : piece.functions } }
          [@entry_functions + functions, @entry_data + pieces.flat_map { |piece| data_of(piece) }]
        end

        private

        def unit_key(unit, entry)
          return nil if unit.source.nil?

          usings = unit.activates ? usings(unit.body) : []
          key_of(unit.file, entry, unit.internal ? 1 : 0, unit.hidden ? 1 : 0, unit.source, *Unit.reached(unit.body) { |reached|
     @lower.unit_entry(reached) }, "usings", *usings)
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

        def again(piece)
          i = @index.fetch(piece.entry)
          lowered(piece.path, piece.entry, piece.key, sites: piece.record[:sites].first) { @lower.lower_unit(i) }
        end

        def fixed_names = @fixed_names ||= @entry_functions.map(&:name) + @entry_data.map(&:name)

        def fixed_state(sym)
          @fixed_set ||= @entry_functions.to_h { |f| [f.name, true] }
          [:fixed, nil] if @fixed_set[sym]
        end
      end
    end
  end
end
