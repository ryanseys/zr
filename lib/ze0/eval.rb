# frozen_string_literal: true

require_relative "hir"
require_relative "zr/lower"
require_relative "ir/arm64"
require_relative "obj/jit"
require_relative "../../rt/ext/zr_description"
require "ze0/eval/runtime"
require "ze0/eval/forms"

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

    # The toplevel `source` compiles to: its address, and the address of
    # its FrameMeta, which the call writes the asking frame into.
    def compile(source, file, line = 1)
      @count += 1
      name = "zr_eval_#{@count}"
      hir = Hir.build(string(source), string(file), road: false, line: line.to_int)
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval).run
      intern_new_names
      symbols = Obj::JIT.load(unit(functions, data), host: @host)
      [symbols.fetch(name), symbols.fetch("zr_meta_#{name}")]
    end

    private

    # The argument as ruby takes a string of it: a String, or anything
    # that answers `to_str`.
    def string(value)
      return value if value.is_a?(String)
      raise TypeError, "no implicit conversion of #{name_of(value)} into String" unless value.respond_to?(:to_str)

      value.to_str
    end

    def name_of(value)
      value.nil? || value == true || value == false ? value.inspect : value.class.name
    end

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
