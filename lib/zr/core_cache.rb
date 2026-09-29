# frozen_string_literal: true

require_relative "lowering_cache"

module Zr
  # The core library's files, and the gem prelude, as the pieces of a
  # `LoweringCache`. The fixed part is the kernel, which the build lowers
  # each time, and the prelude that runs each core file.
  #
  # The kernel calls nothing of the core, so it inlines alone first: the
  # state of each kernel function (a leaf, and the fingerprint of its IR)
  # is then known before any check of an entry.
  class CoreCache < LoweringCache
    # The core cache for `target`, or nil: only the aarch64 runtime object
    # has a code cache to take the code from.
    def self.for(target)
      code = Native::CodeCache.for("runtime", target)
      code && new("core", target, code)
    end

    # Lowers the core over the kernel `unit`, as `Zr.core` does, taking each
    # file it can from an entry. Returns `[functions, data]`: IR for a file
    # that it lowered, `Obj::Function` for one that it took. It inlines the
    # whole unit (the kernel's functions too), so the object build must not.
    def lower(unit, symbols, sources)
      @unit = unit
      @symbols = symbols
      @sources = sources
      @base = Zr.clock("core cache: key") do
        Digest::SHA256.hexdigest([VERSION, @target.triple, Paths.root.to_s, Zr.compiler_digest(@target),
                                  Machine::Description.of(unit).to_text, Lower.boot_classes.inspect].join("\0"))
      end
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

      pieces = Zr.clock("core cache: checked") { settle(pieces) }
      @pieces = pieces
      report("core cache", pieces)
      Zr.clock("core cache: inlined") { inline(pieces, @kernel + [@prelude]) }
      # The kernel inlines alone only while it calls nothing of the core.
      core_call = @kernel_calls.find { |sym| @piece_names[sym] }
      raise "the kernel calls #{core_call} of the core, so CoreCache cannot inline it alone" if core_call

      functions = Zr.clock("core cache: code read") { pieces.flat_map { |piece| piece.is_a?(Kept) ? kept_code(piece) : piece.functions } }
      [functions << @prelude, pieces.flat_map { |piece| data_of(piece) }]
    end

    # The symbols that the core's functions call, and the symbols of the
    # data that they read and that are not colocated (`Runtime#wants`).
    def calls_and_reads
      pairs = @pieces.map { |piece| piece.is_a?(Kept) ? piece.record[:wants] : piece.wants }
      [pairs.flat_map(&:first).uniq, pairs.flat_map(&:last).uniq]
    end

    private

    def core_file(path)
      entry = "zr_core_#{File.basename(path, ".rb")}"
      source = @sources.fetch(path) { File.read(path) }
      piece(path, entry, key_of(path, entry, source)) { lower_core(path, entry, source) }
    end

    def lower_core(path, entry, source)
      Lower.new(Hir.build(source, path, eval_support: false, target: @target), @unit, @symbols, entry: entry, internal: true,
                                                                                  target: @target).run
    end

    # The key text of the gem prelude: the path and the bytes of each file
    # that its program loads.
    def gem_source = @gem_hir.units.map { |u| "#{u.file}\0#{u.source}" }.join("\0") + File.read(Zr::GEM_PRELUDE)

    def gem_piece
      entry = "zr_gem_prelude"
      piece(Zr::GEM_PRELUDE, entry, key_of(Zr::GEM_PRELUDE, entry, gem_source)) { lower_gem(entry) }
    end

    def lower_gem(entry) = Lower.new(@gem_hir, @unit, @symbols, entry: entry, kind: :top, target: @target).run

    # A piece from an entry that failed its check, lowered now with the
    # site counter it had.
    def again(piece)
      sites = piece.record[:sites].first
      if piece.path == Zr::GEM_PRELUDE
        lowered(piece.path, piece.entry, piece.key, sites: sites) { lower_gem(piece.entry) }
      else
        source = @sources.fetch(piece.path) { File.read(piece.path) }
        lowered(piece.path, piece.entry, piece.key, sites: sites) { lower_core(piece.path, piece.entry, source) }
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
