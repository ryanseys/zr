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
  # The core library's files that a build does not lower again: a file
  # whose inputs are the same as at an earlier build gets that build's
  # machine code (`Native::CodeCache`) and data in place of its IR.
  #
  # Lowering the core took 7 s of each runtime build, and loading its IR
  # from a cache took longer (15 s of Marshal), so a file is either lowered
  # or not needed at all. An entry keeps what the rest of the build reads
  # from a file's lowering: the fingerprint of each function, its data, the
  # names it asked the symbol table for with their ids, its sites, the
  # symbols it wants from a program, and the IR of each of its leaves,
  # which other functions inline.
  #
  # A function's code also depends on the other functions: on the leaves
  # that it inlines, and on which of its callees the unit defines. An
  # entry records, for each colocated symbol that a function calls, what
  # that symbol was: a kernel leaf (with the fingerprint of its IR), a
  # kernel function that is not a leaf, a core function, or no function.
  # The build checks each entry against the unit of this build before any
  # inlining: a core callee must come from a file that this build also
  # takes from an entry. Then it lowers each file that fails, with the
  # site counter that the file had, and inlines once over the whole unit.
  # So the code is the same as a build that lowers every file, which
  # `core_cache_test.rb` checks byte for byte.
  class CoreCache
    VERSION = 1

    Lowered = Struct.new(:path, :entry, :key, :functions, :data, :names, :sites, :wants)
    Kept = Struct.new(:path, :entry, :key, :record, :data)

    # The core cache for `target`, or nil: only the aarch64 runtime object
    # has a code cache to take the code from.
    def self.for(target)
      code = Native::CodeCache.for("runtime", target)
      code && new(target, code)
    end

    attr_reader :code

    def initialize(target, code)
      @target = target
      @code = code
      @dir = File.join(Paths.cache, "core", Native::CodeCache.backend_digest[0, 16])
    end

    # Lowers the core over the kernel `unit`, as `Zr.core` does, taking each
    # file it can from an entry. Returns `[functions, data]`: IR for a file
    # that it lowered, `Obj::Function` for one that it took. It inlines the
    # whole unit (the kernel's functions too), so the object build must not.
    def lower(unit, symbols, sources)
      @unit = unit
      @symbols = symbols
      @base = Zr.clock("core cache: key") { base_key(unit) }
      @kernel = unit.functions
      @kernel_names = @kernel.to_h { |f| [f.name, true] }
      kernel = IR::Passes::Inline.new(@kernel)
      Zr.clock("core cache: kernel inlined") { kernel.run }
      @kernel_leaf = Zr.clock("core cache: kernel leaves") { @kernel.to_h { |f| [f.name, kernel.settled_leaf?(f.name) ? IR::Fingerprint.of(f, EMPTY) : nil] } }
      @kernel_calls = @kernel.flat_map { |f| kernel.calls(f.name) }.uniq.reject { |sym| @kernel_names[sym] }

      files = Zr.clock("core cache: files") { each_file(sources) }
      @core_entries = files.map(&:entry)
      # The gem prelude is one more file: its key has each file it loads.
      @gem_hir = Zr.clock("core cache: gem prelude built") { Zr.gem_prelude(@target) }
      files << file(Zr::GEM_PRELUDE, "zr_gem_prelude", gem_source)
      @prelude = Zr.prelude(@core_entries, unit)

      files = Zr.clock("core cache: checked") { settle(files, sources) }
      @files = files
      if Config.current.timing?
        warn format("zr: core cache: %d of %d files from entries%s", files.count { |f| f.is_a?(Kept) }, files.size,
                    @why ? " (first lowered: #{@why})" : "")
      end
      Zr.clock("core cache: inlined") { inline(files) }
      # The kernel inlines alone only while it calls nothing of the core.
      core_call = @kernel_calls.find { |sym| @core_names[sym] }
      raise "the kernel calls #{core_call} of the core, so CoreCache cannot inline it alone" if core_call
      functions = Zr.clock("core cache: code read") { files.flat_map { |file| file.is_a?(Kept) ? kept_code(file) : file.functions } }
      functions << @prelude
      data = Zr.clock("core cache: data read") { files.flat_map { |file| file.data || (file.data = Marshal.load(file.record[:data])) } }
      [functions, data]
    end

    # The symbols that the core's functions call, and the symbols of the
    # data that they read and that are not colocated (`Runtime#wants`).
    def calls_and_reads
      pairs = @files.map { |file| file.is_a?(Kept) ? file.record[:wants] : file.wants }
      [pairs.flat_map(&:first).uniq, pairs.flat_map(&:last).uniq]
    end

    # Writes an entry for each file this build lowered. `fingerprints` gives
    # each function's fingerprint, and `defined` what the unit defines.
    def keep(fingerprints, defined)
      return if Zr.moved

      FileUtils.mkdir_p(@dir)
      @files.each do |file|
        next if file.is_a?(Kept)

        record = {
          names: file.names, sites: file.sites, wants: file.wants, data: Marshal.dump(file.data),
          functions: file.functions.map { |f| [f.name, fingerprints.fetch(f.name)] },
          calls: file.functions.to_h { |f| [f.name, @inliner.calls(f.name).to_h { |sym| [sym, dependency(sym)] }] },
          bits: file.functions.flat_map { |f| f.callees.map(&:symbol) }.uniq.to_h { |sym| [sym, defined.include?(sym)] },
          leaves: file.functions.select { |f| @inliner.settled_leaf?(f.name) }.to_h { |f| [f.name, Marshal.dump(f)] }
        }
        Paths.write_atomic(File.join(@dir, "#{file.key}.marshal"), Marshal.dump(record))
      end
    rescue SystemCallError
      nil
    end

    # The fingerprint and the code of each function that the build took
    # from an entry, for `Native::Build.cached`.
    def known = @known ||= {}

    EMPTY = Set.new.freeze

    private

    def each_file(sources)
      Zr.core_files(@target).map do |path|
        file(path, "zr_core_#{File.basename(path, ".rb")}", sources.fetch(path) { File.read(path) })
      end
    end

    # A file from its entry, or lowered now.
    def file(path, entry, source)
      key = key_of(path, entry, source)
      record = fetch(key)
      if record && @symbols.holds?(record[:names]) && @symbols.sites == record[:sites].first
        @symbols.replay(record[:names])
        @symbols.sites = record[:sites].last
        Kept.new(path, entry, key, record)
      else
        why(path, record ? (@symbols.holds?(record[:names]) ? "sites" : "names") : "no entry")
        lower_file(path, entry, key, source)
      end
    end

    # The key text of the gem prelude: the path and the bytes of each file
    # that its program loads.
    def gem_source = @gem_hir.units.map { |u| "#{u.file}\0#{u.source}" }.join("\0") + File.read(Zr::GEM_PRELUDE)


    def base_key(unit)
      Digest::SHA256.hexdigest([VERSION, @target.triple, Paths.root.to_s, Zr.compiler_digest(@target),
                                Machine::Description.of(unit).to_text, Lower.boot_classes.inspect].join("\0"))
    end

    def key_of(path, entry, source) = Digest::SHA256.hexdigest([@base, path, entry, source.b].join("\0"))

    def fetch(key)
      path = File.join(@dir, "#{key}.marshal")
      File.exist?(path) ? Marshal.load(File.binread(path)) : nil
    rescue SystemCallError, TypeError, ArgumentError
      nil
    end

    def lower_file(path, entry, key, source, sites: nil)
      if sites
        after = @symbols.sites
        @symbols.sites = sites
      end
      before = @symbols.sites
      functions = data = nil
      names = @symbols.record do
        functions, data =
          if path == Zr::GEM_PRELUDE
            Lower.new(@gem_hir, @unit, @symbols, entry: entry, kind: :top, target: @target).run
          else
            Lower.new(Hir.build(source, path, eval_support: false, target: @target), @unit, @symbols, entry: entry, internal: true,
                                                                                         target: @target).run
          end
      end
      lowered = Lowered.new(path, entry, key, functions, data, names, [before, @symbols.sites], wants_of(functions, data))
      @symbols.sites = after if sites
      lowered
    end

    # The symbols that `functions` call, and those of the data that they
    # read and that are not colocated, as `Runtime#write_cached` counts them.
    def wants_of(functions, _data)
      [functions.flat_map { |f| f.callees.map(&:symbol) }.uniq, functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq]
    end

    # The files this build takes from an entry, after the checks; the
    # others it lowers now, each with the site counter it had.
    def settle(files, sources)
      loop do
        core = {}
        files.each do |file|
          names = file.is_a?(Kept) ? file.record[:functions].map(&:first) : file.functions.map(&:name)
          names.each { |name| core[name] = file }
        end
        core[@prelude.name] = :lowered
        defined = defined_names(files)
        failed = files.select { |file| file.is_a?(Kept) && !current?(file, core, defined) }
        return files if failed.empty?

        failed.each do |file|
          at = files.index(file)
          source = file.path == Zr::GEM_PRELUDE ? gem_source : sources.fetch(file.path) { File.read(file.path) }
          files[at] = lower_file(file.path, file.entry, file.key, source, sites: file.record[:sites].first)
        end
      end
    end

    # What `Aarch64.unit` counts as defined: every function, data and raw
    # function of the runtime's unit.
    def defined_names(files)
      names = @kernel.map(&:name) + @unit.data.map(&:name) + @unit.raw
      files.each do |file|
        if file.is_a?(Kept)
          names.concat(file.record[:functions].map(&:first))
          names.concat((file.data ||= Marshal.load(file.record[:data])).map(&:name))
        else
          names.concat(file.functions.map(&:name), file.data.map(&:name))
        end
      end
      names << @prelude.name
      names.to_set
    end

    # Whether an entry still holds: each callee is what it was, each bit
    # of `defined` is the same, and the code cache has each function.
    def current?(file, core, defined)
      record = file.record
      bit = record[:bits].find { |sym, was| defined.include?(sym) != was }
      return why(file.path, "#{bit.first} is #{bit.last ? "no longer" : "now"} defined") if bit

      record[:calls].each do |_, calls|
        call = calls.find { |sym, was| now(sym, core) != was }
        return why(file.path, "#{call.first} was #{call.last.inspect}, now #{now(call.first, core).inspect}") if call
      end
      missing = record[:functions].find { |_, key| !code.take(key) }
      return why(file.path, "no code for #{missing.first}") if missing

      true
    end

    # Notes the first reason that a file is lowered, for ZR_TIMING.
    def why(path, reason)
      @why ||= "#{File.basename(path)}: #{reason}"
      false
    end

    # What the symbol `sym` is in this build, as an entry records it.
    def now(sym, core)
      return [:kernel, @kernel_leaf[sym]] if @kernel_names[sym]

      owner = core[sym]
      return :absent if owner.nil?

      owner.is_a?(Kept) ? :core : :changed
    end

    # What the symbol `sym` was, for an entry this build writes.
    def dependency(sym)
      return [:kernel, @kernel_leaf[sym]] if @kernel_names[sym]

      @core_names.key?(sym) ? :core : :absent
    end

    # One pass of inlining over the kernel and the IR this build lowered,
    # with the leaves of each file taken from an entry as sources.
    def inline(files)
      ir = @kernel + files.flat_map { |file| file.is_a?(Kept) ? [] : file.functions } + [@prelude]
      sources = files.flat_map { |file| file.is_a?(Kept) ? file.record[:leaves].values.map { |blob| Marshal.load(blob) } : [] }
      @core_names = files.flat_map { |file| file.is_a?(Kept) ? file.record[:functions].map(&:first) : file.functions.map(&:name) }
                         .push(@prelude.name).to_h { |name| [name, true] }
      @inliner = IR::Passes::Inline.new(ir, sources: sources)
      @inliner.run
    end

    def kept_code(file)
      file.record[:functions].map do |name, key|
        function, blob = code.take(key)
        known[name] = [key, blob]
        function
      end
    end
  end
end
