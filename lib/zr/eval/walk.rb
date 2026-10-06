# frozen_string_literal: true

# The front end reads the library directories of the program's build
# from `Zr::Eval::Runtime` (Library::Roots.carried). Without it, the front end
# tries to resolve the gems in the guest, which has no gems.
require_relative "../runtime/lib/zr/eval/runtime"
require_relative "../runtime/lib/zr/eval/walking"
require_relative "../runtime/lib/zr/eval/walk_forms"
require_relative "walk/evaluate"

module Zr
  # The tree-walking interpreter: it runs a string of Ruby in the running
  # program that evals it.
  #
  # A program uses it when it cannot write machine code into itself. The
  # engine fixes the code of a wasm module when it instantiates it, and
  # WASI gives a guest no way to make a second module. Thus the eval
  # compiler (`lib/zr/eval.rb`) has no place for its output. The front
  # end is the same for both (prism port, `Hir.build`, the same
  # desugaring). Only the back end is different: here `Eval::Walk::Tree` walks
  # the tree and does not lower it.
  #
  # `ZR_EVAL=walk` builds a native program with the tree-walking
  # interpreter, so the tests can check it against the eval compiler.
  class Eval
    # The interpreter loads with the first string that a program evals,
    # as the eval compiler does.
    #
    # This method and the others that lib/zr/eval.rb defines too have
    # `@rbs skip`: their types are those of eval.rb. A program loads
    # only one of the two files, so this `new` takes no runtime, though
    # eval.rb's `initialize` does: Steep sees both files at once.
    # @rbs skip
    def self.current = @current ||= new # steep:ignore

    # Walks `source` in `scope` (`Walk.evaluate`).
    #: (untyped source, untyped file, _ToInt line, Binding scope, untyped self_, untyped cref, untyped block, ?add: bool) -> untyped
    def run(source, file, line, scope, self_, cref, block, add: false)
      Walk.evaluate(source, scope, file: file, line: line, self_: self_, cref: cref, block: block, add: add)
    end

    # A file that is not compiled into the program. The eval compiler
    # returns the address of its toplevel, and the kernel calls it. The
    # interpreter has no address, so it refuses, with a message that
    # gives the file.
    # @rbs skip
    def compile_file(path)
      raise Walk::Tree::Refused, "#{path}:1: a require of a file the program was not compiled with is not walked yet"
    end

    # `RubyVM::InstructionSequence.compile` and the loader of a Ractor
    # need code to run later. The interpreter cannot make such code.
    # @rbs skip
    def compile(_source, file, line = 1, _scopes = [], _method = nil, using: nil, warn_now: false, debug_frozen: false)
      raise Walk::Tree::Refused, "#{file}:#{line}: compiling a string to code that runs later is not walked yet"
    end
  end
end
