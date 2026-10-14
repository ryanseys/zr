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
    # @rbs @syscalls: Obj::JIT::_Syscalls
    # @rbs @count: Integer
    # @rbs @compiled: Hash[Array[untyped], [Integer, Integer, Integer, Integer, Array[Integer], Integer?] | Exception]
    # @rbs @files: Hash[[String, String], [Integer, String?]]
    # @rbs @file_spots: Hash[String, String?]
    # @rbs @scripts: Array[String]
    # @rbs @script_sources: Array[[String, Integer]]

    # Two threads can eval at the same time. Only one of them loads the
    # compiler, and the other waits until the load is complete. A trap
    # handler may eval, so it may take this lock (rb_mutex_allow_trap); a
    # host ruby has no such switch.
    LOADING = Thread::Mutex.new
    begin
      Thread::Mutex.send(:allow_trap, LOADING)
    rescue NoMethodError
      nil
    end

    # The compiler loads at the first eval, not when the program boots.
    # Most programs that can eval never do. Loading it makes about
    # 100,000 objects, and about 90,000 stay live for the rest of the run.
    #: () -> Eval
    def self.current
      @current || LOADING.synchronize do
        @current ||= plainly do
          require_relative "hir"
          require_relative "lower"
          require_relative "backend/aarch64"
          require_relative "obj/jit"
          require_relative "runtime/lib/zr/obj/jit/runtime"
          require "zr_description"
          new(Runtime.new)
        end
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
      # `GC.stress=` has one overload for an Integer and one for a bool,
      # and Steep cannot give it the union that `GC.stress` returns.
      stress = GC.stress #: untyped
      begin
        GC.stress = false
        Runtime.plain_separators { Runtime.compiling(&) }
      ensure
        GC.stress = stress
      end
    end

    #: (Runtime runtime) -> void
    def initialize(runtime)
      @runtime = runtime
      @description = Machine::Description.parse(Machine::Description::KERNEL)
      @symbols = Machine::Symbols.new(runtime.symbol_names, sites: runtime.sites, intern: runtime.method(:intern))
      @syscalls = Obj::JIT::Runtime.new
      @count = 0
      @compiled = {}
      @files = {}
      @scripts = []
      @script_sources = []
      @file_spots = {}
    end

    # Compiles `source`. Returns the toplevel's address, its FrameMeta
    # (the call writes the calling frame into it), and the shape of the
    # Env that the call makes for it (the slot count and names).
    #
    # `scopes` are the local names that the calling scope can see,
    # innermost first. zr parses the string one scope inside them. A
    # write to a name that they contain goes to their Env. A new name
    # stays in the eval's own Env. `method` is the parameters of the
    # enclosing method, or nil outside a method. `debug_frozen` is
    # RubyVM::InstructionSequence.compile's debug_frozen_string_literal:
    # each String literal keeps where it was made.
    #
    # @rbs source: untyped
    # @rbs file: untyped
    # @rbs line: _ToInt
    # @rbs scopes: Array[Array[Symbol]]
    # @rbs method: untyped
    # @rbs using: Integer?
    # @rbs warn_now: bool
    # @rbs debug_frozen: bool
    # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
    def compile(source, file, line = 1, scopes = [], method = nil, using: nil, warn_now: false, debug_frozen: false)
      Eval.plainly { compiled(source, file, line, scopes, method, using: using, warn_now: warn_now, debug_frozen: debug_frozen) }
    rescue Hir::Invalid => e
      # Ruby reads a regexp literal when it compiles the string around it,
      # so an invalid pattern is a syntax error, not a run-time error. A
      # build exits with status 3 and gives the line. Here the program is
      # running, so it gets an error that it can rescue.
      syntax = SyntaxError.new(e.message)
      syntax.set_backtrace(caller_locations(1))
      raise syntax
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
    #
    # The machine code of a file is never freed, so a file that a program
    # loads again with the same source runs the code of its first compile.
    # Under Coverage, or a TracePoint in a program built without trace
    # events, the code differs, so each load compiles.
    #: (String path) -> Integer
    def compile_file(path)
      Eval.plainly do
        source = File.read(path)
        coverage = covering
        reuse = coverage.nil? && !@runtime.traced_for_now?
        key = [-path, -source] #: [String, String]
        if reuse && @files.key?(key)
          # The path's spots are this code's again.
          top, @file_spots[path] = @files.fetch(key)
          next top
        end

        @count += 1
        name = "zr_load_#{@count}"
        # While Coverage measures, the file gets its :line events and its
        # def sites, and Coverage learns which of its lines can run and where
        # each of its methods is.
        base = coverage&.send(:next_def_site)
        # The file's `using` entries come after every entry in use, as an
        # eval's do (`compiled`): numbered from 0, they would take the
        # entries of the program and of eval support (prism's parser).
        hir = Hir.build(source, path, BuildOptions.new(trace: @runtime.tracing?), program: false, def_base: base, activations: @runtime.activations)
        @file_spots[path] = (hir.spots || {}).fetch(path, "")
        @runtime.take_activations(hir.activations)
        coverage&.send(:compiled_lines!, hir.coverable, hir.defs)
        ext = Library::Roots.internal_library?(path)
        functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :top, ext: ext).run
        top = Obj::JIT.load(unit(functions, data), syscalls: @syscalls).fetch(name)
        @files[key] = [top, @file_spots[path]] if reuse
        top
      end
    end

    # The spots (Hir::Spots) of the file at `path` that a load or require
    # compiled at run time, or nil.
    #: (String path) -> String?
    def file_spots(path) = @file_spots[path]

    # The spots (Hir::Spots) of the eval that `kept_script` numbered.
    #: (Integer number) -> String
    def script_spots(number) = @scripts.fetch(number - 1)

    # The source and first line of the eval that `kept_script` numbered.
    #: (Integer number) -> [String, Integer]
    def script_source(number) = @script_sources.fetch(number - 1)

    private

    # The Coverage module, when the program loaded it. It is reached by a
    # symbol: a constant that names it in code arms the trace events of the
    # build (`Loader#names_of?`), and this code only reports to it.
    #: () -> untyped
    def covering
      coverage = Object.const_defined?(:Coverage) && Object.const_get(:Coverage) #: untyped
      coverage.respond_to?(:compiled_lines!, true) ? coverage : nil
    end

    # @rbs source: untyped
    # @rbs file: untyped
    # @rbs line: _ToInt
    # @rbs scopes: Array[Array[Symbol]]
    # @rbs method: untyped
    # @rbs using: Integer?
    # @rbs warn_now: bool
    # @rbs debug_frozen: bool
    # @rbs return: [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
    def compiled(source, file, line, scopes, method, using:, warn_now:, debug_frozen: false)
      # eval_make_iseq: a source that is not ASCII compatible cannot be read.
      raise ArgumentError, "invalid source encoding" unless string(source).encoding.ascii_compatible?

      coverage = covering
      # The machine code of an eval is never freed, so a string that runs
      # again, in a scope of the same shape, runs the code that its first
      # compile made, or raises a copy of the error that its first compile
      # raised. Coverage changes the code, and so does a TracePoint enabled
      # in a program built without trace events, so under them each eval
      # compiles. So does an eval that takes `using` entries.
      plain_new = plain_new?
      keep = keep_script_lines?
      key = [-string(source), string(source).encoding, -string(file), line.to_int, scopes, method, using, warn_now, debug_frozen, plain_new,
             keep]
      reuse = coverage.nil? && !@runtime.traced_for_now?
      if reuse && (kept = @compiled[key])
        raise warned(kept.dup) if kept.is_a?(Exception)

        return kept
      end

      taken = @runtime.activations
      @count += 1
      name = "zr_eval_#{@count}"
      # A `using` entry is a slot in one table that the whole program
      # shares. The build numbered the program's own entries, and all are
      # in use before the first line runs. So an eval takes the next free
      # entries, and takes them now, because no other code runs before
      # the next compile.
      begin
        switches = Hir::Switches.new(debug_frozen_string_literal: debug_frozen, keep_script_lines: keep)
        hir = Hir.build(string(source), string(file), BuildOptions.new(trace: @runtime.tracing?, switches: switches), program: false,
                        line: line.to_int, scopes: [*scopes.reverse, []], method: method, activations: @runtime.activations, using: using)
      rescue Hir::Invalid, SyntaxError => e
        @compiled[key] = e.dup if reuse
        raise warned(e)
      end
      @runtime.take_activations(hir.activations)
      # RubyVM::InstructionSequence.compile: the parser warns as it reads,
      # not when the code runs.
      if warn_now
        hir.warnings.each { |text| parse_warning(text) }
        hir.warnings.clear
      end
      # Coverage is there only when the program loads it. Under `eval:
      # true` it counts the eval's lines as lines of the eval's file. Ruby
      # gives the file as many lines as the code has newlines, after the
      # lines before the eval's first one.
      coverable = hir.coverable
      if coverable && !coverable.empty?
        size = string(source).b.count("\n") + line.to_int - 1
        no_defs = {} #: Hash[String, Array[Array[Integer]]]
        coverage&.send(:compiled_lines!, coverable.transform_values { |(_, lines)| [size, lines] }, no_defs, true)
      end
      script = keep ? kept_script((hir.spots || {}).fetch(string(file), ""), string(source), line.to_int) : 0
      functions, data = Zr::Lower.new(hir, @description, @symbols, entry: name, kind: :eval, outer: outer(scopes), plain_new: plain_new,
                                                                   script: script).run
      symbols = Obj::JIT.load(unit(functions, data), syscalls: @syscalls)
      metas = symbols.select { |symbol, _| symbol.start_with?("zr_meta_") }.values
      code = [symbols.fetch(name), symbols.fetch("zr_meta_#{name}"), hir.locals.size, symbols.fetch("zr_locals_#{name}"),
              metas, hir.using] #: [Integer, Integer, Integer, Integer, Array[Integer], Integer?]
      @compiled[key] = code if reuse && hir.activations == taken
      code
    end

    # Keeps an eval's spots, as ruby keeps its script lines: its
    # Locations then find their source ranges. Its source and first line
    # stay too, for #syntax_tree. The number starts at 1.
    #: (String spots, String source, Integer line) -> Integer
    def kept_script(spots, source, line)
      @scripts << spots
      @script_sources << [source, line]
      @scripts.size
    end

    # Whether ruby keeps the script lines of the code that it compiles
    # (RubyVM.keep_script_lines).
    #: () -> bool
    def keep_script_lines?
      vm = Object.const_get(:RubyVM) #: untyped
      vm.keep_script_lines ? true : false
    end

    # Whether the program turned off CRuby's specialized instructions
    # (RubyVM::InstructionSequence.compile_option), so `new` is a send.
    #: () -> bool
    def plain_new?
      vm = Object.const_get(:RubyVM) #: untyped
      vm::InstructionSequence.compile_option[:specialized_instruction] == false
    end

    # An error of an eval's code that does not parse: the parser's
    # warnings print first, as ruby's parser prints them while it reads.
    # A kept copy has them too, so each eval of the code prints them.
    #: (Exception error) -> Exception
    def warned(error)
      return error unless error.instance_variable_defined?(:@zr_warnings)

      warnings = error.remove_instance_variable(:@zr_warnings) #: Array[String]
      warnings.each { |text| parse_warning(text) }
      error
    end

    # A warning of the parser, as zr_parse_warning writes it: one that
    # only a true $VERBOSE prints starts with VERBOSE_WARNING.
    #: (String text) -> void
    def parse_warning(text)
      verbose = text.start_with?(Hir::Build::Loader::VERBOSE_WARNING)
      return if $VERBOSE.nil? || (verbose && !$VERBOSE)

      Warning.warn("#{verbose ? text[1..] : text}\n")
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
    # the code of the program around it. `Zr::Lower#run` without a block
    # gives only IR functions.
    #: (Array[IR::Function | Obj::Code] lowered, Array[Obj::Datum] data) -> Obj::Unit
    def unit(lowered, data)
      functions = lowered #: Array[IR::Function]
      functions.each { |f| IR::Passes.prepare(f) }
      Backend::Aarch64.unit(functions, data)
    end
  end
end
