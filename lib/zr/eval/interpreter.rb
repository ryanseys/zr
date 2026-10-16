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
        Interpreter.evaluate(source, scope, file: path, line: 1, self_: scope.receiver, cref: cref, block: nil)
      end

      # `RubyVM::InstructionSequence.compile` and the loader of a Ractor
      # need code to run later. The interpreter cannot make such code.
      # @rbs (untyped source, untyped file, ?_ToInt line, ?Array[Array[Symbol]] scopes, ?untyped method,
      #        ?using: Integer?, ?warn_now: bool, ?debug_frozen: bool) -> bot
      def compile(_source, file, line = 1, _scopes = [], _method = nil, using: nil, warn_now: false, debug_frozen: false)
        raise Tree::Refused, "#{file}:#{line}: compiling a string to code that runs later is not walked yet"
      end
    end
  end
end

# After `Zr::Eval::Interpreter#walk_next`: this require runs the file's
# toplevel once.
require_relative "../runtime/lib/zr/eval/interpreter_file"
