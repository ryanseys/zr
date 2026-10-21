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
      # it as a file, not as an eval. The parser's warnings come before the
      # walk, unless a compile gave them already (`quiet`).
      #
      # It reads the runtime only through `World`, so the tests run it on
      # CRuby over a `World` of plain Ruby (test/support/interpreter_world.rb).
      # @rbs (untyped source, Binding scope, file: untyped, line: _ToInt, self_: untyped, cref: untyped, block: untyped,
      #        ?add: bool, ?loaded: bool, ?quiet: bool) -> untyped
      def self.evaluate(source, scope, file:, line:, self_:, cref:, block:, add: false, loaded: false, quiet: false)
        file = string(file)
        source = string(source)
        # eval_make_iseq: a source that is not ASCII compatible cannot be read.
        raise ArgumentError, "invalid source encoding" unless source.encoding.ascii_compatible?

        hir = built(source, file, line.to_int, scope, loaded)
        hir.warnings.each { |text| parse_warning(text) } unless quiet
        own = Tree::Scope.new(hir.locals)
        tree = Tree.new(file, scope, loaded: loaded)
        # An eval's code shows the label of its caller; a required file's
        # is `<top (required)>`.
        caller = World.eval_caller_meta unless loaded
        meta = caller ? tree.scope_meta(:eval, nil, nil, caller) : tree.scope_meta(:top, nil, nil, nil)
        ctx = Tree::Ctx.new(self_: self_, cref: cref, chain: [own, *held(scope)], block: block,
                            name: nil, owner: nil, args: nil, kwargs: nil, tag: nil, home: nil, svars: nil, meta: meta)
        World.walk_enter
        value = begin
          tree.run(hir, ctx)
        ensure
          World.walk_leave
        end
        keep(scope, own) if add
        value
      rescue Hir::Invalid => e
        warned(e) unless quiet
        raise syntax_error(e.message)
      rescue SyntaxError => e
        warned(e) unless quiet
        e.set_backtrace(caller_locations(0)) unless e.backtrace == [e.path]
        raise e
      end

      # Gives the parser's warnings that came before the syntax error
      # `error`, as the eval compiler does (Compiler#warned).
      #: (Exception error) -> void
      def self.warned(error)
        return unless error.instance_variable_defined?(:@zr_warnings)

        warnings = error.remove_instance_variable(:@zr_warnings) #: Array[String]
        warnings.each { |text| parse_warning(text) }
      end

      # Builds the tree one scope inside the scopes of the frame, as the
      # eval compiler does. A write to a name that the frame has goes to the
      # frame. A new name stays in the scope of the string. Under Coverage's
      # `eval: true`, the tree gets its line events and branch counters
      # after those already in use, as a compiled eval's does. A `loaded`
      # file gets them whenever Coverage measures, as a compiled file does
      # (Compiler#compiled_file).
      #
      # A string that runs again in a scope of the same shape walks the
      # tree of its first build, as the eval compiler runs the code of its
      # first compile (a loop of `eval("")`). Under Coverage each build
      # takes counters of its own, so none is kept.
      #: (String source, String file, Integer line, Binding scope, bool loaded) -> Hir::Program
      def self.built(source, file, line, scope, loaded)
        # Hir only tests a name for membership, so a slot with no name
        # matches nothing.
        names = World.binding_scopes(scope) #: Array[Array[Symbol]]
        params = World.binding_parameters(scope)
        return kept_tree(source, file, line, names, params, loaded: loaded) if Ractor.main?

        # The parse reads the main Ractor's tables (RbConfig, prism's), so
        # another Ractor's tree is built there, as the compiler compiles
        # there (Eval::OnMain).
        Ractor.__send__(:on_main) { kept_tree(source, file, line, names, params, loaded: loaded) }
      end

      # The tree of `source`, the one built before for the same string and
      # scope shape when there is one.
      # @rbs source: String
      # @rbs file: String
      # @rbs line: Integer
      # @rbs names: Array[Array[Symbol]]
      # @rbs params: untyped
      # @rbs loaded: bool
      # @rbs return: Hir::Program
      def self.kept_tree(source, file, line, names, params, loaded:)
        coverage = covering
        key = [-source, source.encoding, -file, line, names, params, loaded] if coverage.nil?
        trees = Eval.walk_trees
        if key && (kept = trees[key])
          return kept
        end

        hir = built_new(source, file, line, names, params, coverage: coverage, loaded: loaded)
        if key
          trees.shift if trees.size >= KEPT_TREES
          trees[key] = hir
        end
        hir
      end

      # The trees that `built` keeps, at most: the strings that a program
      # evals in a loop are few.
      KEPT_TREES = 256

      # @rbs (String source, String file, Integer line, Array[Array[Symbol]] names, untyped params, coverage: untyped,
      #       loaded: bool) -> Hir::Program
      def self.built_new(source, file, line, names, params, coverage:, loaded:)
        own = [] #: Array[Symbol]
        # The front end joins, splits and reads lines with ruby's defaults,
        # as the eval compiler's does (`Eval.plainly`); the walk itself runs
        # with the program's separators.
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
      rescue Hir::Invalid, SyntaxError => e
        warned(e) if warn_now
        raise e.is_a?(SyntaxError) ? e.tap { |syntax| syntax.set_backtrace(caller_locations(0)) } : syntax_error(e.message)
      end

      # A SyntaxError whose backtrace starts at the eval call. The walker's
      # own frames show in no backtrace, as ruby's compiler is C.
      #: (String message) -> SyntaxError
      def self.syntax_error(message)
        error = SyntaxError.new(message)
        error.set_backtrace(caller_locations(0))
        error
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

      private_class_method :built, :built_new, :held, :keep, :parse_warning, :syntax_error, :warned
    end
  end
end
