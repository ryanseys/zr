# frozen_string_literal: true

require_relative "../lowering"

module Zr
  module Cache
    class Lowering
      # The core library's files, and the gem prelude, as the pieces of a
      # `Lowering`. The fixed part is the kernel, which the build lowers
      # each time, and the prelude that runs each core file.
      #
      # The kernel calls nothing of the core, so it inlines alone first: the
      # state of each kernel function (a leaf, and the fingerprint of its IR)
      # is then known before any check of an entry.
      class Core < Lowering
        # The core cache for `target`, or nil: only the aarch64 runtime object
        # has a code cache to take the code from.
        def self.for(target)
          code = Native::CodeCache.for("runtime", target)
          code && new("core", target, code)
        end

        # Lowers the core over the kernel `unit`, as `Zr.core` does, with the
        # kernel's ids `ids`, taking each file it can from an entry. Returns
        # `[functions, data]`: machine code (`Obj::Code`) for each core
        # function, then the prelude's IR, and the data of each piece. It
        # inlines the kernel, so the object build must not inline again.
        def lower(unit, ids, sources)
          @unit = unit
          @ids = ids
          @sources = sources
          @base = Timing.phase("core cache: key") do
            base_key(Machine::Description.of(unit).to_text, Lower.boot_classes.inspect, *ids.keys)
          end
          paths = RuntimeSources.for(@target).core_files
          @prelude = Zr.prelude(paths.map { |path| Zr.core_entry(path) }, unit)
          pieces = paths.map { |path| core_file(path) }
          # The gem prelude is one more piece: its key has each file it loads.
          @gem_hir = Timing.phase("core cache: gem prelude built") { Zr.gem_prelude(@target) }
          pieces << gem_piece
          kernel = unit.functions
          names = kernel.map(&:name) + unit.data.map(&:name) + unit.raw + [@prelude.name] + pieces.map(&:entry)
          functions, data = build(pieces, kernel, names.to_set, "core cache")
          # The kernel inlines alone only while it calls nothing of the core
          # but an entry (boot runs the gem prelude's), which is a file's
          # toplevel and never a leaf.
          entries = pieces.to_set(&:entry)
          core_call = kernel.flat_map { |f| f.callees.map(&:symbol) }.find { |sym| known.key?(sym) && !entries.include?(sym) }
          raise "the kernel calls #{core_call} of the core, so Lowering::Core cannot inline it alone" if core_call

          [functions << @prelude, data]
        end

        private

        def core_file(path)
          entry = Zr.core_entry(path)
          source = @sources.fetch(path) { File.read(path) }
          Piece.new(path, entry, key_of(path, entry, source), source.bytesize,
                    -> { Zr.lower_core_file(path, source, @unit, @ids, @target) })
        end

        # The key text of the gem prelude: the path and the bytes of each file
        # that its program loads.
        def gem_source = @gem_hir.units.map { |u| "#{u.file}\0#{u.source}" }.join("\0") + File.read(Layout::GEM_PRELUDE)

        def gem_piece
          entry = Zr::GEM_PRELUDE_ENTRY
          source = gem_source
          Piece.new(Layout::GEM_PRELUDE, entry, key_of(Layout::GEM_PRELUDE, entry, source), source.bytesize,
                    -> { Zr.lower_gem_prelude(@gem_hir, @unit, @ids, @target) })
        end
      end
    end
  end
end
