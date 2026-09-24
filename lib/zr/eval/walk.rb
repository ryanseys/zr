# frozen_string_literal: true

require "zr/eval/walking"
require "zr/eval/walk_forms"
require_relative "walk/tree"

module Zr
  # A string of ruby, walked while the program that asked for it runs.
  #
  # This is the road a program carries where it cannot write machine code
  # into itself. A wasm module's code is fixed when the engine
  # instantiates it, and WASI hands a guest no way to make a second
  # module, so the compiling road (`lib/zr/eval.rb`) has nowhere to put
  # what it emits. The front end is the same one either way -- prism port,
  # `Hir.build`, the same desugaring -- and only the back half differs:
  # here the tree is walked (`Eval::Tree`) rather than lowered.
  #
  # `ZR_EVAL=walk` builds a native program with this road, which is how
  # the walk is checked against the compiling road's own answers.
  class Eval
    # The walk loads with the first string a program evals, as the
    # compiler does on the other road.
    def self.current = @current ||= new

    # `source` walked in `scope` -- the Binding of the frame that asked --
    # under `self_` and `cref`, with `block` as the block a `yield` in the
    # string reaches. `add` marks a `Binding#eval`, where a local the
    # string invents becomes the Binding's own, as ruby gives it.
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

    # A file the program was not compiled with. The compiling road
    # answers the address of its toplevel, which the kernel then calls;
    # there is no address here, so this is refused by name.
    def compile_file(path)
      raise Tree::Refused, "#{path}:1: a require of a file the program was not compiled with is not walked yet"
    end

    # `RubyVM::InstructionSequence.compile` and a Ractor's own loader ask
    # the road for code to run later. The walk has none to give.
    def compile(source, file, line = 1, scopes = [], method = nil)
      raise Tree::Refused, "#{file}:#{line}: compiling a string to code that runs later is not walked yet"
    end

    private

    # The tree, built one scope inside the scopes the frame holds, as the
    # compiling road builds it: a name the string writes that the frame
    # already holds lands in the frame, and a name it invents stays its
    # own.
    def built(source, file, line, scope)
      names = World.binding_scopes(scope)
      Hir.build(source, file, eval_support: false, line: line, scopes: [*names.reverse, []],
                                           method: World.binding_parameters(scope))
    end

    # The frame's own scopes, innermost first, as the walk reaches them.
    def held(scope)
      World.binding_scopes(scope).each_with_index.map { |names, depth| Tree::Held.new(scope, depth, names) }
    end

    # `Binding#eval`: what the string invented is the Binding's from here
    # on, so a later read of it there answers what the string left.
    def keep(scope, own)
      own.names.each do |name|
        next unless name.to_s.match?(/\A[a-z_][A-Za-z0-9_]*\z/)

        scope.local_variable_set(name, own.get(name))
      end
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
  end
end
