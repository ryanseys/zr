# frozen_string_literal: true

require_relative "helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# The kernel core's test programs, `test/rt/<name>.rb`: hand-written
# toplevels in the dialect. `rt_test.rb` links each into a binary and
# `wasm_test.rb` into a module.
module RtPrograms
  FILES = Dir[File.join(ROOT, "test/rt/*.rb")].sort.freeze

  module_function

  # A program of `rb` over `target`'s runtime, as `ze0 build` makes one:
  # the runtime comes from the cache, and only the file's own functions
  # and data are lowered and assembled. The file is lowered with the
  # kernel, so it names the kernel's defs, constants and layouts, and
  # over the runtime's symbol table, so its ids are the runtime's.
  def compile(rb, target = Ze0::Target.default)
    runtime = Ze0::Zr.runtime(target)
    unit = Ze0::Machine.unit(Ze0::Zr.kernel_files(target) + [rb], symbols: runtime_symbols(runtime))
    own = unit.declared_defs.filter_map { |name, d| name if d.file == rb }
    kernel = kernel_data(runtime)
    functions = unit.functions.select { |f| own.include?(f.name) }
    data = unit.data.reject { |d| kernel.include?(d.name) }
    Ze0::Zr::Program.new(runtime, functions, data + Ze0::Zr.symbol_names(unit.symbols) + Ze0::Zr.load_tables(target: target), nil)
  end

  def runtime_symbols(runtime) = Ze0::Machine::Symbols.new(runtime.symbols.ids.keys, sites: runtime.symbols.sites)

  # The names of the data the kernel alone makes, which the runtime
  # object holds already: lowered once a process, over the runtime's
  # symbols, so its names are the ones a file lowered after it sees.
  def kernel_data(runtime)
    (@kernel_data ||= {})[runtime.target.triple] ||=
      Ze0::Machine.unit(Ze0::Zr.kernel_files(runtime.target), symbols: runtime_symbols(runtime)).data.map(&:name)
  end

  # What the program prints, stderr folded in, and the status it exits with.
  def expected(rb)
    exit_file = rb.sub(/\.rb\z/, ".exit")
    [File.binread(rb.sub(/\.rb\z/, ".stdout")), File.file?(exit_file) ? Integer(File.read(exit_file)) : 0]
  end
end
