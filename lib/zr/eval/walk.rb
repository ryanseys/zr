# frozen_string_literal: true

# The front end reads the library directories of the program's build
# from `Zr::Eval::Runtime` (Libraries.carried). Without it, the front end
# tries to resolve the gems in the guest, which has no gems.
require "zr/eval/runtime"
require "zr/eval/walking"
require "zr/eval/walk_forms"
require_relative "walk/tree"

module Zr
  # The tree-walking interpreter: it runs a string of Ruby in the running
  # program that evals it.
  #
  # A program uses it when it cannot write machine code into itself. The
  # engine fixes the code of a wasm module when it instantiates it, and
  # WASI gives a guest no way to make a second module. Thus the eval
  # compiler (`lib/zr/eval.rb`) has no place for its output. The front
  # end is the same for both (prism port, `Hir.build`, the same
  # desugaring). Only the back end is different: here `Eval::Tree` walks
  # the tree and does not lower it.
  #
  # `ZR_EVAL=walk` builds a native program with the tree-walking
  # interpreter, so the tests can check it against the eval compiler.
  class Eval
    # The interpreter loads with the first string that a program evals,
    # as the eval compiler does.
    def self.current = @current ||= new

    # Walks `source` in `scope` (the Binding of the calling frame), with
    # `self_` and `cref`. `block` is the block that a `yield` in the
    # string calls. `add` marks a `Binding#eval`: a new local of the
    # string becomes a local of the Binding, as in ruby.
    def run(source, file, line, scope, self_, cref, block, add = false)
      file = string(file)
      hir = built(string(source), file, line.to_int, scope)
      own = Tree::Scope.new(hir.locals)
      ctx = Tree::Ctx.new(self_: self_, cref: cref, chain: [own, *held(scope)], block: block,
                          name: nil, owner: nil, args: nil, kwargs: nil, tag: nil, home: nil)
      World.walk_enter
      begin
        value = Tree.new(file).run(hir, ctx)
      ensure
        World.walk_leave
      end
      keep(scope, own) if add
      value
    rescue Hir::Invalid => e
      raise SyntaxError.new(e.message).tap { |syntax| syntax.set_backtrace(caller_locations(1)) }
    rescue SyntaxError => e
      e.set_backtrace(caller_locations(1)) unless e.backtrace == [e.path]
      raise e
    end

    # A file that is not compiled into the program. The eval compiler
    # returns the address of its toplevel, and the kernel calls it. The
    # interpreter has no address, so it refuses, with a message that
    # gives the file.
    def compile_file(path)
      raise Tree::Refused, "#{path}:1: a require of a file the program was not compiled with is not walked yet"
    end

    # `RubyVM::InstructionSequence.compile` and the loader of a Ractor
    # need code to run later. The interpreter cannot make such code.
    def compile(_source, file, line = 1, _scopes = [], _method = nil)
      raise Tree::Refused, "#{file}:#{line}: compiling a string to code that runs later is not walked yet"
    end

    private

    # Builds the tree one scope inside the scopes of the frame, as the
    # eval compiler does. A write to a name that the frame has goes to the
    # frame. A new name stays in the scope of the string.
    def built(source, file, line, scope)
      names = World.binding_scopes(scope)
      Hir.build(source, file, eval_support: false, line: line, scopes: [*names.reverse, []],
                                           method: World.binding_parameters(scope))
    end

    # The scopes of the frame, innermost first, in the order of lookup.
    def held(scope)
      World.binding_scopes(scope).each_with_index.map { |names, depth| Tree::Held.new(scope, depth, names) }
    end

    # `Binding#eval`: the new locals of the string become locals of the
    # Binding, so a later read there returns the value the string set.
    def keep(scope, own)
      own.names.each do |name|
        next unless name.to_s.match?(/\A[a-z_][A-Za-z0-9_]*\z/)

        scope.local_variable_set(name, own.get(name))
      end
    end

    # The argument as a String, as ruby converts it: a String, or an
    # object that responds to `to_str`.
    def string(value)
      return value if value.is_a?(String)
      raise TypeError, "no implicit conversion of #{name_of(value)} into String" unless value.respond_to?(:to_str)

      value.to_str
    end

    def name_of(value)
      value.nil? || value == true || value == false ? value.inspect : value.class.name
    end
  end
end
