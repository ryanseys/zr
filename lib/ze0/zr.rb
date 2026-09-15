# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "paths"
require_relative "target"
require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "zr/lower"

module Ze0
  # The `zr` runtime: the kernel files, the core library written in
  # Ruby over them, and the data the compiler lays out beside them.
  module Zr
    # The core library files, in the order their toplevels run: a module
    # before the classes that include it. An `os/` name is the OS layer's
    # file of that name, under rt/core/os/<os>/: the numbers each OS
    # gives the constants the portable file after it goes on to use, in
    # the order ruby defines them.
    CORE_NAMES = %w[module warning encodings transcode cjk exception enumerable enumerator comparable integer bignum array hash range struct unicode string converter kernel float proc binding format os/errno os/io_constants io io_buffer os/process_constants process signal env os/file_constants file argf data os/clock_constants gc random thread trace_point monitor time set ractor marshal pack regexp_pattern regexp pathname rational complex objectspace rubyvm box].freeze

    # Where the runtime's built forms live, keyed on the digest of
    # everything they depend on: the runtime sources and the compiler.
    # A stage of the bootstrap takes its own, so that it emits the
    # runtime itself instead of reading a form another stage wrote.
    CACHE = Paths::CACHE

    # The kernel and the core library, lowered once per process, and as
    # little of them as a build needs: a program's lowering reads the
    # kernel unit and the symbol table; only a build with no cached
    # runtime object reads the core's functions and data.
    class Runtime
      attr_reader :unit, :target

      def initialize(target = Target.default)
        @target = target
        @unit = Machine.unit(Zr.kernel_files(target), symbols: kernel_symbols)
      end

      def raw = unit.raw

      def digest
        # The target goes in first: two targets never share a built form.
        # A path goes in beside its bytes: the runtime object carries the
        # core's file names, so two checkouts never share one either.
        @digest ||= digest_of(Zr.sources(target) + gem_prelude_files)
      end

      # The files the gem prelude loads, which only its loader knows:
      # read from the cache under the digest of everything else, or
      # found by building the prelude's HIR. A change to one of them that
      # reaches another file changes the digest, and the list is found
      # again.
      def gem_prelude_files
        @gem_prelude_files ||= begin
          path = File.join(CACHE, "gem-prelude-#{digest_of(Zr.sources(target))}.json")
          files = JSON.parse(File.read(path)) if File.exist?(path)
          unless files&.all? { |file| File.file?(file) }
            files = [GEM_PRELUDE, *Zr.gem_prelude(target).units.map(&:file).select { |file| File.file?(file) }].uniq.sort
            Zr.write_cache(path, JSON.generate(files))
          end
          files
        end
      end

      def digest_of(files)
        Digest::SHA256.new.tap do |d|
          d << target.triple << "\0"
          files.each { |path| d << path << "\0" << File.binread(path) }
        end.hexdigest
      end

      # The symbol table after the core library: from the cache when the
      # core was lowered before under this digest.
      def symbols
        cached.fetch(:symbols)
      end

      # The function and data symbols the runtime names and does not
      # define, for a program to define: `{ functions:, data: }`.
      def wants
        cached.fetch(:wants)
      end

      def functions = unit.functions + lowered.first

      def data = unit.data + lowered.last

      private

      def kernel_symbols
        @kernel_symbols ||= Machine::Symbols.new
      end

      # The symbol table and the wanted symbols, read from the cache or
      # found by lowering the core and then cached.
      def cached
        @cached ||= begin
          path = File.join(CACHE, "symbols-#{digest}.json")
          if File.exist?(path)
            rows = JSON.parse(File.read(path))
            { symbols: Machine::Symbols.new(rows.fetch("names"), sites: rows.fetch("sites")),
              wants: { functions: rows.fetch("functions"), data: rows.fetch("data") } }
          else
            lowered
            defined = functions.map(&:name)
            wanted_functions = (functions.flat_map { |f| f.callees.map(&:symbol) }.uniq - defined).sort
            wanted_data = (functions.flat_map { |f| f.globals.reject(&:colocated).map(&:symbol) }.uniq - data.map(&:name)).sort
            Zr.write_cache(path, JSON.generate({ "names" => kernel_symbols.ids.keys, "sites" => kernel_symbols.sites,
                                                 "functions" => wanted_functions, "data" => wanted_data }))
            { symbols: kernel_symbols, wants: { functions: wanted_functions, data: wanted_data } }
          end
        end
      end

      # The core library's `[functions, data]`, lowered over the kernel.
      def lowered
        @lowered ||= Zr.core(unit, kernel_symbols, target)
      end
    end

    # A program's own functions and data over its runtime. Destructures
    # as `[functions, data, raw]` with the runtime included, for a build
    # that takes everything as one unit. `evals` says the program carries
    # the compiler, whose JIT finds kernel functions by name: it is the
    # Road the program links beside the runtime, or nil.
    Program = Struct.new(:runtime, :functions, :data, :evals) do
      def raw = runtime.raw

      def to_ary = [runtime.functions + functions, runtime.data + data, raw]
    end

    # The compiler a program that evals carries, lowered once over the
    # runtime's symbols and assembled into an object of its own, so a
    # program that evals lowers and assembles only itself. The cache keeps,
    # beside the object, what a program needs to know of it: the entry of
    # each file it holds, what it needs beside it, and the symbol table
    # after it. The key is the runtime's digest and the bytes of every
    # file the road holds, so an edit to any of them builds it again.
    class Road
      def initialize(runtime)
        @runtime = runtime
      end

      def target = @runtime.target

      def units = meta.fetch("units")
      def configures? = meta.fetch("configures")
      def normalizes? = meta.fetch("normalizes")
      def pretty_prints? = meta.fetch("pretty_prints")
      def gems? = meta.fetch("gems")

      # A fresh table to lower a program over, which goes on from the
      # road's.
      def symbols = Machine::Symbols.new(meta.fetch("names"), sites: meta.fetch("sites"))

      def object_path = File.join(CACHE, "road-#{meta.fetch("key")}.o")

      def functions = lowered.fetch(:functions)
      def data = lowered.fetch(:data)

      private

      def meta_path = File.join(CACHE, "road-#{@runtime.digest}.json")

      def meta
        @meta ||= begin
          meta = JSON.parse(File.read(meta_path)) if File.exist?(meta_path)
          meta && meta.fetch("key") == files_key(meta.fetch("files")) ? meta : lowered.fetch(:meta)
        end
      end

      def files_key(files)
        Digest::SHA256.new.tap do |d|
          d << @runtime.digest
          files.each { |path| d << path << "\0" << (File.exist?(path) ? File.binread(path) : "") }
        end.hexdigest
      end

      def lowered
        @lowered ||= begin
          loader = Hir::Build.road(target)
          program = Hir::Program.new(Hir::Build::EVAL_ROAD, [], Hir::Seq.new([], 0), loader.units, [], true, loader.entries)
          symbols = Machine::Symbols.new(@runtime.symbols.ids.keys, sites: @runtime.symbols.sites)
          lower = Lower.new(program, @runtime.unit, symbols, entry: "zr_road")
          functions, data = lower.run
          files = loader.units.filter_map { |u| u.file if u.file.start_with?("/") }.uniq.sort
          meta = { "key" => files_key(files), "files" => files,
                   "units" => loader.entries.to_h { |path, i| [path, lower.unit_entry(i)] },
                   "configures" => loader.configures?, "normalizes" => loader.normalizes?, "pretty_prints" => loader.pretty_prints?, "gems" => loader.gems?,
                   "names" => symbols.ids.keys, "sites" => symbols.sites }
          Zr.write_cache(meta_path, JSON.generate(meta))
          { functions: functions, data: data, meta: meta }
        end
      end
    end

    module_function

    # Given a block, each function goes to it as soon as its file is
    # lowered (`Lower#run`), with the names the lowering spells from, and
    # the program holds what the block answers.
    def program(source, file, target: Target.default, &finish)
      rt = runtime(target)
      carried = road(target)
      hir = Hir.build(source, file, road: carried, target: target)
      symbols = hir.evals ? carried.symbols : Machine::Symbols.new(rt.symbols.ids.keys, sites: rt.symbols.sites)
      lower = Lower.new(hir, rt.unit, symbols)
      functions, data = finish ? lower.run { |f| finish.call(f, lower.entry) } : lower.run
      units = hir.entries.map { |path, i| [path, lower.unit_entry(i)] }
      tables = load_tables(units, evals: hir.evals, spots: hir.spots || {}, target: target)
      Program.new(rt, functions, data + symbol_names(symbols) + tables, hir.evals && carried)
    end

    # The runtime for `target`, lowered once per process.
    def runtime(target = Target.default)
      (@runtimes ||= {})[target.triple] ||= Runtime.new(target)
    end

    def road(target = Target.default)
      (@roads ||= {})[target.triple] ||= Road.new(runtime(target))
    end

    # The kernel files `target`'s runtime is lowered from: the portable
    # kernel, then its OS layer, then its architecture layer.
    def kernel_files(target = Target.default)
      Dir[File.join(Paths::RT, "kernel/*.rb")].sort +
        Dir[File.join(Paths::RT, "kernel/os/#{target.os_layer}/*.rb")].sort +
        Dir[File.join(Paths::RT, "kernel/arch/#{target.arch_layer}/*.rb")].sort
    end

    # The core library files for `target`, in the order their toplevels
    # run.
    def core_files(target = Target.default)
      layer = target.os_layer
      CORE_NAMES.map do |name|
        File.join(Paths::RT, name.start_with?("os/") ? "core/os/#{layer}/#{name.delete_prefix("os/")}.rb" : "core/#{name}.rb")
      end
    end

    # The files `target`'s runtime is lowered from, and the compiler that
    # lowers them.
    def sources(target = Target.default)
      kernel_files(target) + core_files(target) + Dir[File.join(__dir__, "**/*.rb")].sort
    end

    # `content` at `path` under the cache, written whole: a parallel
    # build never reads a half-written file.
    def write_cache(path, content)
      FileUtils.mkdir_p(CACHE)
      Dir.mktmpdir("ze0-rt-", CACHE) do |work|
        fresh = File.join(work, File.basename(path))
        File.binwrite(fresh, content)
        File.rename(fresh, path)
      end
      path
    end

    # The core library over the kernel `unit`: `[functions, data]`, the
    # functions ending with `zr_prelude`. Whether a program carries the
    # compiler is the program's own question, so the core never asks for
    # the eval road: a box or an eval brings it with the program.
    def core(unit, symbols, target = Target.default)
      functions = []
      data = []
      entries = core_files(target).map do |path|
        entry = "zr_core_#{File.basename(path, ".rb")}"
        f, d = Lower.new(Hir.build(File.read(path), path, road: false, target: target), unit, symbols, entry: entry, internal: true).run
        functions.concat(f)
        data.concat(d)
        entry
      end
      f, d = Lower.new(gem_prelude(target), unit, symbols, entry: "zr_gem_prelude", kind: :top).run
      [functions.concat(f) << prelude(entries, unit), data.concat(d)]
    end

    # CRuby's gem_prelude.rb, which loads the libraries ruby carries
    # before a program's first line, and after it error_highlight's
    # lookup for a program compiled ahead of time. Boot runs it once the
    # core library stands, before the program.
    GEM_PRELUDE = File.join(Paths::VENDOR, "prelude/gem_prelude.rb")
    SPOTTED = File.join(Paths::RT, "ext/ze0/error_highlight.rb")

    # The parsers the prelude's libraries require for work this runtime
    # does another way: error_highlight's prism_find, which the compiled
    # spots stand in for, and syntax_suggest's search, which only a
    # program that carries the compiler can meet a SyntaxError for.
    DEFERRED = %w[prism syntax_suggest/api].freeze


    # A wasm32 module has no regexp engine, which those libraries and
    # rbconfig reach for as they load, so it carries none of them.
    def gem_prelude(target = Target.default)
      return Hir::Program.new("<internal:gem_prelude>", [], Hir::Seq.new([], 0), [], [], false, {}, false, {}, {}) if target.arch == :wasm32

      loader = Hir::Build::Loader.new(Hir::Build.stdlib(target), deferred: DEFERRED,
                                                                 preloaded: Hir::Build::PRELOADED - Hir::Build::GEM_PRELOADED)
      main = loader.unit("<internal:gem_prelude>", File.read(GEM_PRELUDE))
      spotted = Hir::Require.new(:eval_road, "ze0/error_highlight", SPOTTED, loader.add(SPOTTED), 0)
      # did_you_mean reads RbConfig, which ruby has loaded by then.
      rbconfig = loader.configures? ? [Hir::Build.rbconfig(loader)] : []
      body = Hir::Seq.new([*rbconfig, main.body, spotted], 0)
      Hir::Program.new(main.file, main.locals, body, loader.units, main.warnings, false, loader.entries, false, loader.node_ids, {})
    end

    # `zr_prelude`: boot runs each core file's toplevel in turn, and
    # stops at the first that leaves a signal pending.
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

    # What a require whose name the program computes reads when it runs,
    # behind the one word `zr_load_tables` points with: the count of files
    # compiled in and their rows, (path bytes, length, toplevel) each;
    # then, as (bytes, length), the library directories to search after
    # $LOAD_PATH, the features ruby carries that this runtime has no file
    # for, the features ruby loaded before the program, and the directory
    # of native halves, one name a line. Only a program that carries the
    # compiler can reach a require by a computed name, so only one of
    # those gets the lines. Last come error_highlight's spots for each
    # file and the compiling ruby's install layout, which every program
    # carries. `units` are `[path, entry]`
    # pairs; a unit that only stops has no path.
    def load_tables(units = [], evals: false, spots: {}, target: Target.default)
      units = units.select { |path, _| path.start_with?("/") }.sort
      names = evals ? [Hir::Build.stdlib(target), Hir::Build.missing_features(target), Hir::Build::PRELOADED, [Hir::Build::EXT]] : [[]] * 4
      # error_highlight's spots, a file at a time: its name, a newline,
      # then its rows, and a form feed before the next file.
      names << [spots.map { |file, rows| "#{file}\n#{rows}" }.join("\f")]
      # The install layout of the ruby that compiles the program, which
      # RbConfig names as the program's own, a `key=value` line each.
      names << (defined?(::RbConfig) ? %w[prefix ENABLE_SHARED].filter_map { |key| "#{key}=#{::RbConfig::CONFIG[key]}" if ::RbConfig::CONFIG[key] } : [])
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

    # `zr_symbol_names`: a row of (bytes, length) per symbol id, the bytes
    # in their own read-only objects.
    def symbol_names(symbols)
      names = symbols.ids.keys
      bytes = names.each_with_index.map { |name, i| Obj::Data.new("zr_symname_#{i}", :text_const, name.b, align: 1) }
      table = +"".b
      relocs = []
      names.each_with_index do |name, i|
        relocs << Obj::Reloc.new(i * 16, :abs64, "zr_symname_#{i}")
        table << [0, name.bytesize].pack("Q<Q<")
      end
      bytes + [Obj::Data.new("zr_symbol_names", :data_const, table, relocs: relocs, align: 8, linkage: :export),
               Obj::Data.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export),
               Obj::Data.new("zr_site_count", :data_const, [symbols.sites].pack("Q<"), align: 8, linkage: :export)]
    end
  end
end
