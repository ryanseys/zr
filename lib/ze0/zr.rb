# frozen_string_literal: true

require_relative "machine/lower"
require_relative "obj/model"
require_relative "hir"
require_relative "zr/lower"

module Ze0
  # The `zr` runtime: the kernel files, the core library written in
  # Ruby over them, and the data the compiler lays out beside them.
  module Zr
    KERNEL = Dir[File.join(__dir__, "../../rt/kernel/*.rb")].sort.freeze
    CORE = Dir[File.join(__dir__, "../../rt/core/*.rb")].sort.freeze

    module_function

    # A Ruby program with the kernel and the core library as one unit:
    # `[functions, data, raw]` ready for `Native::Build`.
    def program(source, file)
      symbols = Machine::Symbols.new
      unit = Machine.unit(KERNEL, symbols: symbols)
      core_functions, core_data = core(unit, symbols)
      functions, data = Lower.new(Hir.build(source, file), unit, symbols).run
      [unit.functions + core_functions + functions, unit.data + core_data + data + symbol_names(symbols), unit.raw]
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
