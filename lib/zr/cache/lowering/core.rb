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

        # Lowers the core over the kernel `unit`, as `Zr.core` does, taking each
        # file it can from an entry. Returns `[functions, data]`: IR for a file
        # that it lowered, `Obj::Code` for one that it took. It inlines the
        # whole unit (the kernel's functions too), so the object build must not.
        def lower(unit, symbols, sources)
          @unit = unit
          @symbols = symbols
          @sources = sources
          @base = Zr.clock("core cache: key") { base_key(Machine::Description.of(unit).to_text, Lower.boot_classes.inspect) }
          @kernel = unit.functions
          @kernel_names = @kernel.to_h { |f| [f.name, true] }
          kernel = IR::Passes::Inline.new(@kernel)
          Zr.clock("core cache: kernel inlined") { kernel.run }
          @kernel_leaf = @kernel.to_h { |f| [f.name, kernel.settled_leaf?(f.name) ? IR::Fingerprint.of(f, EMPTY) : nil] }
          @kernel_calls = @kernel.flat_map { |f| kernel.calls(f.name) }.uniq.reject { |sym| @kernel_names[sym] }

          pieces = Zr.clock("core cache: files") do
            Zr.core_files(@target).map { |path| core_file(path) }
          end
          @prelude = Zr.prelude(pieces.map(&:entry), unit)
          # The gem prelude is one more piece: its key has each file it loads.
          @gem_hir = Zr.clock("core cache: gem prelude built") { Zr.gem_prelude(@target) }
          pieces << gem_piece

          functions = finish(pieces, @kernel + [@prelude], "core cache")
          # The kernel inlines alone only while it calls nothing of the core.
          core_call = @kernel_calls.find { |sym| @piece_names[sym] }
          raise "the kernel calls #{core_call} of the core, so Lowering::Core cannot inline it alone" if core_call

          [functions << @prelude, @pieces.flat_map(&:data)]
        end

        # The symbols that the core's functions call, and the symbols of the
        # data that they read and that are not colocated (`Runtime#wants`).
        def calls_and_reads
          pairs = @pieces.map(&:wants)
          [pairs.flat_map(&:first).uniq, pairs.flat_map(&:last).uniq]
        end

        private

        def core_file(path)
          entry = Zr.core_entry(path)
          source = @sources.fetch(path) { File.read(path) }
          piece(path, entry, key_of(path, entry, source)) { lower_core(path, source) }
        end

        def lower_core(path, source) = Zr.lower_core_file(path, source, @unit, @symbols, @target)

        # The key text of the gem prelude: the path and the bytes of each file
        # that its program loads.
        def gem_source = @gem_hir.units.map { |u| "#{u.file}\0#{u.source}" }.join("\0") + File.read(Layout::GEM_PRELUDE)

        def gem_piece
          entry = Zr::GEM_PRELUDE_ENTRY
          piece(Layout::GEM_PRELUDE, entry, key_of(Layout::GEM_PRELUDE, entry, gem_source)) { lower_gem }
        end

        def lower_gem = Zr.lower_gem_prelude(@gem_hir, @unit, @symbols, @target)

        # A piece from an entry that failed its check, lowered now with the
        # site counter it had.
        def again(piece)
          sites = piece.record[:sites].first
          if piece.path == Layout::GEM_PRELUDE
            lowered(piece.path, piece.entry, piece.key, sites: sites) { lower_gem }
          else
            source = @sources.fetch(piece.path) { File.read(piece.path) }
            lowered(piece.path, piece.entry, piece.key, sites: sites) { lower_core(piece.path, source) }
          end
        end

        # The kernel's functions, data and raw functions, and the prelude.
        def fixed_names = @fixed_names ||= @kernel.map(&:name) + @unit.data.map(&:name) + @unit.raw << @prelude.name

        # A kernel function is itself: a leaf with its fingerprint, or not.
        def fixed_state(sym)
          return [:kernel, @kernel_leaf[sym]] if @kernel_names[sym]

          [:fixed, nil] if sym == @prelude.name
        end
      end
    end
  end
end
