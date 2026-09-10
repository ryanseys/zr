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
      @description = Machine::Description.parse(Machine::Description::KERNEL)
      @symbols = Machine::Symbols.new(runtime.symbol_names, sites: runtime.sites, intern: runtime.method(:intern))
      @host = Obj::JIT.host
      @count = 0
    end

    # What `source` compiles to: the toplevel's address, its FrameMeta,
    # which the call writes the asking frame into, and the shape of the
    # Env the call makes for it (how many slots, and their names).
    #
    # `scopes` are the local names the asking scope reaches, innermost
    # first. The string is parsed one scope inside them, so a name it
    # writes that they already hold lands in their Env, and a name it
    # invents stays its own.
    def compile(source, file, line = 1, scopes = [])
      @count += 1
      name = "zr_eval_#{@count}"
      hir = Hir.build(string(source), string(file), road: false, line: line.to_int, scopes: [*scopes.reverse, []])
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval, outer: outer(scopes)).run
      symbols = Obj::JIT.load(unit(functions, data), host: @host)
      [symbols.fetch(name), symbols.fetch("zr_meta_#{name}"), hir.locals.size, symbols.fetch("zr_locals_#{name}")]
    end

    private

    # The Outer chain for `scopes`, innermost first, as the lowering
    # walks it: one step out per Env the asking frame reaches.
    def outer(scopes)
      scopes.reverse.reduce(nil) { |out, names| Zr::Outer.new(names, out) }
    end

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

    def unit(functions, data)
      unit = Obj::Unit.new
      defined = functions.map(&:name) + data.map(&:name)
      functions.each { |f| unit.functions << IR::Arm64.new(f, defined: defined).compile }
      data.each { |d| unit.data << d }
      unit
    end
  end
end
