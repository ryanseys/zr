# frozen_string_literal: true

# The front end reads the library directories of the program's build
# from `Zr::Eval::Runtime` (Library::Roots.carried). Without it, the front end
# tries to resolve the gems in the guest, which has no gems.
require_relative "../eval"
require_relative "../runtime/lib/zr/eval/world"
require_relative "../runtime/lib/zr/eval/arguments"
require_relative "../runtime/lib/zr/eval/interpreter_forms"
require_relative "interpreter/evaluate"

module Zr
  class Eval
    # The tree-walking interpreter: it runs a string of Ruby in the running
    # program that evals it.
    #
    # A program uses it when it cannot write machine code into itself. The
    # engine fixes the code of a wasm module when it instantiates it, and
    # WASI gives a guest no way to make a second module. Thus the eval
    # compiler (`Eval::Compiler`) has no place for its output. The front
    # end is the same for both (prism port, `Hir.build`, the same
    # desugaring). Only the back end is different: here `Interpreter::Tree`
    # walks the tree and does not lower it. The eval forms call
    # `Interpreter.evaluate` (interpreter/evaluate.rb).
    #
    # `ZR_EVAL=walk` builds a native program with the tree-walking
    # interpreter, so the tests can check it against the eval compiler.
    class Interpreter < Eval
      # @rbs @files: Array[String]
      # @rbs @interpreter_file: String?

      #: () -> void
      def initialize
        super
        @files = []
        @interpreter_file = nil
      end

      # A file that is not compiled into the program. The eval compiler
      # returns the address of its toplevel, and the kernel calls it. The
      # interpreter has no code of its own, so it returns the address of
      # interpreter_file.rb's toplevel, which walks the file (`walk_next`). A
      # file that the walked file requires goes on top of the list, and the
      # toplevel takes it off before it walks, so a nested require works.
      #: (String path) -> Integer?
      def compile_file(path)
        @files.push(path)
        World.unit_for(@interpreter_file)
      end

      # interpreter_file.rb's toplevel: walks the next file that
      # `compile_file` holds, in `scope` (the toplevel's own new scope)
      # under `cref`. The first run holds no file: it keeps `me`, the path
      # of interpreter_file.rb.
      #: (Binding scope, String me, untyped cref) -> untyped
      def walk_next(scope, me, cref)
        @interpreter_file ||= me
        path = @files.pop or return

        source = File.binread(path).force_encoding(Encoding::UTF_8)
        Interpreter.evaluate(source, scope, file: path, line: 1, self_: scope.receiver, cref: cref, block: nil, loaded: true)
      end

      # A string that runs later: `RubyVM::InstructionSequence.compile`, a
      # box's eval and require, and a load with a wrap module. The
      # interpreter has no code to make, so it keeps the string, and the
      # walk runs when the caller runs the code (`Kernel.run_code`). The
      # string is parsed now, so a syntax error and the parser's warnings
      # come from the compile, as in ruby.
      # `warned` marks a compile that gave the parser's warnings already,
      # and `debug_frozen` one with debug_frozen_string_literal. Code of
      # RubyVM::InstructionSequence.compile and of a box's eval is
      # `compiled!`: its frames show the label `<compiled>`, as compiled
      # code's do (zr_box_compiled).
      class Deferred
        attr_reader :source #: String
        attr_reader :file #: String
        attr_reader :line #: Integer
        attr_reader :warned #: bool
        attr_reader :debug_frozen #: bool
        attr_reader :compiled #: bool

        #: (String source, String file, Integer line, bool warned, ?debug_frozen: bool) -> void
        def initialize(source, file, line, warned, debug_frozen: false)
          @source = source
          @file = file
          @line = line
          @warned = warned
          @debug_frozen = debug_frozen
          @compiled = false
        end

        #: () -> void
        def compiled! = @compiled = true
      end

      # @rbs (untyped source, untyped file, ?_ToInt line, ?Array[Array[Symbol]] scopes, ?untyped method,
      #        ?using: Integer?, ?warn_now: bool, ?debug_frozen: bool) -> Deferred
      def compile(source, file, line = 1, _scopes = [], _method = nil, using: nil, warn_now: false, debug_frozen: false)
        source = Eval.string(source)
        file = Eval.string(file)
        # eval_make_iseq: a source that is not ASCII compatible cannot be read.
        raise ArgumentError, "invalid source encoding" unless source.encoding.ascii_compatible?

        Interpreter.check(source, file, line.to_int, warn_now)
        Deferred.new(source, file, line.to_int, warn_now, debug_frozen: debug_frozen ? true : false)
      end

      # Walks code that `compile` deferred, in a new top-level `scope`.
      #: (Deferred code, untyped self_, untyped cref, Binding scope) -> untyped
      def walk_code(code, self_, cref, scope)
        Interpreter.evaluate(code.source, scope, file: code.file, line: code.line, self_: self_, cref: cref, block: nil, quiet: code.warned,
                                                 debug_frozen: code.debug_frozen, compiled: code.compiled)
      end
    end
  end
end

# After `Zr::Eval::Interpreter#walk_next`: this require runs the file's
# toplevel once.
require_relative "../runtime/lib/zr/eval/interpreter_file"
