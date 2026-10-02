# frozen_string_literal: true

require_relative "../config"
require_relative "../paths"
require_relative "../runtime_sources"
require_relative "../timing"
require_relative "store"
require_relative "../ir/fingerprint"
require_relative "../ir/passes"
require_relative "../native/code_cache"
require_relative "../native/parallel"
require_relative "../backend/aarch64"

module Zr
  module Cache
    # The pieces of a large unit (the core files and the gem prelude, the
    # files of eval support), each lowered and assembled on its own, in
    # forked workers, and kept between builds.
    #
    # A piece has only the kernel's ids in its code, and it calls no other
    # piece except through a piece's entry (a core file's toplevel, a
    # unit that a `require` runs). So a piece inlines only its own
    # functions and the fixed part's (the kernel), and its code depends on
    # nothing else of the unit. A worker lowers a piece, inlines it,
    # fingerprints each function and assembles each one that the code cache
    # (`Native::CodeCache`) does not have. It returns machine code and
    # data, never IR: loading the core's IR took longer than lowering it.
    #
    # An entry keeps what the rest of the build reads from a piece: the
    # fingerprint of each function, its data (unnumbered: its pool words
    # name their symbols), the symbols it wants, the kernel rows it read,
    # what each fixed symbol that it called was (a leaf with the fingerprint
    # of its IR, or not), and which of the symbols it names the unit
    # defines. A build takes an entry while all of these hold and the code
    # cache has its code; else a worker makes the piece again.
    class Lowering
      VERSION = 4

      # A piece to build: its path, its entry function, its key (nil when no
      # key can describe it; then it is always made), its weight for the
      # workers, and `make`, which returns `[functions, data]` of IR.
      # @rbs skip -- typed in sig/zr/cache/lowering.rbs
      Piece = Struct.new(:path, :entry, :key, :weight, :make)

      attr_reader :code

      def initialize(kind, target, code)
        @kind = kind
        @target = target
        @code = code
        @backend = Native::CodeCache.backend_digest
      end

      # The fingerprint and the code of each function of the pieces, by
      # name, for `Native::Build.cached`.
      def known = @known ||= {}

      # The symbols that the pieces call, and the symbols of the data that
      # they read and that are not colocated (`Runtime#wants`).
      def calls_and_reads = [@wants.flat_map(&:first).uniq, @wants.flat_map(&:last).uniq]

      private

      # Builds `pieces` over the fixed part: `fixed_ir` (already inlined),
      # whose leaves a piece inlines, and `fixed_names`, every name outside
      # the pieces that the unit defines (the fixed part's functions and
      # data, and the pieces' entries). Returns `[functions, data]`: the
      # machine code (`Obj::Code`) and the data of every piece, in order.
      # `label` names the steps for ZR_TIMING.
      def build(pieces, fixed_ir, fixed_names, label)
        @fixed = fixed_ir.to_h { |f| [f.name, f] }
        @fixed_names = fixed_names
        inliner = IR::Passes::Inline.new(fixed_ir)
        inliner.run
        @leaf = fixed_ir.to_h { |f| [f.name, inliner.settled_leaf?(f.name) ? IR::Fingerprint.of(f, Set.new) : nil] }
        records = Timing.phase("#{label}: checked") { pieces.map { |piece| current(piece) } }
        missing = pieces.each_index.reject { |i| records[i] }
        report(label, pieces.size - missing.size, pieces.size)
        made = Timing.phase("#{label}: made") do
          Native::Parallel.map(missing.map { |i| pieces[i] }, jobs: Config.current.jobs, weight: :weight.to_proc) do |piece|
            made(piece)
          end
        end
        missing.zip(made) { |i, (record, blobs)| records[i] = [record, blobs] }
        Timing.phase("#{label}: kept") { keep(pieces, records) }
        Timing.phase("#{label}: code read") { results(records) }
      end

      # `[record, nil]` for a piece whose entry holds, else nil. The code
      # comes from the code cache.
      def current(piece)
        record = piece.key && Store.read(:lowering, piece.key)
        reason = if piece.key.nil? then "no key"
                 elsif record.nil? then "no entry"
                 else stale(record)
                 end
        return [record, nil] unless reason

        note(piece.path, reason)
        nil
      end

      # Why an entry no longer holds, or nil when it holds.
      def stale(record)
        return "kernel rows" unless reads_hold?(record)

        call = record[:calls].find { |sym, was| state(sym) != was }
        return "#{call.first} was #{call.last.inspect}, now #{state(call.first).inspect}" if call

        own = record[:functions].to_h { |name, _| [name, true] }
        record[:data_names].each { |name| own[name] = true }
        bit = record[:bits].find { |sym, was| (own.key?(sym) || @fixed_names.include?(sym)) != was }
        return "#{bit.first} is #{bit.last ? "no longer" : "now"} defined" if bit

        missing = record[:functions].find { |_, key| !code.has?(key) }
        "no code for #{missing.first}" if missing
      end

      # What a fixed symbol is now: the fingerprint of a leaf, :call for a
      # function that is no leaf, or :absent.
      def state(sym)
        return :absent unless @fixed.key?(sym)

        @leaf[sym] || :call
      end

      # In a worker: lowers `piece`, inlines it over the fixed part, and
      # returns its entry and the Marshal of each function's code.
      def made(piece)
        functions = data = nil
        reads = reading { functions, data = piece.make.call }
        own = (functions.map(&:name) + data.map(&:name)).to_set
        inliner = IR::Passes::Inline.new(functions, sources: @fixed.values)
        inliner.run
        called = functions.flat_map { |f| inliner.calls(f.name) }.uniq.select { |sym| @fixed.key?(sym) }
        named = (functions.flat_map { |f| f.callees.map(&:symbol) + f.globals.map(&:symbol) }).uniq
        defined = own | @fixed_names
        # A code cache is only for this backend (`Native::CodeCache.for`).
        emitter = Backend::Aarch64
        blobs = {}
        prints = functions.map do |f|
          key = IR::Fingerprint.of(f, defined)
          blobs[key] = code.blob(key) || begin
            IR::Passes.prepare(f)
            Marshal.dump(emitter.assemble(f, defined))
          end
          [f.name, key]
        end
        record = { functions: prints, data: Marshal.dump(data), data_names: data.map(&:name), reads: reads,
                   wants: wants_of(functions), calls: called.to_h { |sym| [sym, state(sym)] },
                   bits: named.to_h { |sym| [sym, defined.include?(sym)] } }
        [record, blobs]
      end

      # Writes an entry for each piece that a worker made, and the root that
      # keeps this build's entries.
      def keep(pieces, records)
        return if SourceGuard.changed_file

        pieces.zip(records) do |piece, (record, blobs)|
          Store.write(:lowering, piece.key, record) if blobs && piece.key
        end
        Store.root("#{@target.triple}-#{@kind}", pieces.filter_map { |piece| piece.key && Store.path(:lowering, piece.key) })
      rescue SystemCallError
        nil
      end

      # The code and the data of each piece, in order. The code of a piece
      # that a worker made came with it; the rest comes from the code cache.
      def results(records)
        @wants = records.map { |record, _| record[:wants] }
        functions = []
        data = []
        records.each do |record, blobs|
          record[:functions].each do |name, key|
            blob = blobs ? blobs.fetch(key) : code.blob(key)
            known[name] = [key, blob]
            functions << Marshal.load(blob)
          end
          data.concat(Marshal.load(record[:data]))
        end
        [functions, data]
      end

      # The kernel description that the pieces read, or nil when the key
      # holds all of it. With one, an entry keeps the rows that its piece
      # read (`Machine::Description#record`), and holds while each is the
      # same: a kernel edit that the piece does not read keeps it.
      attr_reader :description

      def reading(&)
        return description.record(&) if description

        yield
        {}
      end

      def reads_hold?(record)
        return true unless description

        reads = record[:reads]
        reads.is_a?(Hash) && description.rows(reads) == reads
      end

      # The symbols that `functions` call, and those of the data that they
      # read and that are not colocated, as `Runtime#write_cached` counts them.
      def wants_of(functions)
        [functions.flat_map { |f| f.callees.map(&:symbol) }.uniq, functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq]
      end

      # An entry's key: the cache's kind (core, eval-jit, eval-walk), the
      # backend, the base of the unit and the piece's own parts.
      #: (*_ToS parts) -> String
      def key_of(*parts) = Store.key(@kind, @backend, @base, *parts)

      # The base of every key of this lowering: the format, the target, the
      # path root and the compiler, then `parts` of the unit.
      #: (*_ToS parts) -> String
      def base_key(*parts) = Store.key(VERSION, @target.triple, Paths.root.to_s, RuntimeSources.for(@target).compiler_digest, *parts)

      # Notes the first reason that a piece is made, for ZR_TIMING.
      def note(path, reason)
        @why ||= "#{File.basename(path.to_s)}: #{reason}"
        (@whys ||= Hash.new(0))[reason.sub(/\A\S+ (is|was) /, "a callee \\1 ")[0, 60]] += 1
      end

      def report(label, kept, all)
        return unless Config.current.timing?

        warn format("zr: %s: %d of %d pieces from entries%s", label, kept, all, @why ? " (first made: #{@why})" : "")
        @whys&.sort_by { |_, n| -n }&.first(5)&.each { |reason, n| warn format("zr: %s:   %4d made: %s", label, n, reason) }
      end
    end
  end
end
