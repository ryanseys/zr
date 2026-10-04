# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "paths"
require_relative "target"
require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "lower"
require_relative "cache/unit"
require_relative "timing"
require_relative "load_tables"
require_relative "symbol_numbering"
require_relative "gc_tuning"
require_relative "source_guard"
require_relative "cache/store"
require_relative "cache/kernel"
require_relative "runtime_sources"
require_relative "cache/lowering/core"
require_relative "cache/lowering/eval_support"
require_relative "manifest"

module Zr

  # The kernel and the core library, lowered once per process, and only
  # as much as a build needs. A program's lowering reads the kernel's
  # description and the symbol table from the cache. Only a build with
  # no cached runtime object lowers the kernel and the core.
  class Runtime
    # @rbs @sources: Hash[String, String]?
    # @rbs @unit: Machine::Lower?
    # @rbs @released: bool?
    # @rbs @description: Machine::Description?
    # @rbs @raw: Array[String]?
    # @rbs @digest: String?
    # @rbs @stamps: Hash[String, [Rational, Integer]?]?
    # @rbs @gem_prelude_files: Array[String]?
    # @rbs @core_cache: Cache::Lowering::Core?
    # @rbs @lowered: [Array[Obj::Code | IR::Function], Array[Obj::Datum]]?
    # @rbs @carried_text: String?
    # @rbs @abi_digest: String?
    # @rbs @eval_digest: String?
    # @rbs @fixed_ids: Hash[String?, Integer]?
    # @rbs @cached: Hash[Symbol, untyped]?
    # @rbs @table: Machine::Symbols

    attr_reader :target #: Target

    #: (?Target target) -> void
    def initialize(target = Target.default)
      @target = target
    end

    # Every source, read once. The digest covers the bytes that the
    # kernel and the core were lowered from, not a later edit. So a build
    # that runs while a file changes cannot cache old output under the
    # new digest.
    #: () -> Hash[String, String]
    def sources
      @sources ||= RuntimeSources.for(target).sources.to_h { |path| [path, File.read(path)] }
    end

    # The lowered kernel, from the cache when an earlier build lowered the
    # same kernel (`Cache::Kernel`). The core's lowering and the runtime
    # object need it. A program's own lowering does not.
    #: () -> Machine::Lower
    def unit
      raise "the runtime's IR was released" if @released

      @unit ||= Timing.phase("lowering the kernel", "kernel lowered") do
        GcTuning.heavy!
        files = RuntimeSources.for(target).kernel_files.map do |path|
          [sources.fetch(path), path] #: [String, String]
        end
        Cache::Kernel.lowered(target, files) { Machine::Lower.new(files).tap(&:run) }
      end
    end

    # The kernel's defs, constants and layouts: all that a program's
    # lowering needs from the kernel. It comes from the cache, or from
    # the unit.
    #: () -> Machine::Description
    def description
      @description ||= Machine::Description.parse(cached.fetch(:description))
    end

    #: () -> Array[String]
    def raw = @raw || unit.raw

    # The runtime object in the cache (`Native::Build.runtime_object`).
    #: () -> String
    def object_path = Cache::Store.path(:object, digest)

    #: () -> String
    def digest
      # The target is the first input, so two targets never share build
      # output. Each path is an input with its bytes, because the runtime
      # object contains the core's file names; so two checkouts never
      # share one. A build with a path root (`Paths.root`) writes
      # different names, so the root is also an input.
      @digest ||= Timing.phase("taking the runtime digest", "runtime digest") do
        files = sources.keys + gem_prelude_files
        @stamps = files.to_h { |path| [path, Paths.stamp(path)] }
        digest_of(files)
      end
    end

    # A file in the digest that changed on disk after the digest was
    # computed, or nil. The build keeps the bytes that the digest covers.
    # But eval support, the prelude and the harness read files again from
    # disk. An edit during a build would put new content under the old
    # digest in every cache. So nothing is cached after a file changes
    # (`Cache::Store.write_file`, `Cache::Unit#keep`, the parse cache, the harness's
    # binaries), and the build stops with the file's name. The cost is one
    # stat per file, which is small compared to a cache write.
    #: () -> String?
    def moved
      stamps = @stamps or return nil

      stamps.each { |path, stamp| return path if Paths.stamp(path) != stamp }
      nil
    end

    # The files that the gem prelude loads. Only its loader knows them.
    # The list comes from the cache (keyed on the digest of all other
    # inputs), or from building the prelude's HIR. If a change to one of
    # them adds or removes a file, the digest changes and the list is
    # computed again.
    # The cache file that lists them.
    #: () -> String
    def gem_prelude_path = RuntimeSources.gem_prelude_list(digest_of(sources.keys))

    #: () -> Array[String]
    def gem_prelude_files
      @gem_prelude_files ||= begin
        path = gem_prelude_path
        files = JSON.parse(File.read(path)) if File.exist?(path)
        unless files&.all? { |file| File.file?(file) }
          files = [Library::Layout::GEM_PRELUDE, *Runtime.gem_prelude(target).units.map(&:file).select { |file| File.file?(file) }].uniq.sort
          Cache::Store.write_file(path, JSON.generate(files))
        end
        files
      end
    end

    #: (Array[String] files) -> String
    def digest_of(files) = Digests.sources(target, files, sources)

    # The symbol table after the core library. It comes from the cache if
    # an earlier build lowered the core with this digest.
    #: () -> Machine::Symbols
    def symbols
      cached.fetch(:symbols)
    end

    # The function and data symbols that the runtime refers to but does
    # not define. A program defines them. `{ functions:, data: }`.
    #: () -> { functions: Array[String], data: Array[String] }
    def wants
      cached.fetch(:wants)
    end

    #: () -> Array[Obj::Code | IR::Function]
    def functions = unit.functions + lowered.first
    # The `Cache::Lowering::Core` of this build's lowering, or nil.
    #: () -> Cache::Lowering::Core?
    def core_cache
      lowered
      @core_cache
    end

    #: () -> Array[Obj::Datum]
    def data = unit.data + lowered.last

    # Releases the kernel's and the core's IR, after the runtime object
    # and the cache contain all that a build reads from them. So a program
    # lowered after this is not in memory at the same time. After this, a
    # call that needs the IR raises; it does not lower again. A warm build
    # never lowers the kernel, not even for the raw functions (only the
    # runtime object contains them).
    #: () -> void
    def release
      @raw = @unit&.raw
      @unit = @lowered = @core_cache = nil
      @released = true
    end

    # The kernel's description as eval support carries it: the source of
    # `zr_description.rb`, which `require "zr_description"` finds
    # (lib/zr/eval.rb, `Library::Roots::DESCRIPTION`). The JIT of a binary
    # lowers eval'd code against it, not against the kernel. zr makes it
    # from this runtime's description, so it is never out of date and
    # nobody commits it.
    #: () -> String
    def carried_text =@carried_text ||= Machine::Description.carried(cached.fetch(:description))

    # `RuntimeSources#abi_digest`: what a program's units and eval support's
    # code take from this runtime. It reads the symbol table's cache, which
    # it makes first.
    #: () -> String
    def abi_digest
      @abi_digest ||= (cached && RuntimeSources.for(target).abi_digest(digest)) || raise("no symbol table for runtime #{digest}")
    end

    # `RuntimeSources#eval_digest`: what eval support's object takes from
    # this runtime: its ABI and the table that numbers eval support's names.
    #: () -> String
    def eval_digest
      @eval_digest ||= (cached && RuntimeSources.for(target).eval_digest(digest)) || raise("no symbol table for runtime #{digest}")
    end

    # The ids that code outside the kernel has as immediates: the kernel's
    # names, name to id. Each other name is a pool word that the link
    # numbers (`Lower#fixed_id`).
    #: () -> Hash[String?, Integer]
    def fixed_ids
      @fixed_ids ||= symbols.names.first(cached.fetch(:kernel)).each_with_index.to_h { |name, i| [name, i] }.freeze
    end

    private

    # The kernel's own symbol table: the names of its `Machine.id`s, in the
    # order of its files. Only these ids are in code outside the kernel.
    #: () -> Machine::Symbols
    def kernel_symbols = unit.symbols

    # The symbol table, the wanted symbols and the kernel's description.
    # They come from the cache, or from lowering the kernel and the core
    # (then cached). A cache file with a missing field is a miss.
    #: () -> Hash[Symbol, untyped]
    def cached
      @cached ||= read_cached || write_cached
    end

    #: () -> String
    def cache_path = RuntimeSources.symbols_path(digest)

    #: () -> Hash[Symbol, untyped]?
    def read_cached
      return unless File.exist?(cache_path)

      rows = JSON.parse(File.read(cache_path))
      return unless %w[names sites kernel functions data description].all? { |key| rows.key?(key) }

      { symbols: Machine::Symbols.new(rows.fetch("names"), sites: rows.fetch("sites")), kernel: rows.fetch("kernel"),
        wants: { functions: rows.fetch("functions"), data: rows.fetch("data") },
        description: rows.fetch("description") }
    end

    #: () -> Hash[Symbol, untyped]
    def write_cached
      GcTuning.heavy!
      Runtime.announce("the zr runtime", target)
      lowered
      defined = functions.map(&:name)
      ir = functions.grep(IR::Function) #: Array[IR::Function]
      calls = ir.flat_map { |f| f.callees.map(&:symbol) }
      reads = ir.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }
      if (core = @core_cache)
        kept_calls, kept_reads = core.calls_and_reads
        calls += kept_calls
        reads += kept_reads
      end
      wanted_functions = (calls.uniq - defined).sort
      wanted_data = (reads.uniq - data.map(&:name)).sort
      description = Machine::Description.of(unit).to_text
      Cache::Store.write_file(cache_path,
                     JSON.generate({ "names" => @table.names, "sites" => @table.sites, "kernel" => kernel_symbols.names.size,
                                     "functions" => wanted_functions, "data" => wanted_data, "description" => description }))
      { symbols: @table, kernel: kernel_symbols.names.size, wants: { functions: wanted_functions, data: wanted_data },
        description: description }
    end

    # The core library's `[functions, data]`, lowered over the kernel.
    #
    # For an aarch64 build, `Cache::Lowering::Core` takes each file it can from an
    # earlier build, and the list then has the machine code of those files
    # (`Obj::Code`) in place of their IR. It also inlines the unit.
    #
    # The core has only the kernel's ids in its code. Its other names are
    # pool words, which this numbers in the order of the core's data, after
    # the kernel's names (`@table`). The data is a numbered copy: the pieces
    # that the core cache keeps stay unnumbered, so an edit that adds a name
    # moves the ids after it and no code.
    #: () -> [Array[Obj::Code | IR::Function], Array[Obj::Datum]]
    def lowered
      @lowered ||= Timing.phase("lowering the core", "core lowered") do
        core = @core_cache = Timing.phase("core cache: opening", "core cache: opened") { Cache::Lowering::Core.for(target) }
        fixed = unit.symbols.ids.dup.freeze
        functions, data = core ? core.lower(unit, fixed, sources) : Runtime.core(unit, fixed, target, sources)
        @table = Machine::Symbols.new(kernel_symbols.names, sites: kernel_symbols.sites)
        tag = unit.const_for("SYMBOL_TAG") #: Integer
        [functions, SymbolNumbering.numbered_copies(data, @table, tag)]
      end
    end
  end

  # The runtimes of a process, and how a runtime's core and gem prelude
  # are built.
  class Runtime
    # The runtimes of this process, by target triple.
    #: () -> Hash[String, Runtime]
    def self.loaded
      Session.current.memo(:runtimes) do
        {} #: Hash[String, Runtime]
      end
    end

    # The runtime for `target`, lowered once per process.
    #: (?Target target) -> Runtime
    def self.for(target = Target.default) = loaded[target.triple] ||= new(target)

    # Says on stderr, once in a process, that a build of `what` for
    # `target` starts, which fills the cache for later builds. The first
    # build of an installed zr would otherwise run for minutes with no
    # output. A checkout says it only on a terminal: a test or a tool
    # that reads stderr gets nothing more. ZR_TIMING prints its own lines.
    #: (String what, Target target) -> void
    def self.announce(what, target)
      return if Config.current.timing? || (Paths.checkout? && !$stderr.tty?)

      announced = @announced ||= {} #: Hash[[String, String], bool]
      return if announced.key?([what, target.triple])

      announced[[what, target.triple]] = true
      warn "zr: building #{what} for #{target.triple}. This occurs one time and takes some minutes."
    end

    # The core library on top of the kernel `unit`: `[functions, data]`,
    # with `zr_prelude` as the last function. The program decides if it
    # links in the compiler, so the core never requires eval support. A
    # box or an eval in the program adds it. `fixed` are the kernel's ids;
    # the data leaves every other name to the link
    # (`SymbolNumbering.numbered_copies`).
    # @rbs unit: Machine::Lower
    # @rbs fixed: Hash[String, Integer]
    # @rbs target: Target
    # @rbs sources: Hash[String, String]
    # @rbs return: [Array[IR::Function | Obj::Code], Array[Obj::Datum]]
    def self.core(unit, fixed, target = Target.default, sources = {})
      functions = [] #: Array[IR::Function | Obj::Code]
      data = [] #: Array[Obj::Datum]
      entries = RuntimeSources.for(target).core_files.map do |path|
        f, d = lower_core_file(path, sources.fetch(path) { File.read(path) }, unit, fixed, target)
        functions.concat(f)
        data.concat(d)
        core_entry(path)
      end
      f, d = lower_gem_prelude(gem_prelude(target), unit, fixed, target)
      [functions.concat(f) << prelude(entries, unit), data.concat(d)]
    end

    # The entry of a core file's toplevel.
    #: (String path) -> String
    def self.core_entry(path) = "zr_core_#{File.basename(path, ".rb")}"

    # `[functions, data]` of one core file over the kernel `unit`, with the
    # kernel's ids `fixed`.
    # @rbs path: String
    # @rbs source: String
    # @rbs unit: Machine::Lower
    # @rbs fixed: Hash[String, Integer]
    # @rbs target: Target
    # @rbs return: [Array[IR::Function | Obj::Code], Array[Obj::Datum]]
    def self.lower_core_file(path, source, unit, fixed, target)
      Lower.new(Hir.build(source, path, eval_support: false, target: target), unit, nil, entry: core_entry(path), internal: true,
                                                                                   target: target, fixed: fixed).run
    end

    # `[functions, data]` of the gem prelude's program `hir`.
    #: (Hir::Program hir, Machine::Lower unit, Hash[String, Integer] fixed, Target target) -> [Array[IR::Function | Obj::Code], Array[Obj::Datum]]
    def self.lower_gem_prelude(hir, unit, fixed, target)
      Lower.new(hir, unit, nil, entry: GEM_PRELUDE_ENTRY, kind: :top, target: target, fixed: fixed).run
    end

    GEM_PRELUDE_ENTRY = "zr_gem_prelude"

    # CRuby's gem_prelude.rb, which loads ruby's default libraries before
    # a program's first line. After it comes error_highlight's lookup for
    # a program compiled ahead of time. Boot runs it after the core
    # library loads, before the program.
    SPOTTED = File.join(Library::Layout::RUNTIME_LIB, "zr/error_highlight.rb")

    # The parsers that the prelude's libraries require for work that this
    # runtime does differently. error_highlight's prism_find: the compiled
    # spots replace it. syntax_suggest's search: only a program that links
    # in the compiler can get a SyntaxError.
    DEFERRED = %w[prism syntax_suggest/api].freeze

    # The gem prelude as one program for `target`.
    #: (?Target target) -> Hir::Program
    def self.gem_prelude(target = Target.default)
      loader = Hir::Build::Loader.new(Library::Roots.stdlib(target), deferred: DEFERRED,
                                                                 preloaded: Hir::Build::PRELOADED - Hir::Build::GEM_PRELOADED)
      main = loader.unit("<internal:gem_prelude>", File.read(Library::Layout::GEM_PRELUDE))
      spotted = Hir::Require.new(:hidden, "zr/error_highlight", SPOTTED, loader.add(SPOTTED), 0)
      # did_you_mean reads RbConfig, which ruby has loaded by then.
      rbconfig = loader.configures? ? [Hir::Build.rbconfig(loader)] : [] #: Array[Hir::node]
      body = Hir::Seq.new([*rbconfig, main.body, spotted], 0)
      Hir::Program.new(main.file, main.locals, body, loader.units, main.warnings, false, loader.entries, false, main.node_ids, {})
    end

    # `zr_prelude`: boot runs each core file's toplevel in turn, and
    # stops at the first one that leaves a pending unwind.
    #: (Array[String] entries, Machine::Lower unit) -> IR::Function
    def self.prelude(entries, unit)
      f = IR::Function.new("zr_prelude", [], "i64")
      # The kernel declares QUNDEF and QNIL.
      qundef = unit.const_for("QUNDEF") #: Integer
      undef_value = f.iconst("i64", qundef)
      entries.each do |entry|
        r = f.call_val(f.callee(entry, [], "i64"), [])
        stop = f.label
        go = f.label
        f.brif(f.icmp("eq", r, undef_value), stop, go)
        f.switch(stop)
        f.ret(r)
        f.switch(go)
      end
      qnil = unit.const_for("QNIL") #: Integer
      f.ret(f.iconst("i64", qnil))
      f
    end
  end
end

require_relative "eval_support"
require_relative "program"
