# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "paths"
require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "zr/lower"

module Ze0
  # The `zr` runtime: the kernel files, the core library written in
  # Ruby over them, and the data the compiler lays out beside them.
  module Zr
    KERNEL = Dir[File.join(Paths::RT, "kernel/*.rb")].sort.freeze
    # The core library files, in the order their toplevels run: a module
    # before the classes that include it.
    CORE = %w[module warning encodings transcode cjk exception enumerable enumerator comparable integer bignum array hash range struct unicode string converter kernel float proc binding format errno io io_buffer process signal env file argf data gc random thread trace_point monitor time set ractor marshal pack regexp_pattern regexp pathname rational complex objectspace box].map { |name| File.join(Paths::RT, "core/#{name}.rb") }.freeze

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
      attr_reader :unit

      def initialize
        @unit = Machine.unit(KERNEL, symbols: kernel_symbols)
      end

      def raw = unit.raw

      def digest
        # A path goes in beside its bytes: the runtime object carries
        # the core's file names, so two checkouts never share one.
        @digest ||= Digest::SHA256.new.tap { |d| Zr.sources.each { |path| d << path << "\0" << File.binread(path) } }.hexdigest
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
        @lowered ||= Zr.core(unit, kernel_symbols)
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

      def units = meta.fetch("units")
      def configures? = meta.fetch("configures")
      def normalizes? = meta.fetch("normalizes")

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
          loader = Hir::Build.road
          program = Hir::Program.new(Hir::Build::EVAL_ROAD, [], Hir::Seq.new([], 0), loader.units, [], true, loader.entries)
          symbols = Machine::Symbols.new(@runtime.symbols.ids.keys, sites: @runtime.symbols.sites)
          lower = Lower.new(program, @runtime.unit, symbols, entry: "zr_road")
          functions, data = lower.run
          files = loader.units.filter_map { |u| u.file if u.file.start_with?("/") }.uniq.sort
          meta = { "key" => files_key(files), "files" => files,
                   "units" => loader.entries.to_h { |path, i| [path, lower.unit_entry(i)] },
                   "configures" => loader.configures?, "normalizes" => loader.normalizes?,
                   "names" => symbols.ids.keys, "sites" => symbols.sites }
          Zr.write_cache(meta_path, JSON.generate(meta))
          { functions: functions, data: data, meta: meta }
        end
      end
    end

    module_function

    def program(source, file)
      rt = runtime
      hir = Hir.build(source, file, road: road)
      symbols = hir.evals ? road.symbols : Machine::Symbols.new(rt.symbols.ids.keys, sites: rt.symbols.sites)
      lower = Lower.new(hir, rt.unit, symbols)
      functions, data = lower.run
      units = hir.entries.map { |path, i| [path, lower.unit_entry(i)] }
      Program.new(rt, functions, data + symbol_names(symbols) + load_tables(units, evals: hir.evals), hir.evals && road)
    end

    def runtime
      @runtime ||= Runtime.new
    end

    def road
      @road ||= Road.new(runtime)
    end

    # The files the runtime is lowered from, and the compiler that lowers
    # them.
    def sources
      KERNEL + CORE + Dir[File.join(__dir__, "**/*.rb")].sort
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
    def core(unit, symbols)
      functions = []
      data = []
      entries = CORE.map do |path|
        entry = "zr_core_#{File.basename(path, ".rb")}"
        f, d = Lower.new(Hir.build(File.read(path), path, road: false), unit, symbols, entry: entry, internal: true).run
        functions.concat(f)
        data.concat(d)
        entry
      end
      [functions << prelude(entries, unit), data]
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
    # those gets the lines. `units` are `[path, entry]` pairs; a unit that
    # only stops has no path.
    def load_tables(units = [], evals: false)
      units = units.select { |path, _| path.start_with?("/") }.sort
      names = evals ? [Hir::Build::STDLIB, Hir::Build.missing_features, Hir::Build::PRELOADED, [Hir::Build::EXT]] : [[]] * 4
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
