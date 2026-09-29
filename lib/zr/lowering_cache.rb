# frozen_string_literal: true

require "digest/sha2"
require "fileutils"
require_relative "config"
require_relative "paths"
require_relative "sources"
require_relative "ir/fingerprint"
require_relative "ir/passes"
require_relative "native/code_cache"

module Zr
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
  class LoweringCache
    VERSION = 2

    Lowered = Struct.new(:path, :entry, :key, :functions, :data, :names, :sites, :wants, :small)
    Kept = Struct.new(:path, :entry, :key, :record, :data)

    EMPTY = Set.new.freeze

    attr_reader :code

    def initialize(kind, target, code)
      @kind = kind
      @target = target
      @code = code
      @dir = File.join(Paths.cache, kind, Native::CodeCache.backend_digest[0, 16])
    end

    # Writes an entry for each piece this build lowered. `fingerprints` gives
    # each function's fingerprint, and `defined` what the unit defines.
    def keep(fingerprints, defined)
      return if Zr.moved

      FileUtils.mkdir_p(@dir)
      @pieces.each do |piece|
        next if piece.is_a?(Kept) || piece.key.nil?

        leaves = piece.functions.select { |f| @inliner.settled_leaf?(f.name) }
        record = {
          names: piece.names, sites: piece.sites, wants: piece.wants, data: Marshal.dump(piece.data),
          functions: piece.functions.map { |f| [f.name, fingerprints.fetch(f.name)] },
          calls: piece.functions.to_h { |f| [f.name, @inliner.calls(f.name).to_h { |sym| [sym, dependency(sym)] }] },
          bits: piece.functions.flat_map { |f| f.callees.map(&:symbol) }.uniq.to_h { |sym| [sym, defined.include?(sym)] },
          leaves: leaves.to_h { |f| [f.name, Marshal.dump(f)] },
          leaf_prints: leaves.to_h { |f| [f.name, IR::Fingerprint.of(f, EMPTY)] }
        }
        Paths.write_atomic(File.join(@dir, "#{piece.key}.marshal"), Marshal.dump(record))
      end
    rescue SystemCallError
      nil
    end

    # The fingerprint and the code of each function that the build took
    # from an entry, for `Native::Build.cached`.
    def known = @known ||= {}

    private

    # A piece from its entry, or lowered now. A nil `key` is a piece that
    # no key can describe; it is always lowered.
    def piece(path, entry, key, &lower)
      record = key && fetch(key)
      if record && @symbols.fits?(record[:names]) && @symbols.sites == record[:sites].first
        @symbols.replay(record[:names])
        @symbols.sites = record[:sites].last
        Kept.new(path, entry, key, record)
      else
        why(path, key.nil? ? "no key" : record ? (@symbols.fits?(record[:names]) ? "sites" : "names") : "no entry")
        lowered(path, entry, key, &lower)
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
      names = @symbols.record { functions, data = yield }
      piece = Lowered.new(path, entry, key, functions, data, names, [before, @symbols.sites], wants_of(functions),
                          functions.to_h { |f| [f.name, small?(f)] })
      @symbols.sites = after if sites
      piece
    end

    # Whether `f` can become a leaf: a function with more instructions than
    # Inline::LIMIT before inlining never becomes one.
    def small?(f) = f.blocks.sum { |b| b.insts.size } <= IR::Passes::Inline::LIMIT

    # The symbols that `functions` call, and those of the data that they
    # read and that are not colocated, as `Runtime#write_cached` counts them.
    def wants_of(functions)
      [functions.flat_map { |f| f.callees.map(&:symbol) }.uniq, functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq]
    end

    def key_of(*parts) = Digest::SHA256.hexdigest([@base, *parts].map { |part| part.to_s.b }.join("\0"))

    def fetch(key)
      path = File.join(@dir, "#{key}.marshal")
      File.exist?(path) ? Marshal.load(File.binread(path)) : nil
    rescue SystemCallError, TypeError, ArgumentError
      nil
    end

    # The pieces this build takes from an entry, after the checks; the
    # others it lowers now (`again`), each with the site counter it had.
    def settle(pieces)
      loop do
        owner = {}
        pieces.each { |piece| names_of(piece).each { |name| owner[name] = piece } }
        defined = defined_names(pieces)
        failed = pieces.select { |piece| piece.is_a?(Kept) && !current?(piece, owner, defined) }
        return pieces if failed.empty?

        failed.each { |piece| pieces[pieces.index(piece)] = again(piece) }
      end
    end

    def names_of(piece) = piece.is_a?(Kept) ? piece.record[:functions].map(&:first) : piece.functions.map(&:name)

    def data_of(piece) = piece.is_a?(Kept) ? (piece.data ||= Marshal.load(piece.record[:data])) : piece.data

    # What `Aarch64.unit` counts as defined: the fixed part's names
    # (`fixed_names`) and every function and data of the pieces.
    def defined_names(pieces)
      names = fixed_names.dup
      pieces.each { |piece| names.concat(names_of(piece), data_of(piece).map(&:name)) }
      names.to_set
    end

    # Whether an entry still holds: each callee is what it was, each bit
    # of `defined` is the same, and the code cache has each function.
    def current?(piece, owner, defined)
      record = piece.record
      bit = record[:bits].find { |sym, was| defined.include?(sym) != was }
      return why(piece.path, "#{bit.first} is #{bit.last ? "no longer" : "now"} defined") if bit

      record[:calls].each_value do |calls|
        call = calls.find { |sym, was| now(sym, owner) != was }
        return why(piece.path, "#{call.first} was #{call.last.inspect}, now #{now(call.first, owner).inspect}") if call
      end
      missing = record[:functions].find { |_, key| !code.take(key) }
      return why(piece.path, "no code for #{missing.first}") if missing

      true
    end

    # Notes the first reason that a piece is lowered, for ZR_TIMING.
    def why(path, reason)
      @why ||= "#{File.basename(path.to_s)}: #{reason}"
      (@whys ||= Hash.new(0))[reason.sub(/\A\S+ (is|was) /, "a callee \\1 ")[0, 60]] += 1
      false
    end

    # What the symbol `sym` is in this build, as an entry records it.
    def now(sym, owner)
      fixed = fixed_state(sym)
      return fixed if fixed

      piece = owner[sym]
      return :absent if piece.nil?
      return [:piece, piece.record[:leaf_prints][sym]] if piece.is_a?(Kept)

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
      ir = fixed_ir + pieces.flat_map { |piece| piece.is_a?(Kept) ? [] : piece.functions }
      sources = pieces.flat_map { |piece| piece.is_a?(Kept) ? piece.record[:leaves].values.map { |blob| Marshal.load(blob) } : [] }
      @piece_names = pieces.flat_map { |piece| names_of(piece) }.to_h { |name| [name, true] }
      @inliner_functions = (ir + sources).to_h { |f| [f.name, f] }
      @inliner = IR::Passes::Inline.new(ir, sources: sources)
      @inliner.run
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

      warn format("zr: %s: %d of %d pieces from entries%s", label, pieces.count { |p| p.is_a?(Kept) }, pieces.size,
                  @why ? " (first lowered: #{@why})" : "")
      @whys&.sort_by { |_, n| -n }&.first(5)&.each { |reason, n| warn format("zr: %s:   %4d lowered: %s", label, n, reason) }
    end
  end
end
