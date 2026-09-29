# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"

module Zr
  module Test
    # The programs in test/runtime. Each is top-level code, written by
    # hand in the machine dialect, that runs on the zr runtime.
    # runtime_test.rb links each into a binary, and wasm_test.rb builds
    # each as a WASI module.
    module RuntimePrograms
      FILES = Dir[File.join(ROOT, "test/runtime/*.rb")].sort.freeze

      module_function

      # Makes a program from `rb` on the runtime of `target`, as
      # `zr build` does. The runtime comes from the cache. Only the
      # functions and data of the file are lowered and assembled. The file
      # is lowered with the kernel, so it can refer to kernel defs,
      # constants and layouts. It uses the symbol table of the runtime,
      # so its symbol ids agree with the runtime.
      def compile(rb, target = Zr::Target.default)
        runtime = Zr.runtime(target)
        unit = Zr::Machine.unit(Zr.kernel_files(target) + [rb], symbols: runtime_symbols(runtime))
        own = unit.declared_defs.filter_map { |name, d| name if d.file == rb }
        kernel = kernel_data(runtime)
        functions = unit.functions.select { |f| own.include?(f.name) }
        data = unit.data.reject { |d| kernel.include?(d.name) }
        Zr::Program.new(runtime, functions, data + Zr.symbol_names(unit.symbols) + Zr.load_tables(target: target), nil)
      end

      def runtime_symbols(runtime) = Zr::Machine::Symbols.new(runtime.symbols.names, sites: runtime.symbols.sites)

      # Returns the names of the data that the kernel makes. The runtime
      # object already contains this data. It is lowered one time in each
      # process, with the symbols of the runtime, so the names agree with
      # a file that is lowered after it.
      def kernel_data(runtime)
        (@kernel_data ||= {})[runtime.target.triple] ||=
          Zr::Machine.unit(Zr.kernel_files(runtime.target), symbols: runtime_symbols(runtime)).data.map(&:name)
      end

      # Returns the expected output (stdout and stderr together) and exit
      # status: `<name>.out`, and `<name>.status` (0 when there is none).
      def expected(rb)
        exit_file = rb.sub(/\.rb\z/, ".status")
        [File.binread(rb.sub(/\.rb\z/, ".out")), File.file?(exit_file) ? Integer(File.read(exit_file)) : 0]
      end
    end
  end
end
