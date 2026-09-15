# frozen_string_literal: true

require "ze0/eval/runtime"
require "ze0/eval/forms"
require "ze0/ir/passes"

module Ze0
  # A string of ruby, compiled while the program that asked for it runs.
  # prism parses it, the lowering the program itself was built with turns
  # it into machine code, and the loader writes that into this process.
  #
  # The kernel description travels with the program, and the symbol table
  # is seeded from the one the program is running on, so an eval names
  # the same kernel and the same symbol ids as the code around it.
  class Eval
    # The compiler loads with the first string a program evals, not as
    # the program boots. Most programs that could eval never do, and
    # loading it makes some twelve thousand objects: every one a
    # collection keeps marking, and one a collection under stress.
    def self.current
      @current ||= begin
        require_relative "hir"
        require_relative "zr/lower"
        require_relative "backend/aarch64"
        require_relative "obj/jit"
        require "zr_description"
        new(Runtime.new)
      end
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
    # invents stays its own. `method` is the parameters of the method the
    # scope runs inside, or nil outside one.
    def compile(source, file, line = 1, scopes = [], method = nil)
      @count += 1
      name = "zr_eval_#{@count}"
      hir = begin
        Hir.build(string(source), string(file), road: false, line: line.to_int, scopes: [*scopes.reverse, []], method: method)
      rescue SyntaxError => e
        # The error is the eval's, raised where the eval stands, unless it
        # names only the string, as a stray `yield`'s does.
        e.set_backtrace(caller_locations(1)) unless e.backtrace == [e.path]
        raise e
      end
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval, outer: outer(scopes)).run
      symbols = Obj::JIT.load(unit(functions, data), host: @host)
      metas = symbols.select { |symbol, _| symbol.start_with?("zr_meta_") }.values
      [symbols.fetch(name), symbols.fetch("zr_meta_#{name}"), hir.locals.size, symbols.fetch("zr_locals_#{name}"), metas]
    end

    # The address of the toplevel of the file at `path`, compiled as a
    # required file is: a scope of its own, under main and Object. A file
    # among the native halves is the runtime's own, where `Primitive`
    # resolves.
    def compile_file(path)
      @count += 1
      name = "zr_load_#{@count}"
      hir = Hir.build(File.read(path), path, road: false)
      ext = path.start_with?("#{Hir::Build::EXT}/")
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :top, ext: ext).run
      Obj::JIT.load(unit(functions, data), host: @host).fetch(name)
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

    # The same passes and checks a build runs, so an eval's code is the
    # code the program around it was built from.
    def unit(functions, data)
      functions.each { |f| IR::Passes.prepare(f) }
      Backend::Aarch64.unit(functions, data)
    end
  end
end
