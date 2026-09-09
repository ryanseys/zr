# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "zr/lower"

module Ze0
  # The `zr` runtime: the kernel files, the core library written in
  # Ruby over them, and the data the compiler lays out beside them.
  module Zr
    KERNEL = Dir[File.join(__dir__, "../../rt/kernel/*.rb")].sort.freeze
    # The core library files, in the order their toplevels run: a module
    # before the classes that include it.
    CORE = %w[module exception enumerable enumerator comparable integer bignum array hash range struct string kernel float proc format io process env file data gc random thread monitor time set pack regexp_pattern regexp rational complex].map { |name| File.join(__dir__, "../../rt/core/#{name}.rb") }.freeze

    # Where the runtime's built forms live, keyed on the digest of
    # everything they depend on: the runtime sources and the compiler.
    CACHE = File.expand_path("../../tmp/rt", __dir__)

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
        @digest ||= Digest::SHA256.new.tap { |d| Zr.sources.each { |path| d << File.binread(path) } }.hexdigest
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
    # that takes everything as one unit.
    Program = Struct.new(:runtime, :functions, :data) do
      def raw = runtime.raw

      def to_ary = [runtime.functions + functions, runtime.data + data, raw]
    end

    module_function

    def program(source, file)
      rt = runtime
      symbols = Machine::Symbols.new(rt.symbols.ids.keys, sites: rt.symbols.sites)
      functions, data = Lower.new(Hir.build(source, file), rt.unit, symbols).run
      Program.new(rt, functions, data + symbol_names(symbols))
    end

    def runtime
      @runtime ||= Runtime.new
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
    # functions ending with `zr_prelude`.
    def core(unit, symbols)
      functions = []
      data = []
      entries = CORE.map do |path|
        entry = "zr_core_#{File.basename(path, ".rb")}"
        f, d = Lower.new(Hir.build(File.read(path), path), unit, symbols, entry: entry, internal: true).run
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
               Obj::Data.new("zr_symbol_count", :data_const, [names.size].pack("Q<"), align: 8, linkage: :export)]
    end
  end
end
