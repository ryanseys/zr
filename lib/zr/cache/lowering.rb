# frozen_string_literal: true

require_relative "../config"
require_relative "../paths"
require_relative "../runtime_sources"
require_relative "store"
require_relative "../ir/fingerprint"
require_relative "../ir/passes"
require_relative "../native/code_cache"

module Zr
  module Cache
    # The pieces of a large unit that a build does not lower again: a piece
    # (a core file, a file of eval support) whose inputs are the same as at
    # an earlier build gets that build's machine code (`Native::CodeCache`)
    # and data in place of its IR.
    #
    # Lowering the core took 7 s of each runtime build, and loading its IR
    # from a cache took longer (15 s of Marshal), so a piece is either
    # lowered or not needed at all. An entry keeps what the rest of the build
    # reads from a piece's lowering: the fingerprint of each function, its
    # data, the names it asked the symbol table for with their ids, its sites,
    # the symbols it wants, and the IR of each of its leaves, which other
    # functions inline.
    #
    # A function's code also depends on the rest of the unit: on the leaves
    # that it inlines, and on which of its callees the unit defines. An entry
    # records, for each colocated symbol that a function calls, what that
    # symbol was: a function of the fixed part (the kernel), with the
    # fingerprint of its IR when it is a leaf; a function of a piece, with
    # the same; or no function. A build checks each entry before it inlines.
    # A callee in a piece that this build lowers can have changed, unless it
    # was no leaf and is still too large to become one (inlining only adds
    # instructions). Then the build lowers each piece that fails, with the
    # site counter that the piece had, and inlines once over the whole unit.
    # So the code is the same as a build that lowers every piece, which
    # `core_cache_test.rb` checks byte for byte.
    class Lowering
      VERSION = 2

      # A piece that this build lowered: its IR and data, and what its
      # entry keeps (`names` are the symbol names it asked for).
      Lowered = Struct.new(:path, :entry, :key, :functions, :data, :names, :sites, :wants, :small, :reads) do
        def kept? = false
        def function_names = functions.map(&:name)
        # The IR that the inlining pass works on.
        def ir = functions
        # The IR of the leaves that other pieces inline: in `ir`.
        def leaves = []
      end

      # A piece that this build takes from its entry, `record`. Its data
      # loads on first use.
      Kept = Struct.new(:path, :entry, :key, :record, :data) do
        def kept? = true
        def function_names = record[:functions].map(&:first)
        def data = self[:data] ||= Marshal.load(record[:data])
        def wants = record[:wants]
        def ir = []
        def leaves = record[:leaves].values.map { |blob| Marshal.load(blob) }
      end

      EMPTY = Set.new.freeze

      attr_reader :code

      def initialize(kind, target, code)
        @kind = kind
        @target = target
        @code = code
        @backend = Native::CodeCache.backend_digest
      end

      # Writes an entry for each piece this build lowered. `fingerprints` gives
      # each function's fingerprint, and `defined` what the unit defines.
      def keep(fingerprints, defined)
        return if Zr.moved

        @pieces.each do |piece|
          next if piece.kept? || piece.key.nil?

          leaves = piece.functions.select { |f| @inliner.settled_leaf?(f.name) }
          record = {
            names: piece.names, sites: piece.sites, wants: piece.wants, reads: piece.reads, data: Marshal.dump(piece.data),
            functions: piece.functions.map { |f| [f.name, fingerprints.fetch(f.name)] },
            calls: piece.functions.to_h { |f| [f.name, @inliner.calls(f.name).to_h { |sym| [sym, dependency(sym)] }] },
            bits: piece.functions.flat_map { |f| f.callees.map(&:symbol) }.uniq.to_h { |sym| [sym, defined.include?(sym)] },
            leaves: leaves.to_h { |f| [f.name, Marshal.dump(f)] },
            leaf_prints: leaves.to_h { |f| [f.name, IR::Fingerprint.of(f, EMPTY)] }
          }
          Store.write(:lowering, piece.key, record)
        end
        # The entries of this build, kept or new, are the ones that the next
        # build after an edit reads.
        Store.root("#{@target.triple}-#{@kind}", @pieces.filter_map { |piece| piece.key && Store.path(:lowering, piece.key) })
      rescue SystemCallError
        nil
      end

      # The fingerprint and the code of each function that the build took
      # from an entry, for `Native::Build.cached`.
      def known = @known ||= {}

      private

      # A piece from its entry, or lowered now. A nil `key` is a piece that
      # no key can describe; it is always lowered.
      def piece(path, entry, key, &)
        record = key && fetch(key)
        if record && @symbols.fits?(record[:names]) && @symbols.sites == record[:sites].first && reads_hold?(record)
          @symbols.replay(record[:names])
          @symbols.sites = record[:sites].last
          Kept.new(path, entry, key, record)
        else
          reason = if key.nil? then "no key"
                   elsif record then why_not(record)
                   else "no entry"
                   end
          note(path, reason)
          lowered(path, entry, key, &)
        end
      end

      # Lowers a piece with the block, which returns `[functions, data]`. With
      # `sites`, it lowers with that site counter and then restores the one
      # the build had.
      def lowered(path, entry, key, sites: nil)
        if sites
          after = @symbols.sites
          @symbols.sites = sites
        end
        before = @symbols.sites
        functions = data = nil
        reads = nil
        names = @symbols.record { reads = reading { functions, data = yield } }
        piece = Lowered.new(path, entry, key, functions, data, names, [before, @symbols.sites], wants_of(functions),
                            functions.to_h { |f| [f.name, small?(f)] }, reads)
        @symbols.sites = after if sites
        piece
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

      def why_not(record)
        return "names" unless @symbols.fits?(record[:names])

        @symbols.sites == record[:sites].first ? "kernel rows" : "sites"
      end

      # Whether `f` can become a leaf: a function with more instructions than
      # Inline::LIMIT before inlining never becomes one.
      def small?(f) = f.blocks.sum { |b| b.insts.size } <= IR::Passes::Inline::LIMIT

      # The symbols that `functions` call, and those of the data that they
      # read and that are not colocated, as `Runtime#write_cached` counts them.
      def wants_of(functions)
        [functions.flat_map { |f| f.callees.map(&:symbol) }.uniq, functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq]
      end

      # An entry's key: the cache's kind (core, eval-jit, eval-walk), the
      # backend, the base of the unit and the piece's own parts.
      def key_of(*parts) = Store.key(@kind, @backend, @base, *parts)

      def fetch(key) = Store.read(:lowering, key)

      # The pieces this build takes from an entry, after the checks; the
      # others it lowers now (`again`), each with the site counter it had.
      def settle(pieces)
        loop do
          owner = {}
          pieces.each { |piece| piece.function_names.each { |name| owner[name] = piece } }
          defined = defined_names(pieces)
          failed = pieces.select { |piece| piece.kept? && !current?(piece, owner, defined) }
          return pieces if failed.empty?

          failed.each { |piece| pieces[pieces.index(piece)] = again(piece) }
        end
      end

      # What `Aarch64.unit` counts as defined: the fixed part's names
      # (`fixed_names`) and every function and data of the pieces.
      def defined_names(pieces)
        names = fixed_names.dup
        pieces.each { |piece| names.concat(piece.function_names, piece.data.map(&:name)) }
        names.to_set
      end

      # Whether an entry still holds: each callee is what it was, each bit
      # of `defined` is the same, and the code cache has each function.
      def current?(piece, owner, defined)
        reason = stale(piece.record, owner, defined)
        note(piece.path, reason) if reason
        reason.nil?
      end

      # Why an entry no longer holds, or nil when it holds.
      def stale(record, owner, defined)
        bit = record[:bits].find { |sym, was| defined.include?(sym) != was }
        return "#{bit.first} is #{bit.last ? "no longer" : "now"} defined" if bit

        record[:calls].each_value do |calls|
          call = calls.find { |sym, was| now(sym, owner) != was }
          return "#{call.first} was #{call.last.inspect}, now #{now(call.first, owner).inspect}" if call
        end
        missing = record[:functions].find { |_, key| !code.take(key) }
        "no code for #{missing.first}" if missing
      end

      # Notes the first reason that a piece is lowered, for ZR_TIMING.
      def note(path, reason)
        @why ||= "#{File.basename(path.to_s)}: #{reason}"
        (@whys ||= Hash.new(0))[reason.sub(/\A\S+ (is|was) /, "a callee \\1 ")[0, 60]] += 1
      end

      # What the symbol `sym` is in this build, as an entry records it.
      def now(sym, owner)
        fixed = fixed_state(sym)
        return fixed if fixed

        piece = owner[sym]
        return :absent if piece.nil?
        return [:piece, piece.record[:leaf_prints][sym]] if piece.kept?

        # Lowered now: it can have changed, unless it is too large to inline.
        piece.small.fetch(sym, true) ? :changed : [:piece, nil]
      end

      # What the symbol `sym` was, for an entry this build writes.
      def dependency(sym)
        fixed = fixed_state(sym)
        return fixed if fixed
        return :absent unless @piece_names.key?(sym)

        [:piece, @inliner.settled_leaf?(sym) ? IR::Fingerprint.of(@inliner_functions.fetch(sym), EMPTY) : nil]
      end

      # One pass of inlining over the fixed part and the IR this build
      # lowered, with the leaves of each piece taken from an entry as sources.
      def inline(pieces, fixed_ir)
        ir = fixed_ir + pieces.flat_map(&:ir)
        sources = pieces.flat_map(&:leaves)
        @piece_names = pieces.flat_map(&:function_names).to_h { |name| [name, true] }
        @inliner_functions = (ir + sources).to_h { |f| [f.name, f] }
        @inliner = IR::Passes::Inline.new(ir, sources: sources)
        @inliner.run
      end

      # The base of every key of this lowering: the format, the target, the
      # path root and the compiler, then `parts` of the unit.
      def base_key(*parts) = Store.key(VERSION, @target.triple, Paths.root.to_s, RuntimeSources.for(@target).compiler_digest, *parts)

      # Checks the pieces, inlines over the unit, and returns the code of
      # each function: IR from a piece lowered now, `Obj::Code` from a
      # kept one. `label` names the steps for ZR_TIMING.
      def finish(pieces, fixed_ir, label)
        @pieces = Zr.clock("#{label}: checked") { settle(pieces) }
        report(label, @pieces)
        Zr.clock("#{label}: inlined") { inline(@pieces, fixed_ir) }
        Zr.clock("#{label}: code read") { @pieces.flat_map { |piece| piece.kept? ? kept_code(piece) : piece.functions } }
      end

      def kept_code(piece)
        piece.record[:functions].map do |name, key|
          function, blob = code.take(key)
          known[name] = [key, blob]
          function
        end
      end

      def report(label, pieces)
        return unless Config.current.timing?

        warn format("zr: %s: %d of %d pieces from entries%s", label, pieces.count(&:kept?), pieces.size,
                    @why ? " (first lowered: #{@why})" : "")
        @whys&.sort_by { |_, n| -n }&.first(5)&.each { |reason, n| warn format("zr: %s:   %4d lowered: %s", label, n, reason) }
      end
    end
  end
end
