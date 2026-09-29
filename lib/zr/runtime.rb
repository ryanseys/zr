# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "paths"
require_relative "target"
require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "lower"
require_relative "unit_cache"
require_relative "clock"
require_relative "tune"
require_relative "settled"
require_relative "sources"
require_relative "core_cache"

module Zr
  # The kernel and the core library, lowered once per process, and only
  # as much as a build needs. A program's lowering reads the kernel's
  # description and the symbol table from the cache. Only a build with
  # no cached runtime object lowers the kernel and the core.
  class Runtime
    attr_reader :target

    def initialize(target = Target.default)
      @target = target
    end

    # Every source, read once. The digest covers the bytes that the
    # kernel and the core were lowered from, not a later edit. So a build
    # that runs while a file changes cannot cache old output under the
    # new digest.
    def sources
      @sources ||= Zr.sources(target).to_h { |path| [path, File.read(path)] }
    end

    # The lowered kernel. The core's lowering and the runtime object need
    # it. A program's own lowering does not.
    def unit
      raise "the runtime's IR was released" if @released

      @unit ||= Zr.clock("kernel lowered") do
        Tune.heavy!
        Machine::Lower.new(Zr.kernel_files(target).map { |path| [sources.fetch(path), path] }, kernel_symbols).tap(&:run)
      end
    end

    # The kernel's defs, constants and layouts: all that a program's
    # lowering needs from the kernel. It comes from the cache, or from
    # the unit.
    def description
      @description ||= Machine::Description.parse(cached.fetch(:description))
    end

    def raw = @raw || unit.raw

    # The runtime object in the cache (`Native::Build.runtime_object`).
    def object_path = File.join(Paths.cache, "runtime-#{digest}.o")

    def digest
      # The target is the first input, so two targets never share build
      # output. Each path is an input with its bytes, because the runtime
      # object contains the core's file names; so two checkouts never
      # share one. A build with a path root (`Paths.root`) writes
      # different names, so the root is also an input.
      @digest ||= Zr.clock("runtime digest") do
        files = sources.keys + gem_prelude_files
        @stamps = files.to_h { |path| [path, Paths.stamp(path)] }
        Zr.with_ledger(digest_of(files), ledger_text)
      end
    end

    # A file in the digest that changed on disk after the digest was
    # computed, or nil. The build keeps the bytes that the digest covers.
    # But eval support, the prelude and the harness read files again from
    # disk. An edit during a build would put new content under the old
    # digest in every cache. So nothing is cached after a file changes
    # (`Zr.write_cache`, `UnitCache#keep`, the parse cache, the harness's
    # binaries), and the build stops with the file's name. The cost is one
    # stat per file, which is small compared to a cache write.
    def moved
      return nil unless @stamps

      @stamps.each { |path, stamp| return path if Paths.stamp(path) != stamp }
      nil
    end

    # The files that the gem prelude loads. Only its loader knows them.
    # The list comes from the cache (keyed on the digest of all other
    # inputs), or from building the prelude's HIR. If a change to one of
    # them adds or removes a file, the digest changes and the list is
    # computed again.
    # The cache file that lists them.
    def gem_prelude_path = Zr.gem_prelude_list(digest_of(sources.keys))

    def gem_prelude_files
      @gem_prelude_files ||= begin
        path = gem_prelude_path
        files = JSON.parse(File.read(path)) if File.exist?(path)
        unless files&.all? { |file| File.file?(file) }
          files = [GEM_PRELUDE, *Zr.gem_prelude(target).units.map(&:file).select { |file| File.file?(file) }].uniq.sort
          Zr.write_cache(path, JSON.generate(files))
        end
        files
      end
    end

    def digest_of(files) = Zr.source_digest(target, files, sources)

    # The symbol table after the core library. It comes from the cache if
    # an earlier build lowered the core with this digest.
    def symbols
      cached.fetch(:symbols)
    end

    # The function and data symbols that the runtime refers to but does
    # not define. A program defines them. `{ functions:, data: }`.
    def wants
      cached.fetch(:wants)
    end

    def functions = unit.functions + lowered.first
    # The `CoreCache` of this build's lowering, or nil.
    def core_cache
      lowered
      @core_cache
    end


    def data = unit.data + lowered.last

    # Releases the kernel's and the core's IR, after the runtime object
    # and the cache contain all that a build reads from them. So a program
    # lowered after this is not in memory at the same time. After this, a
    # call that needs the IR raises; it does not lower again. A warm build
    # never lowers the kernel, not even for the raw functions (only the
    # runtime object contains them).
    def release
      @raw = @unit&.raw
      @unit = @lowered = @core_cache = nil
      @released = true
    end

    # The kernel's description as eval support carries it: a generated file
    # of the target's OS layer (`zr-dev gen description`). The JIT of a
    # binary lowers eval'd code against that file, not against the kernel,
    # so a file that is out of date miscompiles evals with no error.
    def carried_description = File.join(Paths::RUNTIME, "ext/os/#{target.os_layer}/zr_description.rb")

    # Checks the carried description against the kernel before eval
    # support is built. In a checkout, zr writes the file again and says
    # so. An install never has a stale file, so there it stops the build.
    # Only the target that `zr-dev gen description` writes a layer from
    # checks it, because the other targets of a layer can differ in a row.
    def carry_description!
      return unless Target.all.find { |t| t.os_layer == target.os_layer && t.os_layer == t.os.to_s }&.triple == target.triple

      path = carried_description
      want = Machine::Description.carried(cached.fetch(:description))
      return if File.exist?(path) && File.binread(path) == want

      shown = path.delete_prefix("#{Paths::ROOT}/")
      raise "#{shown} is out of date with runtime/kernel; run `zr-dev gen description`" unless Paths.checkout?

      Paths.write_atomic(path, want)
      warn "zr: #{shown} was out of date with runtime/kernel; zr wrote it again"
    end

    # `Zr.abi_digest`: what a program's units take from this runtime. It reads the symbol table's cache, which it makes first.
    def abi_digest
      @abi_digest ||= (cached && Zr.abi_digest(target, digest)) || raise("no symbol table for runtime #{digest}")
    end

    # `Zr.eval_digest`: what eval support takes from this runtime, besides
    # the ids of the names it uses.
    def eval_digest
      @eval_digest ||= (cached && Zr.eval_digest(target, digest)) || raise("no symbol table for runtime #{digest}")
    end

    private

    # The runtime's symbol table, which the kernel and the core fill. In a
    # checkout it starts from the ledger, so each name keeps its id.
    def kernel_symbols
      @kernel_symbols ||= Machine::Symbols.new(ledger, fill: true)
    end

    # The ledger: the runtime's names by id at this checkout's last build,
    # nil for an id free to take (a pad, or a name that build did not use).
    # Each name then keeps its id, and a new name takes a free id. Without
    # it, a new name in an early core file moved the id of every name after
    # it, and with that the code of most functions (`Native::CodeCache`)
    # and all of eval support. A table from a ledger depends on the builds
    # before it, so an install, `zr-dev repro` (a new cache) and a release
    # (`ZR_LEDGER=0`) never read one; their ids come from the sources only.
    def ledger
      ledger_text ? JSON.parse(ledger_text) : []
    rescue JSON::ParserError
      []
    end

    # The ledger's bytes, read once: the digest covers the same bytes that
    # number the symbols.
    def ledger_text
      return @ledger_text if defined?(@ledger_text)

      @ledger_text = Zr.ledger_text(target)
    end

    # Writes the ledger for the next build: this table's names, with nil
    # for each name that this build did not ask for.
    def keep_ledger(symbols)
      return unless Zr.ledger?

      Zr.write_cache(Zr.ledger_path(target), JSON.generate(symbols.names.each_with_index.map { |name, i| name if symbols.used?(i) }))
    end

    # The symbol table, the wanted symbols and the kernel's description.
    # They come from the cache, or from lowering the kernel and the core
    # (then cached). A cache file with a missing field is a miss.
    def cached
      @cached ||= read_cached || write_cached
    end

    def cache_path = Zr.symbols_path(digest)


    def read_cached
      return unless File.exist?(cache_path)

      rows = JSON.parse(File.read(cache_path))
      return unless %w[names sites functions data description].all? { |key| rows.key?(key) }

      { symbols: Machine::Symbols.new(rows.fetch("names"), sites: rows.fetch("sites")),
        wants: { functions: rows.fetch("functions"), data: rows.fetch("data") },
        description: rows.fetch("description") }
    end

    def write_cached
      lowered
      kernel_symbols.pad!
      keep_ledger(kernel_symbols)
      defined = functions.map(&:name)
      ir = functions.grep(IR::Function)
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
      Zr.write_cache(cache_path,
                     JSON.generate({ "names" => kernel_symbols.names, "sites" => kernel_symbols.sites,
                                     "functions" => wanted_functions, "data" => wanted_data, "description" => description }))
      { symbols: kernel_symbols, wants: { functions: wanted_functions, data: wanted_data }, description: description }
    end

    # The core library's `[functions, data]`, lowered over the kernel.
    #
    # For an aarch64 build, `CoreCache` takes each file it can from an
    # earlier build, and the list then has the machine code of those files
    # (`Obj::Function`) in place of their IR. It also inlines the unit.
    def lowered
      @lowered ||= Zr.clock("core lowered") do
        @core_cache = Zr.clock("core cache: opened") { CoreCache.for(target) }
        @core_cache ? @core_cache.lower(unit, kernel_symbols, sources) : Zr.core(unit, kernel_symbols, target, sources)
      end
    end

  end

  # A program's own functions and data, and its runtime. It destructures
  # as `[functions, data, raw]` with the runtime included, for a build
  # that uses one unit for everything. `evals` is the EvalSupport that
  # the program links next to the runtime, or nil. Its JIT finds kernel
  # functions by name. `sources` maps the path of each file the program was
  # built from to the digest of the bytes that were compiled (the run
  # cache checks them); it is empty when the build does not know them.
  Program = Data.define(:runtime, :functions, :data, :evals, :sources) do
    def initialize(runtime:, functions:, data:, evals:, sources: {})
      super
    end

    def raw = runtime.raw

    def to_ary = [runtime.functions + functions, runtime.data + data, raw]
  end

  # Eval support: the compiler that a program with eval links in. zr
  # lowers it once with the runtime's symbols and assembles it into its
  # own object, so a program with eval lowers and assembles only itself.
  # Next to the object, the cache keeps the metadata that a program
  # needs: the entry of each file, its dependencies, and the symbol table
  # after it. The key is the eval digest (`Zr.eval_digest`) and the bytes
  # of each file in eval support, and the metadata lists the runtime names
  # it used. An edit to a file of eval support, to the compiler or to the
  # kernel's description builds it again, as does a runtime name it used
  # that moved; an edit to a core or kernel body does not, nor a new name,
  # because eval support calls the core only by name.
  class EvalSupport
    def initialize(runtime)
      @runtime = runtime
    end

    def target = @runtime.target

    def units = meta.fetch("units")
    def configures? = meta.fetch("configures")
    def normalizes? = meta.fetch("normalizes")
    def pretty_prints? = meta.fetch("pretty_prints")
    def irbs? = meta.fetch("irbs")
    def gems? = meta.fetch("gems")

    # A new symbol table for a program's lowering. It continues from the
    # eval support table: the runtime's names now, then eval support's own,
    # which start after the runtime's table.
    def symbols
      runtime = @runtime.symbols.names
      Machine::Symbols.new(runtime + meta.fetch("names").drop(runtime.size), sites: meta.fetch("sites"))
    end

    # The number of `using` entries that eval support itself uses. Its
    # files activate refinements when they load (the prism port gets its
    # node setters through one), and they load at the first eval. So a
    # program's entries must start after these.
    def activations = meta.fetch("activations")

    # The SHA-256 of each file in eval support (as lowered) and of each
    # file that the gem prelude loads, by path. A compiled compiler keys
    # its parse cache on these (ParseCache.parser_digests,
    # ParseCache.maker).
    def digests = meta.fetch("digests")

    # The key of eval support: the eval digest (`Zr.eval_digest`) and the
    # bytes of each file in eval support. The unit cache uses it for a
    # program that uses this symbol table.
    def key = meta.fetch("key")

    def object_path = self.class.object_path(key)

    # The metadata file of this eval support. The run cache checks it.
    def meta_path = self.class.meta_path(@runtime, kind)

    # The cache files of eval support: the object, by the key in its
    # metadata, and the metadata, by the runtime's digest and the kind
    # of eval (`jit` or `walk`). `zr-dev cache prune` reads these too.
    def self.object_path(key) = File.join(Paths.cache, "eval-#{key}.o")
    def self.meta_path(runtime, kind) = meta_file(runtime.eval_digest, kind)
    def self.meta_file(eval_digest, kind) = File.join(Paths.cache, "eval-#{eval_digest}-#{kind}.json")

    def functions = lowered.fetch(:functions)
    def data = lowered.fetch(:data)

    # Lets go of the IR once the object is written. Only the metadata stays.
    # The IR of 18,000 functions made each collection of the link that
    # follows mark it again: 11 s of a link after eval support was built.
    def release
      meta
      @lowered = nil
    end

    private

    # The eval kind of the target is part of the cache name. The eval
    # compiler (JIT) and the tree-walking interpreter contain different
    # files, so the metadata of one must never be used for the other.
    def kind = Hir::Build.eval_file(target) == Hir::Build::EVAL_COMPILER ? "jit" : "walk"

    # The cached metadata, while its files have the same bytes and the
    # runtime's table has each runtime name it used at the same id; else
    # the metadata of a new lowering.
    def meta
      @meta ||= begin
        meta = JSON.parse(File.read(meta_path)) if File.exist?(meta_path)
        current = meta && meta.fetch("key") == files_key(meta.fetch("files")) && @runtime.symbols.holds?(meta.fetch("used"))
        current ? meta : lowered.fetch(:meta)
      end
    end

    # The key of eval support: the runtime's ABI digest and the bytes of
    # each file. A build gives the bytes that it lowered (`sources`), so an edit
    # during the build cannot put old output under the new bytes' key. A
    # check of the cache reads the files as they are now.
    def files_key(files, sources = {}) = Zr.eval_files_key(@runtime.eval_digest, files, sources)

    def lowered
      @lowered ||= Zr.clock("eval support lowered") do
        Tune.heavy!
        @runtime.carry_description!
        loader = Hir::Build.eval_support(target)
        program = Hir::Program.new(Hir::Build.eval_file(target), [], Hir::Seq.new([], 0), loader.units, [], true, loader.entries)
        symbols = Machine::Symbols.new(@runtime.symbols.names, sites: @runtime.symbols.sites)
        lower = Lower.new(program, @runtime.description, symbols, entry: "zr_eval_support", target: target)
        functions = data = nil
        asked = symbols.record { functions, data = lower.run }
        runtime_size = @runtime.symbols.names.size
        files = loader.units.filter_map { |u| u.file if u.file.start_with?("/") }.uniq.sort
        sources = loader.units.each_with_object({}) { |u, h| h[u.file] ||= u.source if u.source }
        digests = (files + @runtime.gem_prelude_files).uniq.sort.to_h do |path|
          [path, Digest::SHA256.hexdigest(sources[path] || File.binread(path))]
        end
        meta = { "key" => files_key(files, sources), "files" => files, "digests" => digests,
                 "units" => loader.entries.to_h { |path, i| [path, lower.unit_entry(i)] },
                 "configures" => loader.configures?, "normalizes" => loader.normalizes?, "pretty_prints" => loader.pretty_prints?,
                 "irbs" => loader.irbs?, "gems" => loader.gems?,
                 "names" => symbols.names, "sites" => symbols.sites, "activations" => loader.activations,
                 "used" => asked.select { |_, at| at < runtime_size } }
        Zr.write_cache(meta_path, JSON.generate(meta))
        { functions: functions, data: data, meta: meta }
      end
    end
  end

  module_function

  # The bytes of source above which a program's build tunes (`Tune.heavy!`).
  # hello and a probe are far below it; the stdlib rung of the compile
  # benchmark is above.
  HEAVY_SOURCE = 256 * 1024

  # With a block, each function goes to the block when its file is
  # lowered (`Lower#run`), with the lowering's entry name. The program
  # contains the block's results.
  #
  # With `sources`, the program lists the files it was built from
  # (`Program#sources`), for the run cache.
  def program(source, file, target: Target.default, sources: false, &finish)
    rt = runtime(target)
    support = eval_support(target)
    hir = Zr.clock("hir built") { Hir.build(source, file, prebuilt: support, target: target) }
    # A large program is heavy work too (`Tune`): bundler's 1.2 MB of source
    # takes seconds to lower.
    Tune.heavy! if source.bytesize + hir.units.sum { |u| u.source.to_s.bytesize } > HEAVY_SOURCE
    # Before the lowering, which lets go of each unit's source.
    sources = sources ? built_from(source, file, hir) : {}
    symbols = hir.evals ? support.symbols : Machine::Symbols.new(rt.symbols.names, sites: rt.symbols.sites)
    # Each name already in the table has a fixed id. The link numbers all
    # other names, so a unit's code does not depend on the compile order.
    # So an earlier build's code for a unit is correct for this build.
    # The cache key includes the table that fixes the ids: the runtime's,
    # or the larger eval support table for a program with eval.
    units = finish && UnitCache.for(hir, dir: Paths.cache, runtime: rt.abi_digest, table: hir.evals ? support.key : "rt",
                                         entries: Lower.entries_of("zr_toplevel", hir.units))
    lower = Lower.new(hir, rt.description, symbols, target: target, fixed: symbols.ids.dup.freeze, units: units || nil)
    functions, data = Zr.clock(finish ? "program lowered and assembled" : "program lowered") do
      finish ? lower.run { |f| finish.call(f, lower.entry) } : lower.run
    end
    units = hir.entries.map { |path, i| [path, lower.unit_entry(i)] }
    number_symbols(data, symbols, rt.description.const_for("SYMBOL_TAG"))
    tables = load_tables(units, evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {},
                         branches: hir.branches || {}, defs: hir.defs || {}, sources: hir.evals ? support.digests : {},
                         target: target)
    Program.new(rt, functions, data + symbol_names(symbols) + tables, hir.evals && support, sources)
  end

  # The path and digest of each file that `hir` was built from: `file`,
  # with `source`, and each unit that has its own file. Empty when a
  # require stays for the run time (a file that did not exist, or a name
  # built at run time): a file that appears later would change the build,
  # and no list of paths can say which.
  def built_from(source, file, hir)
    return {} if run_time_require?([hir.body, *hir.units.map(&:body)])

    [[file, source], *hir.units.filter_map { |u| [u.file, u.source] if u.source && File.file?(u.file) }]
      .to_h { |path, bytes| [File.expand_path(path), Digest::SHA256.hexdigest(bytes)] }
  end

  REQUIRES = %i[require require_relative load].freeze

  # A require, require_relative or load of Kernel, or any autoload, that
  # the HIR left as a call.
  def run_time_require?(node)
    case node
    when Hir::Send
      kernel = node.recv.nil? || (node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Kernel && node.recv.scope.nil?)
      return true if node.name == :autoload || (kernel && REQUIRES.include?(node.name))
    when Array then return node.any? { |child| run_time_require?(child) }
    when Hir::Node then nil
    else return false
    end
    Hir.each_child(node) { |child| return true if run_time_require?(child) }
    false
  end

  # The relocation kinds that the link numbers.
  NUMBERED = %i[symid symval symbit site].freeze

  # The value that the link writes into one of those words. A site is a
  # location, not a name, so it gets the next free slot.
  def numbered(reloc, symbols, tag)
    return symbols.site if reloc.kind == :site

    id = symbols.id(reloc.symbol)
    case reloc.kind
    when :symid then id
    when :symval then Lower.symbol_value(id, tag)
    when :symbit then Lower.ivar_name_bit(id)
    end
  end

  # A unit gives a name and the link gives its number. This method sets
  # the numbers, in the order of the program's data, so a program always
  # gets the same numbers, and writes them into their words. After this,
  # no relocation of these kinds is left. Every object writer and the
  # wasm module rely on this.
  def number_symbols(data, symbols, tag)
    data.each do |d|
      waiting, keep = d.relocs.partition { |r| NUMBERED.include?(r.kind) }
      next if waiting.empty?

      bytes = d.bytes.dup
      waiting.each { |r| bytes[r.offset, 8] = [numbered(r, symbols, tag)].pack("q<") }
      d.bytes = bytes
      d.relocs = keep
    end
  end

  # The runtime for `target`, lowered once per process.
  def runtime(target = Target.default)
    (@runtimes ||= {})[target.triple] ||= Runtime.new(target)
  end

  def eval_support(target = Target.default)
    (@eval_supports ||= {})[target.triple] ||= EvalSupport.new(runtime(target))
  end

  # Writes `content` to `path` in the cache atomically, so a parallel
  # build never reads a half-written file. Writes nothing if a source
  # changed (`settled!`).
  def write_cache(path, content)
    settled!
    Paths.write_atomic(path, content)
  end

  # The core library on top of the kernel `unit`: `[functions, data]`,
  # with `zr_prelude` as the last function. The program decides if it
  # links in the compiler, so the core never requires eval support. A
  # box or an eval in the program adds it.
  def core(unit, symbols, target = Target.default, sources = {})
    functions = []
    data = []
    entries = core_files(target).map do |path|
      entry = "zr_core_#{File.basename(path, ".rb")}"
      source = sources.fetch(path) { File.read(path) }
      f, d = Lower.new(Hir.build(source, path, eval_support: false, target: target), unit, symbols, entry: entry, internal: true,
                       target: target).run
      functions.concat(f)
      data.concat(d)
      entry
    end
    f, d = Lower.new(gem_prelude(target), unit, symbols, entry: "zr_gem_prelude", kind: :top, target: target).run
    [functions.concat(f) << prelude(entries, unit), data.concat(d)]
  end

  # CRuby's gem_prelude.rb, which loads ruby's default libraries before
  # a program's first line. After it comes error_highlight's lookup for
  # a program compiled ahead of time. Boot runs it after the core
  # library loads, before the program.
  GEM_PRELUDE = File.join(Paths::VENDOR, "prelude/gem_prelude.rb")
  SPOTTED = File.join(Paths::RUNTIME, "ext/zr/error_highlight.rb")

  # The parsers that the prelude's libraries require for work that this
  # runtime does differently. error_highlight's prism_find: the compiled
  # spots replace it. syntax_suggest's search: only a program that links
  # in the compiler can get a SyntaxError.
  DEFERRED = %w[prism syntax_suggest/api].freeze

  # The gem prelude as one program for `target`.
  def gem_prelude(target = Target.default)
    loader = Hir::Build::Loader.new(Hir::Build.stdlib(target), deferred: DEFERRED,
                                                               preloaded: Hir::Build::PRELOADED - Hir::Build::GEM_PRELOADED)
    main = loader.unit("<internal:gem_prelude>", File.read(GEM_PRELUDE))
    spotted = Hir::Require.new(:hidden, "zr/error_highlight", SPOTTED, loader.add(SPOTTED), 0)
    # did_you_mean reads RbConfig, which ruby has loaded by then.
    rbconfig = loader.configures? ? [Hir::Build.rbconfig(loader)] : []
    body = Hir::Seq.new([*rbconfig, main.body, spotted], 0)
    Hir::Program.new(main.file, main.locals, body, loader.units, main.warnings, false, loader.entries, false, loader.node_ids, {})
  end

  # `zr_prelude`: boot runs each core file's toplevel in turn, and
  # stops at the first one that leaves a pending unwind.
  def prelude(entries, unit)
    f = IR::Function.new("zr_prelude", [], "i64")
    undef_value = f.iconst("i64", unit.const_for("QUNDEF"))
    entries.each do |entry|
      r = f.call_val(f.callee(entry, [], "i64"), [])
      stop = f.label
      go = f.label
      f.brif(f.icmp("eq", r, undef_value), stop, go)
      f.switch(stop)
      f.ret(r)
      f.switch(go)
    end
    f.ret(f.iconst("i64", unit.const_for("QNIL")))
    f
  end

  # The tables that `zr_load_tables` points to. A require with a computed
  # name reads them at run time. They are, in order:
  # - the count of compiled-in files, and one record (path bytes, length,
  #   toplevel) for each;
  # - as (bytes, length), one name per line: the library directories to
  #   search after $LOAD_PATH, the ruby features that this runtime has no
  #   file for, the features ruby loads before the program, and the
  #   extensions directory. Only a program with eval can require a
  #   computed name, so only such a program gets these lines;
  # - error_highlight's spots for each file (every program has them), and
  #   Coverage's tables;
  # - for a program with eval, the digest of each eval support file
  #   (`sources`, path to SHA-256). It keys its parse cache on these.
  # Nothing here comes from the build machine: a binary contains no path
  # or flag of the ruby that compiled it. `units` are `[path, entry]`
  # pairs. A unit that only stops has no path.
  def load_tables(units = [], evals: false, spots: {}, coverable: {}, branches: {}, defs: {}, sources: {},
                  target: Target.default)
    shown = ->(path) { Paths.shown(path) }
    units = units.select { |path, _| path.start_with?("/") }.map { |path, entry| [shown[path], entry] }.sort
    # A ruby feature that no root here contains, then a tab and the reason
    # if there is one. So a computed require stops for the same reason as
    # a literal one.
    uncarried = Hir::Build.missing_features(target).map { |name| [name, *Hir::Build::UNSUPPORTED_LIBRARIES[name]].join("\t") }
    names = evals ? [Hir::Build.stdlib(target).map(&shown), uncarried, Hir::Build::PRELOADED, [shown[Hir::Build::EXT]]] : [[]] * 4
    # error_highlight's spots, one file at a time: its name, a newline,
    # then its records, and a form feed before the next file.
    names << [spots.map { |file, rows| "#{shown[file]}\n#{rows}" }.join("\f")]
    # The lines that Coverage counts, one record per file: its path, its
    # line count, and the lines, tab-separated.
    names << coverable.map { |file, (count, lines)| "#{shown[file]}\t#{count}\t#{lines.uniq.join(',')}" }
    # The branches that Coverage reports, one record per file: its path,
    # then one `kind,id,root,start line,start column,end line,end column`
    # for each branch, in Coverage's order. `id` is the counter that this
    # branch increments. `root` is the index in the file of the branch's
    # root, or empty for a root.
    names << branches.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(',') }.join("\t")}" }
    # The location of each def and block in a measured file, one record
    # per file: its path, then one `id,start line,start column,end
    # line,end column` for each scope. A definition finds its record by
    # its id, and so gets its span.
    names << defs.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(',') }.join("\t")}" }
    names << sources.map { |path, digest| [shown[path], digest] }.sort.map { |path, digest| "#{path}\t#{digest}" }
    out = []
    text = ->(name, bytes) { out << Obj::Data.new(name, :text_const, "#{bytes}\0".b, align: 1) }
    rows = +"".b
    row_relocs = []
    units.each_with_index do |(path, entry), i|
      text.call("zr_unit_path_#{i}", path)
      row_relocs << Obj::Reloc.new(i * 24, :abs64, "zr_unit_path_#{i}") << Obj::Reloc.new((i * 24) + 16, :abs64, entry)
      rows << [0, path.bytesize, 0].pack("Q<3")
    end
    out << Obj::Data.new("zr_unit_rows", :data_const, rows.empty? ? "\0".b * 8 : rows, relocs: row_relocs, align: 8)
    words = [units.size, 0]
    relocs = [Obj::Reloc.new(8, :abs64, "zr_unit_rows")]
    names.each_with_index do |lines, i|
      joined = lines.join("\n")
      text.call("zr_load_names_#{i}", joined)
      relocs << Obj::Reloc.new(words.size * 8, :abs64, "zr_load_names_#{i}")
      words << 0 << joined.bytesize
    end
    out << Obj::Data.new("zr_load_table_words", :data_const, words.pack("Q<*"), relocs: relocs, align: 8)
    out << Obj::Data.new("zr_load_tables", :data_const, "\0".b * 8, relocs: [Obj::Reloc.new(0, :abs64, "zr_load_table_words")], align: 8, linkage: :export)
  end

  # `zr_symbol_names`: one (bytes, length) record per symbol id. The bytes
  # are in their own read-only objects.
  def symbol_names(symbols)
    names = symbols.names
    bytes = names.each_with_index.filter_map { |name, i| Obj::Data.new("zr_symname_#{i}", :text_const, name.b, align: 1) if name }
    table = +"".b
    relocs = []
    names.each_with_index do |name, i|
      # A pad has no bytes, and the tag SYM_PAD (runtime/kernel/symbol.rb).
      if name.nil?
        table << [0, 255 << 56].pack("Q<Q<")
        next
      end
      relocs << Obj::Reloc.new(i * 16, :abs64, "zr_symname_#{i}")
      table << [0, name.bytesize].pack("Q<Q<")
    end
    bytes + [Obj::Data.new("zr_symbol_names", :data_const, table, relocs: relocs, align: 8, linkage: :export),
             Obj::Data.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export),
             Obj::Data.new("zr_site_count", :data_const, [symbols.sites].pack("Q<"), align: 8, linkage: :export)]
  end
end
