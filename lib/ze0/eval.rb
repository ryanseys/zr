# frozen_string_literal: true

require_relative "hir"
require_relative "zr/lower"
require_relative "ir/arm64"
require_relative "obj/jit"
require_relative "../../rt/ext/zr_description"
require "ze0/eval/runtime"

module Ze0
  # A string of ruby, compiled while the program that asked for it runs.
  # prism parses it, the lowering the program itself was built with turns
  # it into machine code, and the loader writes that into this process.
  #
  # The kernel description travels with the program, and the symbol table
  # is seeded from the one the program is running on, so an eval names
  # the same kernel and the same symbol ids as the code around it.
  class Eval
    def self.current
      @current ||= new(Runtime.new)
    end

    def initialize(runtime)
      @runtime = runtime
      @description = Machine::Description.parse(Machine::Description::KERNEL)
      @symbols = Machine::Symbols.new(runtime.symbol_names, sites: runtime.sites)
      @seeded = @symbols.ids.size
      @host = Obj::JIT.host
      @count = 0
    end

    # `source` compiled, loaded and run; answers what its last statement
    # answered.
    def run(source, file)
      @runtime.run(compile(source, file))
    end

    # The address of the toplevel `source` compiles to.
    def compile(source, file)
      @count += 1
      name = "zr_eval_#{@count}"
      hir = Hir.build(source, file, road: false)
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :top).run
      intern_new_names
      Obj::JIT.load(unit(functions, data), host: @host).fetch(name)
    end

    private

    # A name this eval is the first to use gets its id here; the program
    # is running, so the table it interns into must answer the same id
    # the code was compiled with.
    def intern_new_names
      @symbols.ids.keys[@seeded..].each_with_index do |name, i|
        got = @runtime.intern(name)
        raise "#{name.inspect} interned as #{got}, not #{@seeded + i}" if got != @seeded + i
      end
      @seeded = @symbols.ids.size
    end

    def unit(functions, data)
      unit = Obj::Unit.new
      defined = functions.map(&:name) + data.map(&:name)
      functions.each { |f| unit.functions << IR::Arm64.new(f, defined: defined).compile }
      data.each { |d| unit.data << d }
      unit
    end
  end
end

module Kernel
  # Ruby compiled and run where this call stands.
  def eval(source, _binding = nil, file = "(eval)", _line = 1)
    Ze0::Eval.current.run(source, file)
  end
end
