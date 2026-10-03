# frozen_string_literal: true

# The runtime's own libraries (lib/zr/runtime/lib/zr) call `Primitive`, so they
# run only inside a zr binary. Under ruby, nothing loads this file.
require_relative "runtime/lib/zr/eval/runtime"
require_relative "runtime/lib/zr/eval/forms"
require_relative "ir/passes"

module Zr
  # A string of ruby, compiled at run time in the program that evals it.
  # prism parses it, the same lowering as the program's turns it into
  # machine code, and the loader writes that code into this process.
  #
  # The program includes the kernel description, and the symbol table
  # starts from the program's own table. So an eval uses the same kernel
  # and the same symbol ids as the code around it.
  class Eval
    # @rbs @runtime: Runtime
    # @rbs @description: Machine::Description
    # @rbs @symbols: Machine::Symbols
    # @rbs @host: Obj::_JITHost
    # @rbs @count: Integer

    # The compiler loads at the first eval, not when the program boots.
    # Most programs that can eval never do. Loading it makes about
    # 100,000 objects, and about 90,000 stay live for the rest of the run.
    #: () -> Eval
    def self.current
      @current ||= plainly do
        require_relative "hir"
        require_relative "lower"
        require_relative "backend/aarch64"
        require_relative "obj/jit"
        require "zr_description"
        new(Runtime.new)
      end
    end

    # The compiler runs with the plain collector. A collection at every
    # allocation (ZR_GC_STRESS) is for the program's own code. The
    # compiler leaves about 90,000 live objects, and an eval makes about
    # 30,000 allocations. Under stress, each allocation marks all of them
    # again, so one eval would take minutes.
    #
    # The program's separators ($, $; $/ $\) are set aside too: the
    # compiler joins, splits and reads lines with ruby's defaults. And
    # its Enumerable methods walk Arrays and Hashes with the core's own
    # `each`, not one that the program redefines (Runtime.compiling).
    #: [T] () { () -> T } -> T
    def self.plainly(&)
      stress = GC.stress
      GC.stress = false
      Runtime.plain_separators { Runtime.compiling(&) }
    ensure
      GC.stress = stress
    end

    #: (Runtime runtime) -> void
    def initialize(runtime)
      @runtime = runtime
      @description = Machine::Description.parse(Machine::Description::KERNEL)
      @symbols = Machine::Symbols.new(runtime.symbol_names, sites: runtime.sites, intern: runtime.method(:intern))
      @host = Obj::JIT.host
      @count = 0
    end

    # Compiles `source`. Returns the toplevel's address, its FrameMeta
    # (the call writes the calling frame into it), and the shape of the
    # Env that the call makes for it (the slot count and names).
    #
    # `scopes` are the local names that the calling scope can see,
    # innermost first. zr parses the string one scope inside them. A
    # write to a name that they contain goes to their Env. A new name
    # stays in the eval's own Env. `method` is the parameters of the
    # enclosing method, or nil outside a method.
    #
    # @rbs source: untyped
    # @rbs file: untyped
    # @rbs line: _ToInt
    # @rbs scopes: Array[Array[Symbol]]
    # @rbs method: untyped
    # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer]]
    def compile(source, file, line = 1, scopes = [], method = nil)
      # Coverage cannot measure eval'd code, so it stops with a message.
      # Coverage is there only when the program loads it, which `defined?`
      # checks, so Steep cannot know the constant.
      ::Coverage.send(:eval_compiled!) if defined?(::Coverage) && ::Coverage.respond_to?(:eval_compiled!, true) # steep:ignore
      Eval.plainly { compiled(source, file, line, scopes, method) }
    rescue Hir::Invalid => e
      # Ruby reads a regexp literal when it compiles the string around it,
      # so an invalid pattern is a syntax error, not a run-time error. A
      # build exits with status 3 and gives the line. Here the program is
      # running, so it gets an error that it can rescue.
      raise SyntaxError.new(e.message).tap { |syntax| syntax.set_backtrace(caller_locations(1)) }
    rescue SyntaxError => e
      # The backtrace starts at the eval call, unless the error refers
      # only to the string (for example, a stray `yield`).
      e.set_backtrace(caller_locations(1)) unless e.backtrace == [e.path]
      raise e
    end

    # prism's tree of `source`, whose first line is `line`
    # (RubyVM::InstructionSequence reads it).
    #: (String source, Integer line) -> Prism::ProgramNode
    def parse(source, line) = Prism.parse(source, line: line).value

    # The toplevel address of the file at `path`, compiled as a required
    # file: its own scope, under main and Object. A file in the extensions
    # (`Library::Layout::EXT`) is part of the runtime, where `Primitive`
    # resolves.
    #: (String path) -> Integer
    def compile_file(path)
      Eval.plainly do
        @count += 1
        name = "zr_load_#{@count}"
        hir = Hir.build(File.read(path), path, eval_support: false)
        ext = Library::Roots.internal_library?(path)
        functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :top, ext: ext).run
        Obj::JIT.load(unit(functions, data), host: @host).fetch(name)
      end
    end

    private

    # @rbs source: untyped
    # @rbs file: untyped
    # @rbs line: _ToInt
    # @rbs scopes: Array[Array[Symbol]]
    # @rbs method: untyped
    # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer]]
    def compiled(source, file, line, scopes, method)
      @count += 1
      name = "zr_eval_#{@count}"
      # A `using` entry is a slot in one table that the whole program
      # shares. The build numbered the program's own entries, and all are
      # in use before the first line runs. So an eval takes the next free
      # entries, and takes them now, because no other code runs before
      # the next compile.
      hir = Hir.build(string(source), string(file), eval_support: false, line: line.to_int, scopes: [*scopes.reverse, []], method: method,
                                                    activations: @runtime.activations, trace: @runtime.tracing?)
      @runtime.take_activations(hir.activations)
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval, outer: outer(scopes)).run
      symbols = Obj::JIT.load(unit(functions, data), host: @host)
      metas = symbols.select { |symbol, _| symbol.start_with?("zr_meta_") }.values
      [symbols.fetch(name), symbols.fetch("zr_meta_#{name}"), hir.locals.size, symbols.fetch("zr_locals_#{name}"), metas]
    end

    # The Outer chain for `scopes`, innermost first, in lowering order:
    # one step out for each Env that the calling frame can see.
    #: (Array[Array[Symbol]] scopes) -> Lower::Outer?
    def outer(scopes)
      scopes.reverse.reduce(
        nil #: Lower::Outer?
      ) { |out, names| Zr::Lower::Outer.new(names, out) }
    end

    # Converts the argument to a String as ruby does: a String, or an
    # object that responds to `to_str`.
    #: (untyped value) -> String
    def string(value)
      return value if value.is_a?(String)
      raise TypeError, "no implicit conversion of #{name_of(value)} into String" unless value.respond_to?(:to_str)

      value.to_str
    end

    #: (untyped value) -> String?
    def name_of(value)
      value.nil? || value == true || value == false ? value.inspect : value.class.name
    end

    # Runs the same passes and checks as a build, so eval'd code matches
    # the code of the program around it.
    #: (Array[IR::Function] functions, Array[Obj::Datum] data) -> Obj::Unit
    def unit(functions, data)
      functions.each { |f| IR::Passes.prepare(f) }
      Backend::Aarch64.unit(functions, data)
    end
  end
end
