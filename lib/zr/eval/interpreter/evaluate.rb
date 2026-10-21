# frozen_string_literal: true

require_relative "tree"

module Zr
  class Eval
    class Interpreter < Eval
      # Walks `source` in `scope` (the Binding of the calling frame), with
      # `self_` and `cref`. `block` is the block that a `yield` in the
      # string calls. `add` marks a `Binding#eval`: a new local of the
      # string becomes a local of the Binding, as in ruby. `loaded` marks a
      # file that a load or require walks (`walk_next`): Coverage measures
      # it as a file, not as an eval.
      #
      # It reads the runtime only through `World`, so the tests run it on
      # CRuby over a `World` of plain Ruby (test/support/interpreter_world.rb).
      # @rbs (untyped source, Binding scope, file: untyped, line: _ToInt, self_: untyped, cref: untyped, block: untyped,
      #        ?add: bool, ?loaded: bool) -> untyped
      def self.evaluate(source, scope, file:, line:, self_:, cref:, block:, add: false, loaded: false)
        file = string(file)
        hir = built(string(source), file, line.to_int, scope, loaded)
        own = Tree::Scope.new(hir.locals)
        ctx = Tree::Ctx.new(self_: self_, cref: cref, chain: [own, *held(scope)], block: block,
                            name: nil, owner: nil, args: nil, kwargs: nil, tag: nil, home: nil, svars: nil)
        World.walk_enter
        value = begin
          Tree.new(file, scope).run(hir, ctx)
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

      # Builds the tree one scope inside the scopes of the frame, as the
      # eval compiler does. A write to a name that the frame has goes to the
      # frame. A new name stays in the scope of the string. Under Coverage's
      # `eval: true`, the tree gets its line events and branch counters
      # after those already in use, as a compiled eval's does. A `loaded`
      # file gets them whenever Coverage measures, as a compiled file does
      # (Compiler#compiled_file).
      #: (String source, String file, Integer line, Binding scope, bool loaded) -> Hir::Program
      def self.built(source, file, line, scope, loaded)
        # Hir only tests a name for membership, so a slot with no name
        # matches nothing.
        names = World.binding_scopes(scope) #: Array[Array[Symbol]]
        own = [] #: Array[Symbol]
        params = World.binding_parameters(scope)
        # The front end joins, splits and reads lines with ruby's defaults,
        # as the eval compiler's does (`Eval.plainly`); the walk itself runs
        # with the program's separators.
        coverage = covering
        measured = loaded ? !coverage.nil? : coverage&.send(:measures_evals?) || false
        hir = Runtime.plain_separators do
          Runtime.compiling do
            Hir.build(source, file, BuildOptions.new(trace: measured), program: false, line: line, scopes: [*names.reverse, own], method: params,
                                                                    def_base: (coverage.send(:next_def_site) if measured),
                                                                    branch_base: (coverage.send(:next_branch_id) if measured))
          end
        end
        if loaded
          coverage&.send(:compiled_lines!, hir.coverable, hir.defs, false, hir.branches)
        elsif coverage
          cover_eval(coverage, hir, source, line)
        end
        hir
      end

      # Parses `source` for a compile whose walk comes later
      # (Interpreter#compile): raises its SyntaxError now, and with
      # `warn_now` gives the parser's warnings now.
      #: (String source, String file, Integer line, bool warn_now) -> void
      def self.check(source, file, line, warn_now)
        hir = Runtime.plain_separators do
          Runtime.compiling { Hir.build(source, file, BuildOptions.new, program: false, line: line, scopes: [[]]) }
        end
        hir.warnings.each { |text| parse_warning(text) } if warn_now
      rescue Hir::Invalid => e
        raise SyntaxError.new(e.message).tap { |syntax| syntax.set_backtrace(caller_locations(1)) }
      end

      # A warning of the parser, as the eval compiler gives it
      # (Compiler#parse_warning).
      #: (String text) -> void
      def self.parse_warning(text)
        verbose = text.start_with?(Hir::Build::Loader::VERBOSE_WARNING)
        return if $VERBOSE.nil? || (verbose && !$VERBOSE)

        Warning.warn("#{verbose ? text[1..] : text}\n")
      end

      # The scopes of the frame, innermost first, in the order of lookup.
      #: (Binding scope) -> Array[Tree::Held]
      def self.held(scope)
        World.binding_scopes(scope).each_with_index.map { |names, depth| Tree::Held.new(scope, depth, names) }
      end

      # `Binding#eval`: the new locals of the string become locals of the
      # Binding, so a later read there returns the value the string set.
      #: (Binding scope, Tree::Scope own) -> void
      def self.keep(scope, own)
        names = own.names.select { |name| name.to_s.match?(/\A[a-z_][A-Za-z0-9_]*\z/) }
        # The names that the Binding has not got yet go into one new scope
        # inside it first, so `local_variables` lists them before the
        # names of a `local_variable_set`, as in ruby.
        World.binding_push(scope, names.reject { |name| scope.local_variable_defined?(name) })
        names.each { |name| scope.local_variable_set(name, own.get(name)) }
      end

      private_class_method :built, :held, :keep, :parse_warning
    end
  end
end
