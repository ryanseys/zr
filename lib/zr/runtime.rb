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
require_relative "clock"
require_relative "tune"
require_relative "settled"
require_relative "cache/store"
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
    attr_reader :target

    def initialize(target = Target.default)
      @target = target
    end

    # Every source, read once. The digest covers the bytes that the
    # kernel and the core were lowered from, not a later edit. So a build
    # that runs while a file changes cannot cache old output under the
    # new digest.
    def sources
      @sources ||= RuntimeSources.for(target).sources.to_h { |path| [path, File.read(path)] }
    end

    # The lowered kernel. The core's lowering and the runtime object need
    # it. A program's own lowering does not.
    def unit
      raise "the runtime's IR was released" if @released

      @unit ||= Zr.clock("kernel lowered") do
        Tune.heavy!
        Machine::Lower.new(RuntimeSources.for(target).kernel_files.map { |path| [sources.fetch(path), path] }, kernel_symbols).tap(&:run)
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
    def object_path = Cache::Store.path(:object, digest)

    def digest
      # The target is the first input, so two targets never share build
      # output. Each path is an input with its bytes, because the runtime
      # object contains the core's file names; so two checkouts never
      # share one. A build with a path root (`Paths.root`) writes
      # different names, so the root is also an input.
      @digest ||= Zr.clock("runtime digest") do
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
    def gem_prelude_path = RuntimeSources.gem_prelude_list(digest_of(sources.keys))

    def gem_prelude_files
      @gem_prelude_files ||= begin
        path = gem_prelude_path
        files = JSON.parse(File.read(path)) if File.exist?(path)
        unless files&.all? { |file| File.file?(file) }
          files = [Layout::GEM_PRELUDE, *Zr.gem_prelude(target).units.map(&:file).select { |file| File.file?(file) }].uniq.sort
          Cache::Store.write_file(path, JSON.generate(files))
        end
        files
      end
    end

    def digest_of(files) = Digests.sources(target, files, sources)

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
    # The `Cache::Lowering::Core` of this build's lowering, or nil.
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

    # The kernel's description as eval support carries it: the source of
    # `zr_description.rb`, which `require "zr_description"` finds
    # (lib/zr/eval.rb, `Hir::Build::DESCRIPTION`). The JIT of a binary
    # lowers eval'd code against it, not against the kernel. zr makes it
    # from this runtime's description, so it is never out of date and
    # nobody commits it.
    def carried_text = @carried_text ||= Machine::Description.carried(cached.fetch(:description))

    # `RuntimeSources#abi_digest`: what a program's units and eval support's
    # code take from this runtime. It reads the symbol table's cache, which
    # it makes first.
    def abi_digest
      @abi_digest ||= (cached && RuntimeSources.for(target).abi_digest(digest)) || raise("no symbol table for runtime #{digest}")
    end

    # `RuntimeSources#eval_digest`: what eval support's object takes from
    # this runtime: its ABI and the table that numbers eval support's names.
    def eval_digest
      @eval_digest ||= (cached && RuntimeSources.for(target).eval_digest(digest)) || raise("no symbol table for runtime #{digest}")
    end

    # The ids that code outside the kernel has as immediates: the kernel's
    # names, name to id. Each other name is a pool word that the link
    # numbers (`Lower#fixed_id`).
    def fixed_ids
      @fixed_ids ||= symbols.names.first(cached.fetch(:kernel)).each_with_index.to_h { |name, i| [name, i] }.freeze
    end

    private

    # The kernel's own symbol table: the names of its `Machine.id`s, in the
    # order of its files. Only these ids are in code outside the kernel.
    def kernel_symbols
      @kernel_symbols ||= Machine::Symbols.new
    end

    # The symbol table, the wanted symbols and the kernel's description.
    # They come from the cache, or from lowering the kernel and the core
    # (then cached). A cache file with a missing field is a miss.
    def cached
      @cached ||= read_cached || write_cached
    end

    def cache_path = RuntimeSources.symbols_path(digest)

    def read_cached
      return unless File.exist?(cache_path)

      rows = JSON.parse(File.read(cache_path))
      return unless %w[names sites kernel functions data description].all? { |key| rows.key?(key) }

      { symbols: Machine::Symbols.new(rows.fetch("names"), sites: rows.fetch("sites")), kernel: rows.fetch("kernel"),
        wants: { functions: rows.fetch("functions"), data: rows.fetch("data") },
        description: rows.fetch("description") }
    end

    def write_cached
      Tune.heavy!
      Zr.announce("the zr runtime", target)
      lowered
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
    def lowered
      @lowered ||= Zr.clock("core lowered") do
        @core_cache = Zr.clock("core cache: opened") { Cache::Lowering::Core.for(target) }
        fixed = unit.symbols.ids.dup.freeze
        functions, data = @core_cache ? @core_cache.lower(unit, fixed, sources) : Zr.core(unit, fixed, target, sources)
        @table = Machine::Symbols.new(kernel_symbols.names, sites: kernel_symbols.sites)
        [functions, Zr.numbered_data(data, @table, unit.const_for("SYMBOL_TAG"))]
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
  # `gems` are the manifest's rows (lib/zr/manifest.rb): the gems that the
  # program's files come from.
  Program = Data.define(:runtime, :functions, :data, :evals, :sources, :gems) do
    def initialize(runtime:, functions:, data:, evals:, sources: {}, gems: [])
      super
    end

    def raw = runtime.raw

    def to_ary = [runtime.functions + functions, runtime.data + data, raw]
  end

  # Eval support: the compiler that a program with eval links in. zr
  # lowers it once and assembles it into its own object, so a program with
  # eval lowers and assembles only itself. Next to the object, the cache
  # keeps the metadata that a program needs: the entry of each file, its
  # dependencies, and the symbol table after it. The key is the eval
  # digest (`RuntimeSources#eval_digest`) and the bytes of each file in
  # eval support.
  #
  # Its code has only the kernel's ids, so the code of each file depends on
  # the compiler, the kernel's description and the file
  # (`Cache::Lowering::EvalSupport` keeps it). Only its data, whose pool
  # words the runtime's table numbers, depends on the core: a core edit
  # writes the object again from the kept code.
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
    # its parse cache on these (`Cache::Parse.parser_digests`,
    # `Cache::Parse.maker`).
    def digests = meta.fetch("digests")

    # The key of eval support's object (`Digests.eval_key`): the key of its
    # files (the eval digest and the bytes of each file), and the symbol
    # table that numbers its data. The object has this name.
    def key = meta.fetch("key")

    def object_path = self.class.object_path(key)

    # The metadata file of this eval support. The run cache checks it.
    def meta_path = self.class.meta_path(@runtime, kind)

    # The cache files of eval support: the object, by the key in its
    # metadata, and the metadata, by the runtime's digest and the kind
    # of eval (`jit` or `walk`). `zr-dev cache prune` reads these too.
    def self.object_path(key) = Cache::Store.path(:object, key)
    def self.meta_path(runtime, kind) = meta_file(runtime.eval_digest, kind)
    def self.meta_file(eval_digest, kind) = Cache::Store.path(:meta, "#{eval_digest}-eval-#{kind}")

    def functions = lowered.fetch(:functions)
    def data = lowered.fetch(:data)

    # Lets go of the IR once the object is written. Only the metadata stays.
    # The IR of 18,000 functions made each collection of the link that
    # follows mark it again: 11 s of a link after eval support was built.
    def release
      meta
      @lowered = @cache = nil
    end

    # The `Cache::Lowering::EvalSupport` of this build's lowering, or nil.
    def cache
      lowered
      @cache
    end

    # The eval kind of the target is part of the cache name. The eval
    # compiler (JIT) and the tree-walking interpreter contain different
    # files, so the metadata of one must never be used for the other.
    def kind = Hir::Build.eval_file(target) == Hir::Build::EVAL_COMPILER ? "jit" : "walk"

    private

    # The cached metadata, while its files have the same bytes; else the
    # metadata of a new lowering. Its path has the runtime's eval digest,
    # so another runtime table has other metadata.
    def meta
      @meta ||= begin
        meta = JSON.parse(File.read(meta_path)) if File.exist?(meta_path)
        current = meta && meta["files_key"] == files_key(meta.fetch("files"), {}, meta.fetch("absent", []))
        current ? meta : lowered.fetch(:meta)
      end
    end

    # The key of eval support: the runtime's eval digest and the bytes of
    # each file. A build gives the bytes that it lowered (`sources`), so an edit
    # during the build cannot put old output under the new bytes' key. A
    # check of the cache reads the files as they are now.
    def files_key(files, sources = {}, absent = []) = Digests.eval_files_key(@runtime.eval_digest, files, sources, absent)

    def lowered
      @lowered ||= Zr.clock("eval support lowered") do
        Tune.heavy!
        Zr.announce("eval support (the compiler in a program that calls eval)", target)
        loader = Hir::Build.eval_support(target)
        program = Hir::Program.new(Hir::Build.eval_file(target), [], Hir::Seq.new([], 0), loader.units, [], true, loader.entries)
        lower = Lower.new(program, @runtime.description, nil, entry: "zr_eval_support", target: target, fixed: @runtime.fixed_ids)
        @cache = Cache::Lowering::EvalSupport.for(target, kind)
        functions, data = @cache ? @cache.lower(lower, @runtime.description) : lower.run
        # Eval support's names come after the runtime's.
        symbols = Machine::Symbols.new(@runtime.symbols.names, sites: @runtime.symbols.sites)
        data = Zr.numbered_data(data, symbols, @runtime.description.const_for("SYMBOL_TAG"))
        files = loader.units.filter_map { |u| u.file if u.file.start_with?("/") }.uniq.sort
        sources = loader.units.each_with_object({}) { |u, h| h[u.file] ||= u.source if u.source }
        digests = (files + @runtime.gem_prelude_files).uniq.sort.to_h do |path|
          [path, Digest::SHA256.hexdigest(sources[path] || File.binread(path))]
        end
        # A file that appears where a stopped feature would be makes this
        # lowering stale, though no file that it read changed.
        absent = loader.stopped.uniq.sort.flat_map { |feature| Hir::Build.stdlib(target).map { |root| File.join(root, "#{feature}.rb") } }
        read = files_key(files, sources, absent)
        meta = { "key" => Digests.eval_key(read, symbols.names, symbols.sites), "files_key" => read, "files" => files, "absent" => absent, "digests" => digests,
                 "units" => loader.entries.to_h { |path, i| [path, lower.unit_entry(i)] },
                 "configures" => loader.configures?, "normalizes" => loader.normalizes?, "pretty_prints" => loader.pretty_prints?,
                 "irbs" => loader.irbs?, "gems" => loader.gems?,
                 "names" => symbols.names, "sites" => symbols.sites, "activations" => loader.activations }
        Cache::Store.write_file(meta_path, JSON.generate(meta))
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
  #
  # `gem_set` is the GemSet whose gems come before zr's standard library
  # (lib/zr/gem_set.rb), or nil. `gate` stops the build at a require that
  # nothing has in the program's own files (`Hir::Build#gate!`).
  def program(source, file, target: Target.default, sources: false, gem_set: nil, gate: false, &finish)
    rt = runtime(target)
    support = eval_support(target)
    hir = Zr.clock("hir built") { Hir.build(source, file, prebuilt: support, target: target, gem_set: gem_set, gate: gate) }
    gem_conflicts!(hir, support, gem_set, target) if hir.evals && gem_set && !gem_set.empty?
    # A large program is heavy work too (`Tune`): bundler's 1.2 MB of source
    # takes seconds to lower.
    Tune.heavy!(restart: false) if source.bytesize + hir.units.sum { |u| u.source.to_s.bytesize } > HEAVY_SOURCE
    # Before the lowering, which lets go of each unit's source.
    sources = sources ? built_from(source, file, hir) : {}
    gems = Manifest.of_program(hir, support, gem_set)
    symbols = hir.evals ? support.symbols : Machine::Symbols.new(rt.symbols.names, sites: rt.symbols.sites)
    # Only the kernel's names have fixed ids. The link numbers all other
    # names from `symbols`, so a unit's code does not depend on the compile
    # order or on the core. So an earlier build's code for a unit is
    # correct for this build while the kernel's ABI is the same.
    units = finish && Cache::Unit.for(hir, runtime: rt.abi_digest, entries: Lower.entries_of("zr_toplevel", hir.units))
    lower = Lower.new(hir, rt.description, symbols, target: target, fixed: rt.fixed_ids, units: units || nil)
    functions, data = Zr.clock(finish ? "program lowered and assembled" : "program lowered") do
      finish ? lower.run { |f| yield(f, lower.entry) } : lower.run
    end
    units = hir.entries.map { |path, i| [path, lower.unit_entry(i)] }
    number_symbols(data, symbols, rt.description.const_for("SYMBOL_TAG"))
    tables = load_tables(units, evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {},
                         branches: hir.branches || {}, defs: hir.defs || {}, sources: hir.evals ? support.digests : {},
                         target: target, gem_roots: gem_set ? gem_set.gems.reject(&:refusal).flat_map(&:roots) : [],
                         manifest: Manifest.bytes(gems, target))
    Program.new(rt, functions, data + symbol_names(symbols) + tables, hir.evals && support, sources, gems)
  end

  # A program with eval carries eval support, which has zr's own copy of
  # some libraries (fileutils, pp, irb, reline, rubygems and others). A
  # file of a gem in the GemSet with the same feature name would load a
  # second copy beside it, where ruby loads one. So such a build stops.
  def gem_conflicts!(hir, support, gem_set, target)
    stdlib = Hir::Build.stdlib(target)
    carried = support.units.keys.filter_map do |path|
      root = stdlib.find { |dir| path.start_with?("#{dir}/") }
      path.delete_prefix("#{root}/") if root
    end.to_h { |feature| [feature, true] }
    hir.units.each do |unit|
      next unless unit.file

      gem_set.gems.each do |gem|
        root = gem.roots.find { |dir| unit.file.start_with?("#{dir}/") } or next
        feature = unit.file.delete_prefix("#{root}/")
        next unless carried[feature]

        raise Refused, "#{feature} of #{gem.name} #{gem.version} (#{gem.source}): this program uses eval, so it carries " \
                       "zr's own #{feature}, and ruby loads only one copy. Use ruby #{RUBY}'s #{gem.name} " \
                       "(remove the override), or remove the eval"
      end
    end
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

  # `number_symbols` on copies: the data with each number written, where
  # `data` keeps its relocations. A cache keeps a piece's data unnumbered,
  # so that another table can number it again.
  def numbered_data(data, symbols, tag)
    data.map { |d| d.relocs.any? { |r| NUMBERED.include?(r.kind) } ? d.dup : d }.tap { |copies| number_symbols(copies, symbols, tag) }
  end

  # The runtime for `target`, lowered once per process.
  def runtime(target = Target.default)
    (@runtimes ||= {})[target.triple] ||= Runtime.new(target)
  end

  def eval_support(target = Target.default)
    (@eval_supports ||= {})[target.triple] ||= EvalSupport.new(runtime(target))
  end

  # Says on stderr, once in a process, that a build of `what` for
  # `target` starts, which fills the cache for later builds. The first
  # build of an installed zr would otherwise run for minutes with no
  # output. A checkout says it only on a terminal: a test or a tool
  # that reads stderr gets nothing more. ZR_TIMING prints its own lines.
  def announce(what, target)
    return if Config.current.timing? || (Paths.checkout? && !$stderr.tty?)
    return if (@announced ||= {}).key?([what, target.triple])

    @announced[[what, target.triple]] = true
    warn "zr: building #{what} for #{target.triple}. This occurs one time and takes some minutes."
  end

  # The core library on top of the kernel `unit`: `[functions, data]`,
  # with `zr_prelude` as the last function. The program decides if it
  # links in the compiler, so the core never requires eval support. A
  # box or an eval in the program adds it. `fixed` are the kernel's ids;
  # the data leaves every other name to the link (`numbered_data`).
  def core(unit, fixed, target = Target.default, sources = {})
    functions = []
    data = []
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
  def core_entry(path) = "zr_core_#{File.basename(path, ".rb")}"

  # `[functions, data]` of one core file over the kernel `unit`, with the
  # kernel's ids `fixed`.
  def lower_core_file(path, source, unit, fixed, target)
    Lower.new(Hir.build(source, path, eval_support: false, target: target), unit, nil, entry: core_entry(path), internal: true,
                                                                                 target: target, fixed: fixed).run
  end

  # `[functions, data]` of the gem prelude's program `hir`.
  def lower_gem_prelude(hir, unit, fixed, target)
    Lower.new(hir, unit, nil, entry: GEM_PRELUDE_ENTRY, kind: :top, target: target, fixed: fixed).run
  end

  GEM_PRELUDE_ENTRY = "zr_gem_prelude"

  # CRuby's gem_prelude.rb, which loads ruby's default libraries before
  # a program's first line. After it comes error_highlight's lookup for
  # a program compiled ahead of time. Boot runs it after the core
  # library loads, before the program.
  SPOTTED = File.join(Layout::RUNTIME_LIB, "zr/error_highlight.rb")

  # The parsers that the prelude's libraries require for work that this
  # runtime does differently. error_highlight's prism_find: the compiled
  # spots replace it. syntax_suggest's search: only a program that links
  # in the compiler can get a SyntaxError.
  DEFERRED = %w[prism syntax_suggest/api].freeze

  # The gem prelude as one program for `target`.
  def gem_prelude(target = Target.default)
    loader = Hir::Build::Loader.new(Hir::Build.stdlib(target), deferred: DEFERRED,
                                                               preloaded: Hir::Build::PRELOADED - Hir::Build::GEM_PRELOADED)
    main = loader.unit("<internal:gem_prelude>", File.read(Layout::GEM_PRELUDE))
    spotted = Hir::Require.new(:hidden, "zr/error_highlight", SPOTTED, loader.add(SPOTTED), 0)
    # did_you_mean reads RbConfig, which ruby has loaded by then.
    rbconfig = loader.configures? ? [Hir::Build.rbconfig(loader)] : []
    body = Hir::Seq.new([*rbconfig, main.body, spotted], 0)
    Hir::Program.new(main.file, main.locals, body, loader.units, main.warnings, false, loader.entries, false, main.node_ids, {})
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
  #   (`sources`, path to SHA-256). It keys its parse cache on these;
  # - the gem manifest.
  # Nothing here comes from the build machine: a binary contains no path
  # or flag of the ruby that compiled it. `units` are `[path, entry]`
  # pairs. A unit that only stops has no path.
  #
  # `gem_roots` are the roots of the build's GemSet. A program with eval
  # searches them right after ruby's own library, as its build did, so a
  # computed require finds the same gem.
  #
  # `manifest` is the gem manifest (lib/zr/manifest.rb), or nil. It is the
  # last text. `zr inspect` finds it in the binary, and rubygems in the
  # program reads its gems (runtime/lib/zr/gem_manifest.rb).
  def load_tables(units = [], evals: false, spots: {}, coverable: {}, branches: {}, defs: {}, sources: {},
                  target: Target.default, gem_roots: [], manifest: nil)
    shown = ->(path) { Paths.shown(path) }
    units = units.select { |path, _| path.start_with?("/") }.map { |path, entry| [shown[path], entry] }.sort
    # A ruby feature that no root here contains, then a tab and the reason
    # if there is one. So a computed require stops for the same reason as
    # a literal one.
    uncarried = Hir::Build.missing_features(target).map { |name| [name, *Hir::Build::UNSUPPORTED_LIBRARIES[name]].join("\t") }
    # Only a build reads the roots. An eval in a program (evals false)
    # builds its tables here too, and must not read them: they are the
    # build machine's directories.
    names = if evals
              pure = Hir::Build.pure
              roots = Hir::Build.stdlib(target) - [pure]
              [[pure, *gem_roots, *roots].map(&shown), uncarried, Hir::Build::PRELOADED, [shown[Layout::EXT]]]
            else
              [[]] * 4
            end
    # error_highlight's spots, one file at a time: its name, a newline,
    # then its records, and a form feed before the next file.
    names << [spots.map { |file, rows| "#{shown[file]}\n#{rows}" }.join("\f")]
    # The lines that Coverage counts, one record per file: its path, its
    # line count, and the lines, tab-separated.
    names << coverable.map { |file, (count, lines)| "#{shown[file]}\t#{count}\t#{lines.uniq.join(",")}" }
    # The branches that Coverage reports, one record per file: its path,
    # then one `kind,id,root,start line,start column,end line,end column`
    # for each branch, in Coverage's order. `id` is the counter that this
    # branch increments. `root` is the index in the file of the branch's
    # root, or empty for a root.
    names << branches.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(",") }.join("\t")}" }
    # The location of each def and block in a measured file, one record
    # per file: its path, then one `id,start line,start column,end
    # line,end column` for each scope. A definition finds its record by
    # its id, and so gets its span.
    names << defs.map { |file, rows| "#{shown[file]}\t#{rows.map { |row| row.join(",") }.join("\t")}" }
    names << sources.map { |path, digest| [shown[path], digest] }.sort.map { |path, digest| "#{path}\t#{digest}" }
    names << [manifest.to_s.chomp]
    out = []
    text = ->(name, bytes) { out << Obj::Datum.new(name, :text_const, "#{bytes}\0".b, align: 1) }
    rows = +"".b
    row_relocs = []
    units.each_with_index do |(path, entry), i|
      text.call("zr_unit_path_#{i}", path)
      row_relocs << Obj::Reloc.new(i * 24, :abs64, "zr_unit_path_#{i}") << Obj::Reloc.new((i * 24) + 16, :abs64, entry)
      rows << [0, path.bytesize, 0].pack("Q<3")
    end
    out << Obj::Datum.new("zr_unit_rows", :data_const, rows.empty? ? "\0".b * 8 : rows, relocs: row_relocs, align: 8)
    words = [units.size, 0]
    relocs = [Obj::Reloc.new(8, :abs64, "zr_unit_rows")]
    names.each_with_index do |lines, i|
      joined = lines.join("\n")
      text.call("zr_load_names_#{i}", joined)
      relocs << Obj::Reloc.new(words.size * 8, :abs64, "zr_load_names_#{i}")
      words << 0 << joined.bytesize
    end
    out << Obj::Datum.new("zr_load_table_words", :data_const, words.pack("Q<*"), relocs: relocs, align: 8)
    out << Obj::Datum.new("zr_load_tables", :data_const, "\0".b * 8, relocs: [Obj::Reloc.new(0, :abs64, "zr_load_table_words")], align: 8, linkage: :export)
  end

  # `zr_symbol_names`: one (bytes, length) record per symbol id. The bytes
  # of all names are one read-only object, and each record points into it
  # (an addend). An object for each name made a program that evals carry
  # 18,000 more data items and symbols, which each link read, laid out
  # and wrote again.
  def symbol_names(symbols)
    names = symbols.names
    all = +"".b
    table = +"".b
    relocs = []
    names.each_with_index do |name, i|
      # A pad has no bytes, and the tag SYM_PAD (runtime/kernel/symbol.rb).
      if name.nil?
        table << [0, 255 << 56].pack("Q<Q<")
        next
      end
      relocs << Obj::Reloc.new(i * 16, :abs64, "zr_symname_bytes", all.bytesize)
      table << [0, name.bytesize].pack("Q<Q<")
      all << name.b
    end
    [Obj::Datum.new("zr_symname_bytes", :text_const, all.empty? ? "\0".b : all, align: 1),
     Obj::Datum.new("zr_symbol_names", :data_const, table, relocs: relocs, align: 8, linkage: :export),
     Obj::Datum.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export),
     Obj::Datum.new("zr_site_count", :data_const, [symbols.sites].pack("Q<"), align: 8, linkage: :export)]
  end
end
