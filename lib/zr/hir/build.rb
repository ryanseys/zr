# frozen_string_literal: true

require_relative "../parse"
require_relative "../paths"
require_relative "../refused"
require_relative "../library/layout"
require_relative "../library/roots"
require_relative "../target"
require_relative "../build_options"
require_relative "../config"
require_relative "node"
require_relative "syntax_report"

module Zr
  module Hir
    class Refused < Zr::Refused; end

    # A form that ruby itself refuses when it compiles, not one that the
    # HIR does not support yet. A build treats it as any other refusal: it
    # stops and gives the line. But a program that compiles this at run
    # time must get what ruby raises, a SyntaxError, and `Zr::Eval` makes
    # it one.
    class Invalid < Refused; end

    # Prism to HIR. A form that the HIR does not support yet is refused,
    # with a message that gives the form and the line. The rule: the same
    # as CRuby, or refused. Never a guess.
    class Build
      # @rbs @file: String
      # @rbs @eval: bool
      # @rbs @loader: Loader
      # @rbs @root: Prism::ProgramNode?
      # @rbs @node_ids: Hash[Node, Integer]
      # @rbs @encoding: Encoding
      # @rbs @shadowed: Hash[[String, bool, Symbol], bool]
      # @rbs @path: Array[String?]
      # @rbs @singleton: bool
      # @rbs @body_marks: Array[Symbol]
      # @rbs @block_depth: Integer
      # @rbs @retry_scopes: Array[Symbol]
      # @rbs @using: using
      # @rbs @usings: Integer
      # @rbs @in_def: bool
      # @rbs @in_method_body: bool
      # @rbs @in_sclass: bool
      # @rbs @naming: bool
      # @rbs @dead: Integer
      # @rbs @activations: Integer
      # @rbs @temps: Array[Array[Symbol]]
      # @rbs @scopes: Array[Array[Symbol]]
      # @rbs @last_lines: Array[Integer]
      # @rbs @pending_events: Array[bool]
      # @rbs @traced_lines: Array[Integer?]
      # @rbs @ensure_exits: Array[Trace?]
      # @rbs @warnings: Array[String]
      # @rbs @def_depths: Hash[Symbol, Integer]?
      # @rbs @def_params: Params?
      # @rbs @flip_flops: Integer?
      # @rbs @guarded: Integer
      # @rbs @certain: Hash[Prism::node, bool]?
      # @rbs @after_label: Hash[Prism::node, bool]?
      # @rbs @temp_serial: Integer?
      # @rbs @c_messages: Hash[Prism::node, Encoding]?
      # @rbs @in_c_message: Encoding?
      # @rbs @elsewhere: Integer

      # The named calls that a site lowers to a kernel entry with a core
      # fast path (Zr::Lower::Function::Sends::OPT_ENTRIES), with each
      # one's argument count. A call with a different count, or with a
      # block, keywords or a splat, raises or does something different,
      # and only the real call can tell.
      OPT_CALLS = { getbyte: 1, setbyte: 2, push: 1, pop: 0, shift: 0, empty?: 0 }.freeze

      # `program` is true for a whole program, which gets the preludes, the C
      # extensions and, if it evals, the compiler. It is false for the string
      # of an eval, whose program already holds them all, and for a core
      # file. `prebuilt` is an
      # EvalSupport that is already built (`Zr::EvalSupport`), or nil. With
      # it, a program with eval refers to eval support's units and does not
      # build them, also for every file that it shares with eval support.
      # Only the end of a build knows if the program evals, so such a
      # program is built again with eval support.
      # `method` is the parameters of the method that an eval's string
      # runs inside, as from Method#parameters, or nil outside a method:
      # a `yield` has a block only inside a method, and a bare `super`
      # passes those parameters.
      # `options` steer the build (`BuildOptions`). Its `trace` arms the
      # events from the start, for an eval under an enabled TracePoint, and
      # its switches' prelude runs after the other preludes, before the
      # main file.
      # @rbs source: String
      # @rbs file: String
      # @rbs options: BuildOptions
      # @rbs roots: Array[String]
      # @rbs program: bool
      # @rbs prebuilt: untyped
      # @rbs line: Integer
      # @rbs scopes: Array[Array[Symbol]]?
      # @rbs method: Array[[Symbol, Symbol?]]?
      # @rbs activations: Integer?
      # @rbs using: Integer?
      # @rbs def_base: Integer?
      # @rbs branch_base: Integer?
      # @rbs extensions: Loader::_Extensions
      # @rbs return: Program
      def self.program(source, file, options = BuildOptions.new, roots: [], program: true, prebuilt: nil, line: 1, scopes: nil, method: nil,
                       activations: nil, using: nil, def_base: nil, branch_base: nil, extensions: Loader::NoExtensions)
        target = options.target
        switches = options.switches
        # The main file's name came from the build's command line, in the
        # build's locale. A program's locale is UTF-8
        # (Encoding.locale_charmap), and the name must not depend on the
        # build machine.
        file = file.dup.force_encoding(::Encoding::UTF_8) if program && file.encoding != ::Encoding::UTF_8
        # @type var built: ^(untyped, BuildOptions, bool, bool) -> [Loader, Unit, Require?]
        built = lambda do |external, options, evals, covers|
          loader = Loader.new(roots + (options.gem_set&.roots || []) + Library::Roots.stdlib(target), options, eval: !program, external: external,
                              evals: evals, covers: covers, activations: activations, prebuilt_eval: prebuilt,
                              description: Library::Roots.description(target), def_base: def_base || 0, branch_base: branch_base || 0,
                              extensions: extensions)
          loader.main!(file)
          loader.eval_using = using
          # Built before the main file, so that the main file's requires
          # search the -I roots that the prelude adds. It runs as a load: it
          # is not in $LOADED_FEATURES, and what its -r requires is the
          # program's, not hidden as a runtime file's requires are.
          switched = (Require.new(:load, "zr/ruby_switches", Library::Roots::SWITCHES, loader.add(Library::Roots::SWITCHES), 0) if switches.prelude)
          main = loader.unit(file, source, line, scopes, method: method)
          # A program links the extensions that --native-ext names.
          loader.extensions! if program
          [loader, main, switched]
        end
        # A build knows three facts only after it reads every file: that
        # the program uses eval, TracePoint, or Coverage. Each fact needs
        # a different build: with eval support (its files are referred to,
        # not read), with the events armed, or with the branch counters. A
        # prelude can also cause any of them (`binding.irb` loads
        # fileutils, and fileutils evals). So the build repeats: read, add
        # the preludes, and build again while any fact changed. Each fact
        # can only change from false to true, so the loop ends.
        # A compile at run time while Coverage measures methods (`def_base`)
        # records its def sites whether or not the file names Coverage.
        evals = false
        covers = !def_base.nil? #: bool
        external = nil #: untyped
        loader, main, switched = built.call(external, options, evals, covers)
        preludes = program ? Build.preludes(loader, target) : [] #: Array[node]
        loop do
          over = loader.evals? ? prebuilt : nil
          traces = loader.traces? && !options.trace
          break if over.equal?(external) && !traces && (loader.covers? || !def_base.nil?) == covers

          evals = loader.evals?
          external = over
          options = options.with(trace: true) if traces
          covers = loader.covers? || !def_base.nil?
          loader, main, switched = built.call(external, options, evals, covers)
          preludes = program ? Build.preludes(loader, target) : []
        end
        # A program numbers its `using` entries here. Code that makes an
        # entry at run time, a compile in an eval or Proc#refined, cannot
        # see how many there are, because an entry under a condition is
        # made only if the condition is true. So all entries are taken
        # before the first line, and one made at run time comes after the
        # last of them.
        preludes += [Activations.new(loader.activations, 0)] if program && loader.activations.positive?
        preludes << switched if switched
        loader.native_gems.each do |gem|
          # A gem whose C extension the build links has its C part.
          next if loader.extension_in?(gem.roots)

          warn "zr: warning: #{gem.refusal}: its Ruby files compile, and a require of its C part raises LoadError if it runs"
        end
        body = preludes.empty? ? main.body : Seq.new([*preludes, main.body], 0)
        body = Seq.new([data(main, loader.data_at(main.file)), body], 0) if loader.data_at(main.file)
        spots = [main, *loader.units].filter_map { |unit| [unit.file, unit.spots] if unit.spots && !unit.spots.empty? }.to_h
        # A compile at run time gives its lines to a Coverage that runs
        # already, whether or not the file names Coverage.
        coverable = loader.covers? || !program ? loader.coverable : {} #: Hash[String, [Integer, Array[Integer]]]
        Program.new(main.file, main.locals, body, loader.units, main_warnings(main.warnings, switches.verbose), program && loader.evals?, loader.entries, loader.tracing?,
                    main.node_ids, spots, coverable, loader.activations, loader.covers? ? loader.branches : {},
                    loader.covers? ? loader.defs : {}, loader.eval_using_after)
      end

      # The main file's parse-time warnings under the -W level it was
      # parsed with: none for -W0, the -w level ones too for -w. They print
      # as the program starts, whatever $VERBOSE is then.
      #: (Array[String] warnings, bool | Symbol | nil verbose) -> Array[String]
      def self.main_warnings(warnings, verbose)
        return warnings if verbose == :runtime
        return [] if verbose.nil?

        mark = Loader::VERBOSE_WARNING
        verbose ? warnings.map { |w| w.delete_prefix(mark) } : warnings.reject { |w| w.start_with?(mark) }
      end

      # @rbs file: String
      # @rbs loader: Loader
      # @rbs encoding: Encoding
      # @rbs shadowed: Hash[[String, bool, Symbol], bool]
      # @rbs root: Prism::ProgramNode?
      # @rbs eval: bool
      # @rbs return: void
      def initialize(file, loader, encoding = ::Encoding::UTF_8, shadowed: {}, root: nil, eval: false)
        @file = file
        @eval = eval
        @loader = loader
        @root = root
        # The prism node id of each HIR node that this file builds, by
        # identity. The file's Unit keeps it, and the lowering drops it
        # with the unit's tree (`Lower#spent`).
        node_ids = {} #: Hash[Node, Integer]
        @node_ids = node_ids.compare_by_identity
        @encoding = encoding
        # The message literals of this file's errors, each with the
        # encoding of its text (`c_message`), and that encoding while one
        # is being built.
        messages = {} #: Hash[Prism::node, Encoding]
        @c_messages = Library::Roots.stands_in_for_c?(file) ? messages.compare_by_identity : nil
        @in_c_message = nil
        @shadowed = shadowed
        @path = [Object.name]
        @singleton = false
        @body_marks = []
        @block_depth = 0
        # The clauses and blocks around the node: a `retry` is valid only
        # where the innermost is a rescue clause (`retry_in`).
        @retry_scopes = []
        # An eval starts under the refinements of its call site.
        @using = eval ? loader&.eval_using : nil
        # The number of `using` entries that this build made. `statement`
        # reads it to know if a search of its new statement can find one.
        @usings = 0
        @in_def = false
        # In a def's own body, not in a class body that a def holds, where
        # `using` is permitted.
        @in_method_body = false
        @in_sclass = false
        # In a `defined?` operand or a class path, where a constant is only
        # named (`naming`).
        @naming = false
        @dead = 0
        @elsewhere = 0
        @activations = -1
        @temps = [[]]
        @scopes = [@temps.first]
        # The line of each scope's last `:line` event, in the compiler's
        # statement order (ruby's last_line).
        @last_lines = [-1]
        @pending_events = [false]
        @traced_lines = [nil]
        @ensure_exits = [nil]
        @warnings = []
        # The depth of each parameter of the method that an eval runs in,
        # outside the eval's own scope. nil inside a def of the file,
        # whose parameters are in its own scope.
        @def_depths = nil
      end

      # An eval's string runs inside a method. A bare `super` passes the
      # parameters in `rows`, each read from the scope in `scopes`
      # (innermost first) that contains it. A parameter with no name (a
      # destructured one) cannot be passed, so neither `super` can.
      #: (Array[[Symbol, Symbol?]] rows, Array[Array[Symbol]] scopes) -> void
      def within_method(rows, scopes)
        # `using` is a method call there, which ruby refuses.
        @in_method_body = true
        return if rows.any? { |_, name| name.nil? || scopes.none? { |names| names.include?(name) } }

        # The first line returns if a name is nil.
        named = rows #: Array[[Symbol, Symbol]]
        # @type var required: Array[param]
        # @type var optional: Array[[Symbol, node?]]
        # @type var post: Array[param]
        # @type var keywords: Array[[Symbol, node?]]
        # @type var rest: Symbol?
        # @type var kwrest: Symbol?
        # @type var block: Symbol?
        required, optional, post, keywords = [], [], [], []
        rest = kwrest = block = nil
        named.each do |kind, name|
          case kind
          when :req then (optional.empty? && rest.nil? ? required : post) << name
          when :opt then optional << [name, nil]
          when :rest then rest = name
          when :key, :keyreq then keywords << [name, nil]
          when :keyrest then kwrest = name
          when :nokey then kwrest = :nokey
          when :block then block = name
          when :noblock then block = :noblock
          end
        end
        @def_params = Params.new(required, optional, rest, post, keywords, kwrest, block)
        @def_depths = named.to_h do |_, name|
          # The first line returns if a name is in no scope.
          depth = scopes.index { |names| names.include?(name) } #: Integer
          [name, 1 + depth]
        end
      end

      # The method's anonymous `*`, `**` or `&` that a call forwards. In an
      # eval, the method is the scope `@def_depths` gives, out past the
      # string's own scopes.
      #: (Symbol kind, Integer line) -> Local
      def anonymous(kind, line)
        name = ANONYMOUS.fetch(kind)
        Local.new(name, @block_depth + (@def_depths&.fetch(name, nil) || 0), line)
      end

      # The warnings ruby's compiler gives for the file's regexp literals,
      # after the parser's own.
      attr_reader :warnings #: Array[String]

      # The prism node id of each HIR node that this file built.
      attr_reader :node_ids #: Hash[Node, Integer]

      # Ruby's compiler warns as it compiles a file (not an eval) with a
      # `return` of a value at its top level, where the value goes
      # nowhere. The warning has the file and no line. A `return` in a
      # `class << self` body belongs to a method or a block, never to the top level.
      #: () -> void
      def top_return_warning
        return if @eval || @in_def || @in_sclass || @block_depth.positive? || @path != [Object.name]

        @warnings << "#{Paths.shown(@file)}: warning: argument of top-level return is ignored"
      end

      # The hidden locals the toplevel scope needs.
      #: () -> Array[Symbol]
      def temps = @temps.first

      # The names of the anonymous parameters `*`, `**`, `&` and `...`,
      # as locals of the def that declares them.
      ANONYMOUS = { rest: :*, kwrest: :**, block: :& }.freeze

      # Builds `body` in a branch that a literal condition never takes,
      # if `never` is true.
      #: [T] (bool never) { () -> T } -> T
      def dead(never)
        @dead += 1 if never
        yield
      ensure
        @dead -= 1 if never
      end

      # Builds a branch that runs only on another ruby (`when "jruby"` of a
      # `case RUBY_ENGINE`, `if RUBY_ENGINE == "truffleruby"`): zr's
      # RUBY_ENGINE is "ruby". The branch compiles as any other, but what
      # it would do to the whole program (an eval, a change of $LOAD_PATH)
      # does not make the build link the compiler.
      #: [T] (bool other) { () -> T } -> T
      def elsewhere(other)
        @elsewhere += 1 if other
        yield
      ensure
        @elsewhere -= 1 if other
      end

      # The RUBY_ENGINE of a zr program (core/env.rb).
      RUBY_ENGINE_NAME = "ruby"

      # Whether `values`, compared with RUBY_ENGINE, name only other rubies.
      #: (Array[Prism::node?] values) -> bool
      def other_engines?(values)
        values.all? { |v| v.is_a?(Prism::StringNode) && v.unescaped != RUBY_ENGINE_NAME }
      end

      # Whether `node` reads RUBY_ENGINE.
      #: (Prism::node? node) -> bool
      def ruby_engine?(node)
        (node.is_a?(Prism::ConstantReadNode) || (node.is_a?(Prism::ConstantPathNode) && node.parent.nil?)) && node.name == :RUBY_ENGINE
      end

      # Whether an `if` predicate is `RUBY_ENGINE == "other"` (either way
      # round).
      #: (Prism::node predicate) -> bool
      def other_engine_test?(predicate)
        return false unless predicate.is_a?(Prism::CallNode) && predicate.name == :==

        args = predicate.arguments&.arguments
        return false unless args && args.size == 1

        other = args[0]
        (ruby_engine?(predicate.receiver) && other_engines?([other])) || (ruby_engine?(other) && other_engines?([predicate.receiver]))
      end

      # Builds `body` one block scope deeper. A `using` in a block at the
      # top level of a file refines the file's own scope, so it applies to
      # the rest of the file after the block, as in ruby.
      #: [T] () { () -> T } -> T
      def in_block
        @block_depth += 1
        @retry_scopes.push(:block)
        using = @using
        @temps.push([])
        @last_lines.push(-1)
        @pending_events.push(false)
        @traced_lines.push(nil)
        @ensure_exits.push(nil)
        begin
          yield
        ensure
          @block_depth -= 1
          @retry_scopes.pop
          @using = using unless @path == [Object.name] && !@in_def
          @temps.pop
          @last_lines.pop
          @pending_events.pop
          @traced_lines.pop
          @ensure_exits.pop
        end
      end

      # Builds `body` in a new scope: a def or a class body.
      #: [T] () { () -> T } -> T
      def in_scope
        was_depth = @block_depth
        was_params = @def_params
        was_depths = @def_depths
        @block_depth = 0
        @def_params = nil
        @def_depths = nil
        @temps.push([])
        @scopes.push(@temps.last)
        @last_lines.push(-1)
        @pending_events.push(false)
        @traced_lines.push(nil)
        @ensure_exits.push(nil)
        begin
          yield
        ensure
          @block_depth = was_depth
          @def_params = was_params
          @def_depths = was_depths
          @temps.pop
          @scopes.pop
          @last_lines.pop
          @pending_events.pop
          @traced_lines.pop
          @ensure_exits.pop
        end
      end

      # A scope's locals: the parser's, then the hidden ones from its body.
      #: (Array[Symbol] locals) -> Array[Symbol]
      def with_temps(locals) = locals + @temps.last

      # The globals that are in the frame or the task, not the global
      # table. An alias of one is a second name that the lowering resolves.
      FRAME_GVARS = %i[$~ $_ $! $@].freeze

      # The other names ruby gives one global.
      GVAR_ALIASES = {
        :$PROGRAM_NAME => :$0, :$: => :$LOAD_PATH, :$-I => :$LOAD_PATH, :$" => :$LOADED_FEATURES, :$> => :$stdout,
        :$-0 => :$/, :$-F => :$;, :$-v => :$VERBOSE, :$-w => :$VERBOSE, :$-d => :$DEBUG
      }.freeze

      #: (Symbol name) -> Symbol
      def gvar_name(name)
        GVAR_ALIASES.fetch(name, name)
      end

      # A `$name` read: through an alias of a frame global, `$@` as the
      # checked backtrace of `$!` (the private Exception.errat), or the
      # global itself.
      #: (Symbol name, Integer line) -> node
      def gvar_read(name, line)
        aliased = @loader&.back_ref(name)
        if aliased && (flag = @loader.alias_flag(name))
          return If.new(GvarRead.new(flag, line), expr(aliased), GvarRead.new(gvar_name(name), line), line)
        end
        return expr(aliased) if aliased
        return Send.of(Core.new(:Exception, line), :__send__, [Literal.new(:errat, line), GvarRead.new(:$!, line)], line) if name == :$@
        return Send.of(Core.new(:Kernel, line), :warning_level, [], line) if name == :$-W

        GvarRead.new(gvar_name(name), line)
      end

      # The read of `$name ||= value`, which ruby tests with `defined?`
      # first, so an unset global gives no warning under -w.
      #: (Symbol name, Integer line) -> node
      def quiet_gvar_read(name, line)
        read = gvar_read(name, line)
        return read unless read.is_a?(GvarRead) && !SPECIAL_GVARS.include?(read.name)

        If.new(Defined.new(:gvar, read.name, line), read, Literal.new(nil, line), line)
      end

      # `$name = value`: a write through an alias of a frame global goes to
      # that global, and keeps the program's name for error messages.
      # Every back reference is read-only, as `$&` is.
      #: (Symbol name, node? value, Integer line) -> node
      def gvar_write(name, value, line)
        aliased = @loader&.back_ref(name)
        target = if aliased.is_a?(Prism::GlobalVariableReadNode) then aliased.name
                 elsif aliased then :$&
                 else gvar_name(name)
                 end
        write = GvarWrite.new(target, value, line, target == name ? nil : name)
        flag = aliased && @loader.alias_flag(name)
        flag ? If.new(GvarRead.new(flag, line), write, GvarWrite.new(gvar_name(name), value, line, nil), line) : write
      end

      # `$&`, `` $` ``, `$'` and `$+`: from the last match, or nil if there
      # is none.
      #: (Prism::BackReferenceReadNode node, Integer line) -> BackRef
      def back_reference(node, line)
        case node.name
        when :$& then BackRef.new(:nth, 0, line)
        when :$` then BackRef.new(:pre, nil, line)
        when :$' then BackRef.new(:post, nil, line)
        when :$+ then BackRef.new(:last, nil, line)
        else unsupported(node, "the #{node.name} variable")
        end
      end

      # `a..b` in a condition is a flip-flop: it is true from the run where
      # the left side is true to the run where the right side is true. The
      # state is a hidden local of the enclosing def, so a block shares its
      # method's state, as in ruby. A thread or a fiber whose block was
      # written in the def keeps a state of its own (`zr_flip_flop_get`).
      #: (Prism::FlipFlopNode node, Integer line) -> If
      def flip_flop(node, line)
        state = flip_flop_state
        depth = @block_depth
        ends = -> { If.new(end_test(node.right, line), Assign.new(state, depth, Literal.new(false, line), line), nil, line) }
        # `...` waits for the next run before it can turn off. `..` tests
        # the right side at once, so a one-run range ends where it started.
        started = [Assign.new(state, depth, Literal.new(true, line), line)] #: Array[node]
        started << ends.call unless node.exclude_end?
        started << Literal.new(true, line)
        If.new(Local.new(state, depth, line),
               Seq.new([ends.call, Literal.new(true, line)], line),
               If.new(end_test(node.left, line), Seq.new(started, line), Literal.new(false, line), line),
               line)
      end

      # An end of a flip-flop. A missing end never fires. An integer
      # literal is a test of the last line read, `$. == n`, as ruby's
      # compiler makes it.
      #: (Prism::node? node, Integer line) -> node
      def end_test(node, line)
        return Literal.new(nil, line) unless node
        return Send.of(gvar_read(:$., line), :==, [expr(node)], line) if node.is_a?(Prism::IntegerNode)

        expr(node)
      end

      #: () -> Symbol
      def flip_flop_state
        @flip_flops = (@flip_flops || 0) + 1
        name = :"#{FLIP_FLOP}#{@flip_flops}"
        @scopes.last << name
        name
      end

      # `hoist` puts the `BEGIN { }` blocks of a file first, in their
      # order, before anything else runs.
      #
      # A sequence returns its last statement's value, so the value of each
      # earlier statement is never used, in every context.
      #: (Prism::StatementsNode? node, ?hoist: bool, ?taken: bool) -> Seq
      def seq(node, hoist: false, taken: true)
        return Seq.new([], 1) if node.nil?

        body = node.body
        if hoist
          body = body.flat_map { |s| hoisted_from_loop(s) }
          early, rest = body.partition { |s| s.is_a?(Prism::PreExecutionNode) }
          body = early.flat_map { |s| pre_executions(s) } + rest #: Array[Prism::node]
        end
        last = body.size - 1
        Seq.new(body.each_with_index.map { |s, i| statement(s, taken: taken && i == last) }, node.location.start_line)
      end

      # -n and -p wrap the file in a `while gets` loop (prism's
      # `command_line`), with its `BEGIN { }` blocks inside. Ruby runs them
      # once, before the loop, as anywhere else: the blocks, then the loop
      # without them. No other loop can hold a BEGIN, which parses only at
      # the toplevel.
      #: (Prism::node node) -> Array[Prism::node]
      def hoisted_from_loop(node)
        return [node] unless node.is_a?(Prism::WhileNode) && (inner = node.statements)

        early, rest = inner.body.partition { |s| s.is_a?(Prism::PreExecutionNode) }
        early.empty? ? [node] : [*early, node.copy(statements: inner.copy(body: rest))]
      end

      # A `BEGIN { }` in a BEGIN block runs before the block that holds it,
      # as ruby adds each block to its list when the parser closes it.
      #: (Prism::node node) -> Array[Prism::node]
      def pre_executions(node)
        return [node] unless node.is_a?(Prism::PreExecutionNode)

        statements = node.statements or return [node]
        nested, rest = statements.body.partition { |s| s.is_a?(Prism::PreExecutionNode) }
        return [node] if nested.empty?

        [*nested.flat_map { |s| pre_executions(s) }, node.copy(statements: statements.copy(body: rest))]
      end

      # One statement. Each send in it gets the activation that is active
      # at the statement. A `using` changes the activation for the
      # statements after it.
      #: (Prism::node node, ?taken: bool) -> node
      def statement(node, taken: true)
        # `using_activation` makes every `using` entry, so a statement that
        # made none contains none. Then skip the walk below, which reads
        # all of the new statement, for every statement of every file.
        # Almost no file has a `using`.
        made = @usings
        if !taken && silent?(node)
          silent_line(node)
        else
          traced = line_event(node, taken: taken)
        end
        out = using_activation(node) || assigned_using(node) || expr(node, taken: taken)
        # The statement's event found its instruction inside it.
        @traced_lines[-1] = nil
        exit_event(node.location.start_line) unless node.is_a?(Prism::BeginNode)
        out = Seq.new([traced, out], traced.line) if traced
        mark_using(out, Hash.new.compare_by_identity) if @using
        @usings == made ? out : with_using_defaults(out, node.location.start_line)
      end

      # `x op= v`, `x ||= v` or `x &&= v`, where `read` reads x and the block
      # writes x with the value that it gets. `x op= v` is `x = x op v`.
      # `x ||= v` is `x || (x = v)`, and `x &&= v` is `x && (x = v)`: the
      # write occurs only if necessary. A frozen receiver, a global's setter
      # and a constant's redefinition warning can see this.
      #: (untyped node, node read) { (node value) -> node } -> node
      def op_write(node, read)
        line = read.line
        type = node.type
        if type.end_with?("_or_write_node") then Or.new(read, yield(expr(node.value)), line)
        elsif type.end_with?("_and_write_node") then And.new(read, yield(expr(node.value)), line)
        else yield noted(Send.of(read, node.binary_operator, [expr(node.value)], line), node)
        end
      end

      # A prism node's HIR, noted with the node's id.
      #
      # `taken` is false if the program never uses this expression's
      # value: a statement before the last of its scope, a `while` body,
      # or a branch that a literal condition never selects. Ruby's
      # compiler writes no code for such an expression and does not read
      # it. So `puts 1; /[z-a]/; puts 2` runs, but the same literal as a
      # scope's value is a SyntaxError. A regexp is the only literal that
      # zr reads when it builds, so only it uses this flag.
      #: (untyped node, ?taken: bool) -> node
      def expr(node, taken: true)
        noted(built(node, taken: taken), node)
      end

      # `hir` came from prism's `node`. Its frame reports that node's id,
      # as node_id_for_backtrace_location reads it. A HIR node that an
      # inner prism node already built keeps the inner node's id.
      #: (untyped hir, Prism::node node) -> untyped
      def noted(hir, node)
        @node_ids[hir] ||= node.node_id if @node_ids && hir.is_a?(Node)
        hir
      end

      #: (untyped node, ?taken: bool) -> node
      def built(node, taken: true)
        line = node.location.start_line
        case node.type
        when :statements_node then seq(node, taken: taken)
        when :parentheses_node then node.body ? expr(node.body, taken: taken) : Literal.new(nil, line)
        when :integer_node, :float_node then Literal.new(node.value, line)
        # `3r` and `2i` use the core's Kernel, even if self has no Kernel.
        when :rational_node then Send.of(Core.new(:Kernel, line), :Rational, [Literal.new(node.numerator, line), Literal.new(node.denominator, line)], line)
        when :imaginary_node then Send.of(Core.new(:Kernel, line), :Complex, [Literal.new(0, line), expr(node.numeric)], line)
        when :string_node then literal_string(node, unescaped(node), line)
        when :symbol_node then literal_symbol(node, line)
        when :nil_node then Literal.new(nil, line)
        when :true_node then Literal.new(true, line)
        when :false_node then Literal.new(false, line)
        when :self_node then SelfRef.new(line)
        when :call_node then call(node)
        when :def_node then define(node)
        when :local_variable_read_node then Local.new(node.name, node.depth, line)
        when :local_variable_write_node then Assign.new(node.name, node.depth, expr(node.value), line)
        when :multi_write_node then MultiAssign.new(multi_target(node), expr(node.value), line, taken)
        when :local_variable_operator_write_node
          op_write(node, Local.new(node.name, node.depth, line)) { |value| Assign.new(node.name, node.depth, value, line) }
        # No program sees the write of a local, so `x &&= v` is `x = x && v`
        # and `x ||= v` is `x = x || v`.
        when :local_variable_and_write_node
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when :local_variable_or_write_node
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when :lambda_node then lambda_literal(node, line)
        when :it_local_variable_read_node then Local.new(IT, 0, line)
        when :undef_node then undef_names(node, line)
        when :super_node then super_call(node, line)
        when :forwarding_super_node then zsuper(node, line)
        when :yield_node
          args, kwargs, = arguments(node.arguments)
          Yield.new(args, line, kwargs)
        when :break_node, :next_node
          value = jump_value(node.arguments, line)
          node.is_a?(Prism::BreakNode) ? Break.new(value, line) : Next.new(value, line)
        when :if_node then if_branch(node, line, taken: taken)
        when :case_match_node then case_match(node, taken: taken)
        when :match_required_node then match_required(node)
        when :match_predicate_node then match_predicate(node)
        when :match_write_node then match_write(node)
        when :unless_node then unless_branch(node, line, taken: taken)
        when :else_node then node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line)
        when :while_node then while_loop(node, line)
        when :until_node then until_loop(node, line)
        when :return_node
          top_return_warning if node.arguments
          Return.new(jump_value(node.arguments, line), line)
        # The left side decides, so its value is always used. The right
        # side is the result, so it has the pair's `taken`.
        when :and_node then And.new(expr(node.left), expr(node.right, taken: taken), line)
        when :or_node then Or.new(expr(node.left), expr(node.right, taken: taken), line)
        when :class_node then class_body(node, line)
        when :module_node then module_body(node, line)
        when :singleton_class_node then singleton_class_body(node, line)
        when :constant_read_node then const_read(node, line)
        when :constant_path_node then const_path_read(node, line)
        when :constant_write_node then ConstWrite.new(nil, node.name, expr(node.value), line)
        when :constant_path_write_node
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when :interpolated_string_node then interpolated_string(node, line)
        when :source_file_node then source_file(node, line)
        when :source_line_node then Literal.new(line, line)
        when :source_encoding_node
          Send.of(ConstRead.new(nil, :Encoding, line), :find, [Literal.new(@encoding.name, line)], line)
        when :interpolated_symbol_node then Send.of(interpolation(node, line), :to_sym, [], line)
        # A static command is a frozen String, as CRuby passes it to `.
        when :x_string_node then Send.of(nil, :`, [frozen_literal_string(node.unescaped, line)], line)
        # Prism gives 0 for a number too big for a variable, which is always nil.
        when :numbered_reference_read_node then node.number.zero? ? Literal.new(nil, line) : BackRef.new(:nth, node.number, line)
        when :back_reference_read_node then back_reference(node, line)
        when :regular_expression_node then regexp_literal(node, line, taken: taken)
        when :interpolated_regular_expression_node then interpolated_regexp(node, line)
        when :match_last_line_node
          # A bare regexp as a condition matches `$_`.
          Send.of(regexp_literal(node, line), :=~, [GvarRead.new(:$_, line)], line)
        when :interpolated_match_last_line_node
          Send.of(interpolated_regexp(node, line), :=~, [GvarRead.new(:$_, line)], line)
        when :interpolated_x_string_node then Send.of(nil, :`, [interpolation(node, line)], line)
        when :array_node then ArrayLit.new(node.elements.map { |e| array_element(e, line) }, line)
        when :hash_node then HashLit.new(hash_pairs(node.elements), line)
        when :flip_flop_node then flip_flop(node, line)
        when :shareable_constant_node then shareable_constant(node, line)
        when :range_node then range_literal(node, line)
        when :instance_variable_read_node then IvarRead.new(node.name, line)
        when :global_variable_read_node then gvar_read(node.name, line)
        when :global_variable_write_node then gvar_write(node.name, expr(node.value), line)
        when :global_variable_operator_write_node, :global_variable_and_write_node
          op_write(node, gvar_read(node.name, line)) { |value| gvar_write(node.name, value, line) }
        when :global_variable_or_write_node
          op_write(node, quiet_gvar_read(node.name, line)) { |value| gvar_write(node.name, value, line) }
        when :class_variable_read_node then CvarRead.new(node.name, line)
        when :class_variable_write_node then CvarWrite.new(node.name, expr(node.value), line)
        when :class_variable_operator_write_node, :class_variable_and_write_node
          op_write(node, noted(CvarRead.new(node.name, line), node)) { |value| noted(CvarWrite.new(node.name, value, line), node) }
        # `@@x ||= v` reads an undefined `@@x` as nil, as `defined?` does,
        # where a read would raise NameError.
        when :class_variable_or_write_node
          If.new(Defined.new(:cvar, node.name, line), Or.new(noted(CvarRead.new(node.name, line), node), noted(CvarWrite.new(node.name, expr(node.value), line), node), line),
                 noted(CvarWrite.new(node.name, expr(node.value), line), node), line)
        # Ruby compiles nothing for a `defined?` whose value is not used.
        when :defined_node then taken ? defined(node.value, line) : Literal.new(nil, line)
        # `X ||= v` and `A::X ||= v` write only when X is unset or falsy
        # (ConstOrWrite). An unset X is not an error, where a read raises
        # NameError.
        when :constant_or_write_node then ConstOrWrite.new(nil, node.name, expr(node.value), line)
        when :constant_path_or_write_node
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, noted(ConstOrWrite.new(scope, name, expr(node.value), line), node), line)
        when :constant_operator_write_node, :constant_and_write_node
          op_write(node, noted(ConstRead.new(nil, node.name, line), node)) { |value| noted(ConstWrite.new(nil, node.name, value, line), node) }
        when :constant_path_operator_write_node, :constant_path_and_write_node
          scope, name, prelude = constant_scope(node.target, line)
          read = noted(ConstRead.new(scope, name, line, prelude ? true : nil), node)
          with_scope(prelude, op_write(node, read) { |value| noted(ConstWrite.new(scope, name, value, line), node) }, line)
        when :alias_method_node then alias_method_names(node, line)
        when :alias_global_variable_node then alias_global(node, line)
        when :case_node then case_when(node, line, taken: taken)
        when :index_operator_write_node, :index_or_write_node, :index_and_write_node then index_op_assign(node, line)
        when :call_operator_write_node, :call_or_write_node, :call_and_write_node then attr_op_assign(node, line)
        when :for_node then for_loop(node)
        when :post_execution_node then post_execution(node, line)
        when :pre_execution_node
          unsupported(node, "BEGIN { } outside the toplevel") unless @block_depth.zero?
          node.statements ? seq(node.statements) : Literal.new(nil, line)
        when :instance_variable_write_node then IvarWrite.new(node.name, expr(node.value), line)
        when :instance_variable_operator_write_node, :instance_variable_or_write_node, :instance_variable_and_write_node
          op_write(node, IvarRead.new(node.name, line)) { |value| IvarWrite.new(node.name, value, line) }
        when :begin_node then protected_region(node, taken: taken)
        when :rescue_modifier_node
          clause = Rescue.new([], nil, retry_in(:rescue) { expr(node.rescue_expression) }, line)
          Begin.new(expr(node.expression), [clause], nil, nil, line)
        # Ruby's compiler writes no code for a branch that it knows is
        # never taken, so a `retry` there is never an error.
        when :retry_node
          if @dead.positive? then Literal.new(nil, line)
          # Ruby compiles an ensure clause, a block and END as code of
          # their own, where a `retry` has no rescue clause to run again.
          elsif @retry_scopes.last != :rescue then invalid(node, "Invalid retry")
          else Retry.new(line)
          end
        when :redo_node then Redo.new(line)
        else unsupported(node)
        end
      end

      # `begin ... end` with its clauses. A bare `begin ... end` is its
      # body. A region's body and its `else` give the region's value, and
      # have its `taken`. An `ensure` runs only for its effect, so its
      # value is never used. A `rescue` body is different: ruby reads a
      # regexp there even if the region's value is not used. So is the
      # body before a `rescue`, which ruby compiles with its value kept for
      # the clauses (pm_compile_rescue).
      #: (Prism::BeginNode node, ?taken: bool) -> node
      def protected_region(node, taken: true)
        line = node.location.start_line
        kept = taken || !node.rescue_clause.nil?
        body = guarded(node.rescue_clause) { node.statements ? seq(node.statements, taken: kept) : Literal.new(nil, line) }
        return body if node.rescue_clause.nil? && node.ensure_clause.nil?

        rescues = [] #: Array[Rescue]
        # @type var clause: Prism::RescueNode?
        clause = node.rescue_clause
        while clause
          rescues << rescue_clause(clause)
          clause = clause.subsequent
        end
        else_clause = node.else_clause
        else_statements = else_clause&.statements
        else_body = else_clause && (else_statements ? seq(else_statements, taken: taken) : Literal.new(nil, line))
        ensure_clause = node.ensure_clause
        ensure_body = ensure_clause && silent_ensure(retry_in(:ensure) { ensure_clause.statements ? seq(ensure_clause.statements, taken: false) : Literal.new(nil, line) }, ensure_clause)
        Begin.new(body, rescues, else_body, ensure_body, line)
      end

      # The exceptions that rescue a missing file: ruby raises LoadError,
      # a ScriptError, which a bare `rescue` (StandardError) does not catch.
      LOAD_RESCUES = %i[LoadError ScriptError Exception].freeze

      # Builds the block's body as the body of a region whose clauses
      # start at `clause`. When one of them rescues LoadError, a require in
      # the body is guarded: it can fail when it runs (`gate!`).
      #: [T] (Prism::RescueNode? clause) { () -> T } -> T
      def guarded(clause)
        rescues = false
        # @type var at: Prism::RescueNode?
        at = clause
        while at
          rescues ||= at.exceptions.any? { |e| e.is_a?(Prism::ConstantReadNode) && LOAD_RESCUES.include?(e.name) }
          at = at.subsequent
        end
        @guarded = (@guarded || 0) + 1 if rescues
        begin
          yield
        ensure
          @guarded -= 1 if rescues
        end
      end

      # Builds the body of a rescue clause, an ensure clause or a block
      # (`kind`), for the check of `retry`.
      #: [T] (Symbol kind) { () -> T } -> T
      def retry_in(kind)
        @retry_scopes.push(kind)
        yield
      ensure
        @retry_scopes.pop
      end

      #: (Prism::RescueNode node) -> Rescue
      def rescue_clause(node)
        line = node.location.start_line
        classes = node.exceptions.map { |e| e.is_a?(Prism::SplatNode) ? splat(e, line) : expr(e) }
        reference = node.reference
        statements = node.statements
        Rescue.new(classes, reference && target(reference), retry_in(:rescue) { statements ? seq(statements) : Literal.new(nil, line) }, line)
      end

      # The value of `return`, `break` and `next`: none is nil, one value
      # is itself, and several are an Array.
      #: (Prism::ArgumentsNode? arguments, Integer line) -> node
      def jump_value(arguments, line)
        args = arguments&.arguments || []
        return Literal.new(nil, line) if args.empty?

        elements = args.map { |a| array_element(a, line) }
        return elements.first if elements.size == 1 && !elements.first.is_a?(Splat)

        ArrayLit.new(elements, line)
      end

      # `[scope, name]` of a constant path: nil for a bare name, :top for
      # `::Name`, else the expression before the last `::`.
      #: (Prism::node node) -> [scope, Symbol?]
      def constant_path(node)
        case node
        when Prism::ConstantReadNode then [nil, node.name]
        when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
          [node.parent ? expr(node.parent) : :top, node.name]
        else unsupported(node, "a dynamic constant path")
        end
      end

      # The scope of a constant that `A::B op= v` reads and writes. A path
      # of constants gives the same value twice. A computed scope goes into
      # a hidden local, so it is evaluated once.
      #: (Prism::node node, Integer line) -> [scope, Symbol?, node?]
      def constant_scope(node, line)
        # @type var scope: untyped
        scope, name = constant_path(node)
        return [scope, name, nil] if scope.nil? || scope == :top || constant_only?(scope)

        slot = temp(:scope)
        [read(slot, line), name, set(slot, scope, line)]
      end

      #: (node? prelude, node node, Integer line) -> node
      def with_scope(prelude, node, line)
        prelude ? Seq.new([prelude, node], line) : node
      end

      #: (scope scope) -> bool
      def constant_only?(scope)
        scope.is_a?(ConstRead) && (scope.scope.nil? || scope.scope == :top || constant_only?(scope.scope))
      end

      #: (Prism::DefNode node) -> Def
      def define(node)
        @loader.loads_by_def!(node)
        marks = @body_marks
        receiver = node.receiver && expr(node.receiver)
        in_definee(nil, !receiver.nil?) do
          was = @in_def
          @in_def = true
          @in_method_body = true
          begin
            in_scope do
              params = parameters(node.parameters)
              @def_params = params
              body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
              exit_event(node.location.end_line)
              body = marked(body, marks, node.location.start_line) unless marks.empty?
              locals = with_temps(node.locals + (params.names - node.locals))
              Def.new(node.name, params, locals, body, node.location.start_line, receiver, evals?(node.body), node.location.end_line,
                      method_cover(node), entry_using, span(node.location))
            end
          ensure
            @in_def = was
          end
        end
      end

      # The body with the `Primitive.attr!` calls of `marks` first, where
      # a def's own attributes are.
      #: (node body, Array[Symbol] marks, Integer line) -> node
      def marked(body, marks, line)
        return Begin.new(*body.to_a).tap { |b| b.body = marked(body.body, marks, line) } if body.is_a?(Begin)

        rows = marks.map { |mark| Send.of(ConstRead.new(nil, :Primitive, line), :attr!, [Literal.new(mark, line)], line) }
        Seq.new([*rows, *(body.is_a?(Seq) ? body.stmts : [body])], line)
      end

      # Whether an eval is anywhere in this body, blocks included, nested
      # defs not included. A `return` in an eval belongs to the enclosing
      # method, so that method arms the catch for an unwind with no home.
      # Every form of eval counts, because ruby gives them all that
      # return: `instance_eval`, `class_eval` and `module_eval` of a
      # string, and a `send` or `method` that calls one of them by name.
      # A `return` in a `class << self` body has no home either: it returns
      # from the method that holds the body.
      #: (Prism::node? node, ?sclass: bool) -> bool
      def evals?(node, sclass: false)
        return false if node.nil? || node.is_a?(Prism::DefNode)
        return true if node.is_a?(Prism::CallNode) && eval_call?(node)
        return true if sclass && node.is_a?(Prism::ReturnNode)

        sclass ||= node.is_a?(Prism::SingletonClassNode)
        node.child_nodes.any? { |child| evals?(child, sclass: sclass) }
      end

      # `Build.eval_call?` for a prism call, whose arguments are still
      # nodes. A leading Symbol literal is the method name that a send
      # calls or a fetch returns.
      #: (Prism::CallNode node) -> bool
      def eval_call?(node)
        args = node.arguments&.arguments || [] #: Array[untyped]
        named = args.first.unescaped.to_sym if args.first.is_a?(Prism::SymbolNode)
        Build.eval_call?(node.name, named: named, argc: args.size)
      end

      # Runs a body with its definee: one step down the lexical path, and
      # whether it is the singleton side. A `using` in a body applies to
      # the rest of that body and to nothing outside it.
      #: [T] (String? name, bool singleton) { () -> T } -> T
      def in_definee(name, singleton)
        @path.push(name) if name
        was = @singleton
        using = @using
        marks = @body_marks
        in_method_body = @in_method_body
        @singleton = singleton
        @body_marks = []
        @in_method_body = false
        begin
          yield
        ensure
          @path.pop if name
          @singleton = was
          @using = using
          @body_marks = marks
          @in_method_body = in_method_body
        end
      end

      # A bare `super`: passes the method's parameters with their current
      # values, as a `Super` with the locals of the enclosing def.
      #: (Prism::ForwardingSuperNode node, Integer line) -> (ZSuper | Super)
      def zsuper(node, line)
        given = node.block
        p = @def_params or return ZSuper.new(given && block(given), line)

        local = lambda do |name|
          name = name.whole if name.is_a?(MultiTarget)
          depths = @def_depths
          Local.new(name, @block_depth + (depths ? depths.fetch(name) : 0), line)
        end
        positional = (p.required + p.optional.map(&:first)).map(&local) #: Array[node]
        positional << Splat.new(local.call(p.rest), line) if p.rest?
        positional += p.post.map(&local)
        # The rest goes in first, in the order that ruby's own zsuper
        # builds the hash.
        pairs = p.kwrest && p.kwrest != :nokey ? [HashSplat.new(local.call(p.kwrest), line), nil] : [] #: Array[node?]
        pairs += p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        kwargs = pairs.empty? ? nil : HashLit.new(pairs, line)
        # `&nil` has no block to pass: its method got none.
        block = given ? block(given) : (BlockPass.new(local.call(p.block), line) if p.block && !p.no_block?)
        Super.new(positional, kwargs, block, line, @block_depth.positive?)
      end

      # A ParametersNode as one Params.
      #: (Prism::ParametersNode? node) -> Params
      def parameters(node)
        return Params.new([], [], nil, [], [], nil, nil) if node.nil?

        required = node.requireds.map { |p| name_of(p) }
        optional = node.optionals.map { |p| optional_param(p) }
        rest_param = node.rest
        rest = rest_param && rest_name(rest_param)
        post = node.posts.map { |p| name_of(p) }
        keywords = node.keywords.map do |k|
          case k
          when Prism::RequiredKeywordParameterNode then [k.name, nil]
          when Prism::OptionalKeywordParameterNode then [k.name, expr(k.value)]
          end
        end
        keyword_rest = node.keyword_rest
        kwrest = keyword_rest && rest_name(keyword_rest)
        if keyword_rest.is_a?(Prism::ForwardingParameterNode)
          rest = ANONYMOUS[:rest]
          kwrest = ANONYMOUS[:kwrest]
          block = ANONYMOUS[:block]
        else
          block = case (block_param = node.block)
                  when nil then nil
                  # `&nil`: the def refuses a block.
                  when Prism::NoBlockParameterNode then :noblock
                  else block_param.name || ANONYMOUS[:block]
                  end
        end
        Params.new(required, optional, rest, post, keywords, kwrest, block)
      end

      # A required parameter: its name, or a MultiTarget for `(a, b)`. A
      # bare super passes such an argument as it was given, so the full
      # value is kept in a hidden local next to the destructured names.
      #: (untyped param) -> param
      def name_of(param)
        return repeat_name(param) || param.name unless param.is_a?(Prism::MultiTargetNode)

        target = multi_target(param)
        target.whole = temp(:arg)
        target
      end

      #: (Prism::MultiTargetNode | Prism::MultiWriteNode node) -> MultiTarget
      def multi_target(node)
        line = node.location.start_line
        rest = case (rest_node = node.rest)
               when nil then nil
               when Prism::ImplicitRestNode then :implicit
               when Prism::SplatNode then (expression = rest_node.expression) ? target(expression) : :implicit
               else unsupported(rest_node)
               end
        noted(MultiTarget.new(node.lefts.map { |t| target(t) }, rest, node.rights.map { |t| target(t) }, line), node)
      end

      # One target of a multiple assignment, noted with its node: a frame
      # that writes it, or converts the value for a nested target, stands at it.
      #: (Prism::node node) -> node
      def target(node)
        noted(target_of(node), node)
      end

      #: (Prism::node node) -> node
      def target_of(node)
        line = node.location.start_line
        case node
        when Prism::LocalVariableTargetNode then Assign.new(node.name, node.depth, nil, line)
        # A parameter is always in its own scope.
        when Prism::RequiredParameterNode then Assign.new(node.name, 0, nil, line)
        when Prism::InstanceVariableTargetNode then IvarWrite.new(node.name, nil, line)
        when Prism::GlobalVariableTargetNode then gvar_write(node.name, nil, line)
        when Prism::ClassVariableTargetNode then CvarWrite.new(node.name, nil, line)
        when Prism::ConstantTargetNode then ConstWrite.new(nil, node.name, nil, line)
        when Prism::ConstantPathTargetNode
          scope, name = constant_path(node)
          ConstWrite.new(scope, name, nil, line)
        when Prism::MultiTargetNode then multi_target(node)
        when Prism::IndexTargetNode
          args = index_args(node, line)
          Send.of(expr(node.receiver), :[]=, args, line, opt: args.none?(Splat))
        when Prism::CallTargetNode
          # `rescue => o&.x` and `for o&.x in list` write only if `o` is
          # not nil, as their safe call does.
          Send.of(expr(node.receiver), node.name, [], line, safe: node.call_operator == "&.")
        else unsupported(node, "#{Refused.form_of(node)} as an assignment target")
        end
      end

      # The indexes of an index target. A splat disables the inline `[]`
      # path, because the count is known only at run time.
      #: (Prism::IndexTargetNode | Prism::IndexOperatorWriteNode | Prism::IndexOrWriteNode | Prism::IndexAndWriteNode node, Integer line) -> Array[node]
      def index_args(node, line)
        (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? splat(a, line) : expr(a) }
      end

      # A hidden local for a parameter that repeats a name (`def m(_, _)`),
      # or nil. The name binds the first; a bare super passes each one,
      # as ruby keeps the others in hidden slots.
      #: (untyped param) -> Symbol?
      def repeat_name(param)
        temp(:arg) if param.respond_to?(:repeated_parameter?) && param.repeated_parameter?
      end

      # An optional parameter's name and default. A repeated name's default
      # goes to the name, which binds the first, and its hidden slot stays
      # nil, as CRuby assigns it (`def m(_, _ = 9) = super; m(1)` passes
      # 9 and nil).
      #: (Prism::OptionalParameterNode param) -> [Symbol, node]
      def optional_param(param)
        hidden = repeat_name(param)
        return [param.name, expr(param.value)] unless hidden

        line = param.location.start_line
        [hidden, Seq.new([set(param.name, expr(param.value), line), Literal.new(nil, line)], line)]
      end

      # A rest parameter's name. `|a, |` has an implicit rest that binds
      # nothing.
      #: (Prism::node node) -> Symbol
      def rest_name(node)
        case node
        when Prism::ImplicitRestNode then :implicit
        when Prism::RestParameterNode then repeat_name(node) || node.name || ANONYMOUS[:rest]
        when Prism::KeywordRestParameterNode then node.name || ANONYMOUS[:kwrest]
        when Prism::ForwardingParameterNode then ANONYMOUS[:kwrest]
        when Prism::NoKeywordsParameterNode then :nokey
        else unsupported(node)
        end
      end

      # A block literal, or the `&value` a call passes on.
      #: (Prism::BlockNode | Prism::BlockArgumentNode node) -> block
      def block(node)
        line = node.location.start_line
        return BlockPass.new(node.expression ? expr(node.expression) : anonymous(:block, line), line) if node.is_a?(Prism::BlockArgumentNode)

        in_block do
          params, extra = block_params(node.parameters)
          body = node.body ? expr(node.body) : Literal.new(nil, line)
          exit_event(node.location.end_line)
          noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                          node.location.end_line, method_cover(node), entry_using, span(node.location)), node)
        end
      end

      # A block's Params and the locals prism leaves implicit: `it`, or
      # the numbered parameters.
      #: (Prism::node? node) -> [Params, Array[Symbol]]
      def block_params(node)
        none = Params.new([], [], nil, [], [], nil, nil)
        case node
        when nil then [none, []]
        when Prism::ItParametersNode then [Params.new([IT], [], nil, [], [], nil, nil), [IT]]
        when Prism::NumberedParametersNode
          names = (1..node.maximum).map { |i| :"_#{i}" }
          [Params.new(names, [], nil, [], [], nil, nil), []]
        when Prism::BlockParametersNode
          # A block-local (`|x; y|`) is already in the block's locals,
          # where prism resolves it at depth 0, new at each call.
          [parameters(node.parameters), []]
        else unsupported(node)
        end
      end

      # Whether the definee of this call defines its own `require` or
      # `load`, which dispatch finds before Kernel's.
      #: (Symbol name) -> bool
      def shadowed?(name) = @shadowed.key?([@path.join("::"), @singleton, name])

      #: (Prism::CallNode node) -> node
      def call(node)
        mark = body_mark(node)
        @body_marks |= [mark] if mark
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil? && node.call_operator != "&."
        return FrozenString.new(unescaped(node.receiver), node.location.start_line) if node.name == :freeze && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil? && node.block.nil?
        # `-"text"`: CRuby's opt_str_uminus, the fstring with no new String.
        return FrozenString.new(unescaped(node.receiver), node.location.start_line, :uminus) if node.name == :-@ && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil? && node.block.nil?
        # The core's `+"text"` under its frozen_string_literal comment: a
        # new String, as its C makes, with no send of +@.
        return Literal.new(unescaped(node.receiver), node.location.start_line, false) if node.name == :+@ && node.receiver.is_a?(Prism::StringNode) && node.block.nil? && Library::Roots.runtime_file?(@file)
        return require_node(node) if REQUIRES.include?(node.name) && node.receiver.nil? && node.block.nil? && !shadowed?(node.name) && !@loader&.eval? && literal_feature(node)
        return autoload_node(node) if AUTOLOADS.include?(node.name) && node.block.nil? && literal_autoload?(node)
        return newarray_send(node) if newarray_send?(node)

        message, encoding = c_message(node)
        @c_messages&.store(message, encoding) if message && encoding
        send = plain_call(node)
        relative_in_file(node, send)
      end

      # The message literal of an error that a file standing in for ruby's
      # C makes, and the encoding of its ASCII text: `raise Klass, "text"`
      # (or `+"text"`), `raise "text"`, or `SomeError.new("text")`. CRuby's
      # C raises with rb_raise, whose format makes the message binary
      # while it is ASCII; a NameError's message is US-ASCII, as
      # rb_name_err_raise makes it.
      #: (Prism::CallNode node) -> [Prism::node, Encoding]?
      def c_message(node)
        return unless @c_messages && node.block.nil?

        args = node.arguments&.arguments || []
        if node.name == :new && error_class?(node.receiver)
          klass = node.receiver
          message = args[0]
        elsif %i[raise fail].include?(node.name) && ((receiver = node.receiver).nil? || (receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :Kernel))
          klass = args[0] if args.size > 1
          message = args.size == 1 ? args[0] : args[1]
        end
        return unless message && (message.is_a?(Prism::StringNode) || message.is_a?(Prism::InterpolatedStringNode) || unary_plus_literal?(message))

        name_error = klass.is_a?(Prism::ConstantReadNode) && %i[NameError NoMethodError].include?(klass.name)
        [message, name_error ? ::Encoding::US_ASCII : ::Encoding::BINARY]
      end

      # Whether `node` names an error class by a constant (`KeyError`,
      # `Encoding::CompatibilityError`).
      #: (Prism::node? node) -> bool
      def error_class?(node)
        (node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)) && node.name.to_s.end_with?("Error")
      end

      #: (Prism::node? node) -> bool
      def unary_plus_literal?(node)
        node.is_a?(Prism::CallNode) && node.name == :+@ && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil?
      end

      # Builds the message literal of an error (`c_message`): its ASCII
      # text has the message's encoding, and the code that it interpolates
      # is built as any other.
      #: (Prism::node node) -> node
      def c_message_expr(node)
        @in_c_message = @c_messages&.fetch(node)
        expr(node)
      ensure
        @in_c_message = nil
      end

      # compile.c's opt_newarray_send and opt_duparray_send: `[a, b].min`,
      # `.max` or `.hash` on a literal that is not static, and
      # `.include?(arg)` on any literal, with no splat. They run without the
      # method's send, so no c_call or c_return fires, and min and max
      # compare in the other order. The core's own files keep the send. A
      # site under `using` takes the literal path too: a refinement of the
      # method turns it off where the program runs
      # (Array.newarray_optimized?), as it clears CRuby's BOP flag.
      #: (Prism::CallNode node) -> bool
      def newarray_send?(node)
        receiver = node.receiver
        return false unless receiver.is_a?(Prism::ArrayNode) && node.block.nil? && node.call_operator != "&." &&
                            receiver.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) } &&
                            !Library::Roots.runtime_file?(@file)

        case node.name
        when :min, :max, :hash then !receiver.static_literal? && node.arguments.nil?
        when :include?
          args = node.arguments&.arguments || []
          args.size == 1 && simple_include_arg?(args.first, receiver.static_literal?)
        else false
        end
      end

      # The argument forms that compile.c's peephole takes for include?: a
      # local, an ivar, self or a literal object (putobject), nil only on a
      # static Array (duparray's list has putnil, newarray's has not), a
      # String only where it is frozen or the Array is not static, then any
      # chain of plain calls with no arguments.
      #: (Prism::node arg, bool static) -> bool
      def simple_include_arg?(arg, static)
        case arg
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::SelfNode, Prism::IntegerNode,
             Prism::FloatNode, Prism::SymbolNode, Prism::TrueNode, Prism::FalseNode, Prism::RationalNode,
             Prism::ImaginaryNode, Prism::RegularExpressionNode
          true
        when Prism::NilNode then static
        when Prism::StringNode then !static || arg.frozen?
        when Prism::RangeNode
          [arg.left, arg.right].all? { |side| side.nil? || side.is_a?(Prism::IntegerNode) } && !(arg.left.nil? && arg.right.nil?)
        when Prism::CallNode
          plain = arg.arguments.nil? && arg.block.nil? && arg.call_operator != "&." && !arg.name.end_with?("=")
          receiver = arg.receiver
          plain && (receiver.nil? || simple_include_arg?(receiver, static))
        else false
        end
      end

      # The program itself sends the method when it is redefined, so the
      # send sees what the program sees.
      #: (Prism::CallNode node) -> Seq
      def newarray_send(node)
        line = node.location.start_line
        items = temp("items")
        steps = [set(items, expr(node.receiver), line)] #: Array[node]
        args = (node.arguments&.arguments || []).map do |arg|
          held = temp("arg")
          steps << set(held, expr(arg), line)
          read(held, line)
        end
        optimized = send_to(core(:Array, line), :newarray_optimized?, [Literal.new(node.name, line)], line)
        fast = send_to(core(:Array, line), :"newarray_#{node.name}", [read(items, line), *args], line)
        Seq.new([*steps, If.new(optimized, fast, send_to(read(items, line), node.name, args, line), line)], line)
      end

      # A file of the program uses rubygems' API. rubygems' own files and
      # the runtime's files do not count.
      #: (Symbol name) -> void
      def gems!(name)
        @loader.gems!(name) if @loader && !@loader.ahead?(@file) && !Library::Roots.runtime_file?(@file)
      end

      # `Primitive.attr! :ruby`, `:hidden`, `:ivars`, `:sends_each`, `:sends_ops` or `:sends_all` in a
      # class body of the core library: every later def in that body gets
      # the attribute, as if each def started with it. `:ruby` marks
      # methods that CRuby writes in Ruby. `:hidden` marks a class of
      # helpers that CRuby writes as a C struct. `:ivars` marks a class
      # whose instance variables CRuby shows. `:sends_each` marks methods
      # that send `each` by name, as CRuby's rb_block_call does. `:sends_ops`
      # marks methods whose operators send by name, as CRuby's f_add does.
      # `:sends_all` marks methods that CRuby writes in Ruby with no C behind
      # them (Pathname's): every send goes by name, as Ruby's do.
      #: (Prism::CallNode node) -> Symbol?
      def body_mark(node)
        mark = node.arguments&.arguments&.first
        return unless !@in_def && node.name == :attr! && (receiver = node.receiver).is_a?(Prism::ConstantReadNode) && receiver.name == :Primitive &&
                      mark.is_a?(Prism::SymbolNode) && %w[ruby hidden ivars sends_each sends_ops sends_all].include?(mark.unescaped)

        mark.unescaped.to_sym
      end

      # A string compiled at run time from a file with a location (loaded
      # by `load`, or given a file by an eval) keeps its literal
      # require_relative as a send. The name that it passes is made from
      # that file's directory, which the runtime's frame cannot know.
      #: (Prism::CallNode node, Send send) -> Send
      def relative_in_file(node, send)
        return send unless @loader&.eval? && node.name == :require_relative && node.receiver.nil? && File.absolute_path?(@file)

        feature = literal_feature(node)
        return send unless feature

        send.args = [Literal.new(File.expand_path(feature, File.dirname(Loader.real_path(@file))), send.line)]
        send
      end

      # A call as a plain Send, with none of the special forms above.
      # `defined?` uses it, because it never runs the call. `compiles` is
      # false for a require of a literal name that no root contains. The
      # call searches at run time, and finds a file that was not compiled
      # in only if the program changed $LOAD_PATH. That change already
      # links in the compiler.
      #: (Prism::CallNode node, ?compiles: bool) -> Send
      def plain_call(node, compiles: true)
        args, kwargs, forwarded = arguments(node.arguments)
        # A receiverless call in a module that defines its own `load` or
        # `require` goes to that method (json's `JSON.load`), not Kernel's.
        receiver = node.receiver
        kernel = compiles && ((receiver.nil? && !shadowed?(node.name)) ||
                              (receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :Kernel))
        @loader.evals!(node.name, args, kernel: kernel) if @elsewhere.zero?
        gems!(:Gem) if node.name == :gem && node.receiver.nil?
        @loader.load_path_changed!(node, @file) if @elsewhere.zero?
        @loader.normalizes!(node.name, args)
        # `&:name` calls that method, as a call with that name does.
        if (given = node.block).is_a?(Prism::BlockArgumentNode) && (symbol = given.expression).is_a?(Prism::SymbolNode)
          @loader.normalizes!(symbol.unescaped.to_sym, [])
        end
        # The inline `[]`, `[]=` and `<<` check visibility as an explicit
        # call does, so a literal `self` dispatches (it can call private
        # methods). A named call with a fast path (OPT_CALLS) needs an
        # explicit receiver, no other options, and the body's argument
        # count.
        opt = ((%i[[] []=].include?(node.name) && node.opening == "[") ||
               (node.name == :<< && node.call_operator.nil? && args.size == 1) ||
               (OPT_CALLS[node.name] == args.size && node.call_operator == "." && kwargs.nil? && node.block.nil? && forwarded.nil? &&
                args.none?(Splat))) &&
              !node.receiver.is_a?(Prism::SelfNode)
        recv = node.receiver && expr(node.receiver)
        # A refinement is active inside its own block, so a sibling
        # refined method can be called there by bare name.
        given = node.block
        blk = given ? in_refine(node) { block(given) } : forwarded
        safe = node.call_operator == "&."
        # Both branches of a safe call have the call's location, as CRuby
        # records. `branch_covers` returns nils if nothing is measured, and
        # then the Send has no covers.
        if safe
          at = safe_call_span(node)
          covers = branch_covers(:"&.", at, [[:then, at], [:else, at]])
        end
        Send.new(recv, node.name, args, message_line(node), node.variable_call?, opt,
                 blk, kwargs, safe, node.attribute_write?, nil, covers&.first && covers)
      end

      # The calls whose block runs with a cref of its own, so a `using` in
      # the block applies to the block alone and not to the rest of the file.
      CREF_BLOCKS = %i[class_eval module_eval class_exec module_exec instance_eval instance_exec].freeze

      #: [T] (Prism::CallNode node) { () -> T } -> T
      def in_refine(node)
        was = @using
        own = node.name == :refine
        return yield unless own || CREF_BLOCKS.include?(node.name) || (node.name == :new && %i[Module Class].include?(constant_name(node.receiver)))

        @using = :owner if own
        begin
          yield
        ensure
          @using = was
        end
      end

      #: (Prism::node? node) -> Symbol?
      def constant_name(node) = node.is_a?(Prism::ConstantReadNode) ? node.name : nil

      # A call's line is its name's line, which can differ from the
      # receiver's if the receiver has several lines.
      #: (Prism::CallNode node) -> Integer
      def message_line(node) = node.message_loc&.start_line || node.location.start_line

      # The globals that ruby always has. Their `defined?` is
      # "global-variable" whether they have a value or not (CRuby's hooked
      # variables).
      SPECIAL_GVARS = %i[$! $@ $~ $_ $; $, $/ $\\ $0 $* $$ $? $: $" $< $> $. $stdin $stdout $stderr
                         $VERBOSE $DEBUG $FILENAME $LOAD_PATH $LOADED_FEATURES $PROGRAM_NAME].freeze

      # `defined?(value)`, as CRuby's defined_expr0: the result of each
      # form. The form decides at compile time. Only an ivar, gvar, cvar,
      # constant, method, yield or super is tested at run time.
      #: (Prism::node node, Integer line) -> Defined
      def defined(node, line)
        case node
        when Prism::LocalVariableReadNode, Prism::ItLocalVariableReadNode then Defined.new(:local, nil, line)
        when Prism::InstanceVariableReadNode then Defined.new(:ivar, node.name, line)
        when Prism::GlobalVariableReadNode
          if SPECIAL_GVARS.include?(gvar_name(node.name)) || @loader&.back_ref(node.name)
            Defined.new(:global, nil, line)
          else
            Defined.new(:gvar, node.name, line)
          end
        # `$1` and `$&` refer to a part of the last match: defined if the
        # part exists.
        when Prism::NumberedReferenceReadNode, Prism::BackReferenceReadNode then Defined.new(:backref, expr(node), line)
        when Prism::ClassVariableReadNode then Defined.new(:cvar, node.name, line)
        when Prism::ConstantReadNode, Prism::ConstantPathNode then Defined.new(:const, naming { expr(node) }, line)
        when Prism::CallNode
          # `o.x = v` and `o[k] = v` are assignments if `o` has the writer.
          if node.attribute_write? then Defined.new(:attrasgn, plain_call(node), line)
          # A call with a block literal is an expression, whatever it calls.
          elsif node.block.is_a?(Prism::BlockNode) then Defined.new(:expression, nil, line)
          else Defined.new(:method, plain_call(node), line)
          end
        when Prism::YieldNode then Defined.new(:yield, nil, line)
        when Prism::SuperNode, Prism::ForwardingSuperNode then Defined.new(:super, nil, line)
        # An Array or Hash literal is defined if every part is defined. A
        # splat's part is its value.
        when Prism::ArrayNode
          Defined.new(:list, node.elements.map { |e| array_element(e, line) }, line)
        when Prism::HashNode then Defined.new(:list, [HashLit.new(hash_pairs(node.elements), line)], line)
        # `(x)` tests `x`, and `()` or an empty `begin` is nil. A `;` makes
        # more than one statement, even an empty one: `(;x)` is an
        # expression.
        when Prism::ParenthesesNode
          return Defined.new(:nil, nil, line) if node.body.nil?
          return Defined.new(:expression, nil, line) if node.multiple_statements?

          body = node.body
          inner = body.is_a?(Prism::StatementsNode) && body.body.size == 1 ? body.body.first : nil
          inner ? defined(inner, line) : Defined.new(:expression, nil, line)
        when Prism::BeginNode
          empty = node.statements.nil? && node.rescue_clause.nil? && node.else_clause.nil? && node.ensure_clause.nil?
          Defined.new(empty ? :nil : :expression, nil, line)
        when Prism::SelfNode then Defined.new(:self, nil, line)
        when Prism::NilNode then Defined.new(:nil, nil, line)
        when Prism::TrueNode then Defined.new(:true, nil, line)
        when Prism::FalseNode then Defined.new(:false, nil, line)
        else Defined.new(assignment?(node) ? :assignment : :expression, nil, line)
        end
      end

      # Every form that writes a variable, a constant, an attribute or an
      # index, including operator assignments. A named-capture match is a
      # call.
      #: (untyped node) -> bool
      def assignment?(node) = node.class.name.end_with?("WriteNode") && !node.is_a?(Prism::MatchWriteNode)

      # `for x in list; body; end` is `list.each { |x| body }` with the
      # body in the enclosing scope: its locals move one scope out.
      #: (Prism::ForNode node) -> Send
      def for_loop(node)
        line = node.location.start_line
        index = node.index
        # `for *x in o` assigns as `*x = value` does.
        target = if index.is_a?(Prism::SplatNode)
                   MultiTarget.new([], (expression = index.expression) ? target(expression) : :implicit, [], line)
                 else
                   target(index)
                 end
        target = deepen(target, 0)
        body = node.statements ? deepen(retry_in(:block) { seq(node.statements) }, 0) : Literal.new(nil, line)
        value = Local.new(:"*for", 0, line)
        if target.is_a?(MultiTarget)
          # `for a, b in o` takes all yielded values, as `|a, b|` does. The
          # block collects them, and a single value is used as is.
          got = Local.new(:"*for", 0, line)
          one = Send.of(Send.of(got, :size, [], line), :==, [Literal.new(1, line)], line)
          first = Send.of(got, :[], [Literal.new(0, line)], line)
          bind = MultiAssign.new(target, If.new(one, first, got, line), line)
          params = Params.new([], [], :"*for", [], [], nil, nil)
        else
          bind = target.is_a?(Send) ? target.tap { |t| t.args << value } : target.tap { |t| t.value = value }
          params = Params.new([:"*for"], [], nil, [], [], nil, nil)
        end
        # The body is a Proc whose source is the whole `for` (Proc#source_range).
        block = noted(Block.new(params, [:"*for"], Seq.new([bind, RedoPoint.new(line), body], line), line, node.location.end_line, nil, nil, span(node.location)), node)
        Send.of(expr(node.collection), :each, [], line, block: block)
      end

      # `node` as read from one block scope deeper: every local at
      # `level` or more is one scope further out. A node that the tree
      # holds in two places (a pattern's subject) moves once (`seen`).
      #: (untyped node, Integer level, ?Hash[untyped, bool]? seen) -> untyped
      def deepen(node, level, seen = nil)
        if seen.nil?
          seen = {} #: Hash[untyped, bool]
          seen.compare_by_identity
        end
        return node if Hir.node?(node) && seen.key?(node)

        seen[node] = true if Hir.node?(node)
        case node
        when Local, Assign
          node.depth += 1 if node.depth >= level
          node.value = deepen(node.value, level, seen) if node.is_a?(Assign) && node.value
          node
        when Block
          node.body = deepen(node.body, level + 1, seen)
          node.params.optional.each { |pair| pair[1] = deepen(pair[1], level + 1, seen) }
          node.params.keywords.each { |pair| pair[1] = deepen(pair[1], level + 1, seen) if pair[1] }
          node
        when Def
          node.receiver = deepen(node.receiver, level, seen) if node.receiver
          node
        when ClassDef
          node.scope = deepen(node.scope, level, seen) if Hir.node?(node.scope)
          node.superclass = deepen(node.superclass, level, seen) if node.superclass
          node
        when ModuleDef
          node.scope = deepen(node.scope, level, seen) if Hir.node?(node.scope)
          node
        when SingletonClassDef
          node.target = deepen(node.target, level, seen)
          node
        when Node
          node.each_pair { |k, v| node[k] = deepen(v, level, seen) if Hir.node?(v) || v.is_a?(Array) }
          node
        when Array then node.map! { |v| Hir.node?(v) || v.is_a?(Array) ? deepen(v, level, seen) : v }
        else node
        end
      end

      # `[args, kwargs, block]` of an argument list: the args (with any
      # Splats), the keywords as one HashLit or nil, and the block that
      # `...` forwards, or nil.
      #: (Prism::ArgumentsNode? node) -> [Array[node], HashLit?, BlockPass?]
      def arguments(node)
        kwargs = nil #: HashLit?
        block = nil #: BlockPass?
        args = (node&.arguments || []).filter_map do |a|
          line = a.location.start_line
          case a
          when Prism::SplatNode then splat(a, line)
          when Prism::KeywordHashNode
            kwargs = HashLit.new(call_keyword_pairs(hash_pairs(a.elements), line), line)
            nil
          when Prism::ForwardingArgumentsNode
            kwargs = HashLit.new([HashSplat.new(anonymous(:kwrest, line), line), nil], line)
            block = BlockPass.new(anonymous(:block, line), line)
            Splat.new(anonymous(:rest, line), line)
          else @c_messages&.key?(a) ? c_message_expr(a) : expr(a)
          end
        end
        [args, kwargs, block]
      end

      # The pairs of a call's keywords. A literal key given twice keeps its
      # last place, as ruby's keyword arguments do (`r(b: 1, a: 2, b: 3)`
      # is `{a: 2, b: 3}`), where a Hash literal keeps the first. Each
      # earlier value still runs in its place, as `**(value; {})`. Only
      # keywords that are all Symbol literals compile so; with a `**` or
      # any other key among them, ruby builds a Hash, which keeps the
      # first place.
      #: (Array[untyped] pairs, Integer line) -> Array[node?]
      def call_keyword_pairs(pairs, line)
        return pairs unless pairs.each_slice(2).all? { |k, _| k.is_a?(Literal) && k.value.is_a?(Symbol) }

        keys = pairs.each_slice(2).map { |k, _| k.value }
        out = [] #: Array[node?]
        pairs.each_slice(2).with_index do |(k, v), i|
          if keys[i] && keys.drop(i + 1).include?(keys[i])
            out.push(HashSplat.new(Seq.new([v, HashLit.new([], line)], line), line), nil)
          else
            out.push(k, v)
          end
        end
        out
      end

      # `*value`, or a bare `*`: the anonymous rest parameter that the
      # method forwards, anywhere a splat can be.
      #: (Prism::SplatNode node, Integer line) -> Splat
      def splat(node, _line)
        # The splat's own line: its conversion reports it (splatarray).
        line = node.location.start_line
        noted(Splat.new(node.expression ? expr(node.expression) : anonymous(:rest, line), line), node)
      end

      # The bodies that a file always runs when it loads: its own
      # statements, a class or a module body, and a `begin` for grouping.
      # A branch, a loop, a block and a method body are not included.
      #: (Prism::node? node) -> Array[Prism::node?]?
      def self.always_run(node)
        case node
        when Prism::ProgramNode, Prism::BeginNode then [node.statements]
        when Prism::StatementsNode then node.body
        when Prism::ModuleNode, Prism::ClassNode, Prism::SingletonClassNode then [node.body]
        end
      end

      # Every `alias $x $&` the file always runs, by identity.
      #: (Prism::node? node, ?Hash[Prism::node, bool]? out) -> Hash[Prism::node, bool]
      def self.certain_aliases(node, out = nil)
        unless out
          out = {} #: Hash[Prism::node, bool]
          out.compare_by_identity
        end
        (always_run(node) || []).compact.each do |child|
          out[child] = true if child.is_a?(Prism::AliasGlobalVariableNode)
          certain_aliases(child, out)
        end
        out
      end

      # Whether this file always runs `node`. The walk occurs at the first
      # call, which for almost every file never occurs.
      #: (Prism::node node) -> bool
      def certain_alias?(node)
        return true unless @root

        (@certain ||= Build.certain_aliases(@root)).key?(node)
      end

      #: (Prism::node node, String message) -> bot
      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end

      # A form of Ruby that zr does not support yet, at the node's line and
      # column. `form` is in user words (Refused.form_of).
      #: (Prism::node node, ?String form) -> bot
      def unsupported(node, form = Refused.form_of(node))
        raise Refused.unsupported(form, file: @file, line: node.location.start_line, column: node.location.start_column + 1)
      end

      # A refusal of a form that ruby also refuses. A program that compiles
      # it at run time gets the SyntaxError that ruby raises.
      #: (Prism::node node, String message) -> bot
      def invalid(node, message)
        raise Invalid, "#{@file}:#{node.location.start_line}: #{message}"
      end

      # The arms of `built` that need more than one line. `line` is the
      # node's first line, and `taken` is the flag of `built`.
      private

      # The block starts at its `{` or `do`, the line that ruby gives as
      # the lambda's source_location.
      #: (Prism::LambdaNode node, Integer line) -> Lambda
      def lambda_literal(node, line)
        in_block do
          params, extra = block_params(node.parameters)
          body = node.body ? expr(node.body) : Literal.new(nil, line)
          exit_event(node.location.end_line)
          Lambda.new(noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, node.opening_loc.start_line,
                                     node.location.end_line, method_cover(node), entry_using, span(node.location)), node), line)
        end
      end

      #: (untyped node, Integer line) -> (Undef | UndefValue)
      def undef_names(node, line)
        return UndefValue.new(node.names.map { |n| expr(n) }, line) unless node.names.all?(Prism::SymbolNode)

        names = node.names.map { |n| n.unescaped.to_sym }
        Undef.new(names, line)
      end

      #: (Prism::SuperNode node, Integer line) -> Super
      def super_call(node, line)
        args, kwargs, forwarded = arguments(node.arguments)
        given = node.block
        Super.new(args, kwargs, given ? block(given) : forwarded, line)
      end

      #: (Prism::IfNode node, Integer line, taken: bool) -> (If | Seq)
      def if_branch(node, line, taken:)
        chosen = chooses?(node.predicate)
        traced = line_event(node, taken: taken)
        # The predicate gets its number first, because ruby's compiler
        # writes it first. If ruby decides the predicate at compile time,
        # it drops the whole branch, and Coverage records nothing.
        predicate = expr(node.predicate)
        then_cover, else_cover = chosen.nil? ? branch_covers(:if, span(node.location), if_sides(node)) : [nil, nil]
        then_live, else_live = reaches(node.predicate)
        # CRuby's jump over an `elsif` carries the event of a silent end of
        # the branch (`jump_event`); an `else` it folds away, except under
        # branch coverage, where a counter starts the else, given or not.
        then_body = node.statements && elsewhere(other_engine_test?(node.predicate)) do
          dead(!then_live) do
            body = seq(node.statements, taken: taken && chosen != false)
            if node.subsequent.is_a?(Prism::IfNode) then jumping(body, node.statements, line, taken: taken)
            elsif else_cover then jumping(body, node.statements, line, taken: taken, coverage: true)
            else body
            end
          end
        end
        built = If.new(predicate,
                       covered(then_cover, then_body, line),
                       covered(else_cover, (following = node.subsequent) && dead(!else_live) { subsequent(following, taken: taken && chosen != true) }, line), line)
        traced ? Seq.new([traced, built], line) : built
      end

      # The `else` or `elsif` of an `if`. An `elsif` that starts a line
      # fires its :line event before its predicate, as a statement does.
      #: (Prism::ElseNode | Prism::IfNode node, taken: bool) -> node
      def subsequent(node, taken:)
        traced = line_event(node, taken: taken) if node.is_a?(Prism::IfNode)
        built = expr(node, taken: taken)
        traced ? Seq.new([traced, built], traced.line) : built
      end

      #: (Prism::UnlessNode node, Integer line, taken: bool) -> (If | Seq)
      def unless_branch(node, line, taken:)
        chosen = chooses?(node.predicate)
        traced = line_event(node, taken: taken)
        # Ruby lists an `unless`'s else before its then, and numbers them
        # in that order. The branch test is the same.
        predicate = expr(node.predicate)
        else_cover, then_cover = chosen.nil? ? branch_covers(:unless, span(node.location), unless_sides(node)) : [nil, nil]
        true_live, false_live = reaches(node.predicate)
        built = If.new(predicate,
                       covered(else_cover, (else_clause = node.else_clause) && dead(!true_live) { seq(else_clause.statements, taken: taken && chosen != false) }, line),
                       covered(then_cover, node.statements && dead(!false_live) { seq(node.statements, taken: taken && chosen != true) }, line), line)
        traced ? Seq.new([traced, built], line) : built
      end

      # A loop returns nil, so its body's value is not used.
      #: (Prism::WhileNode node, Integer line) -> While
      def while_loop(node, line)
        body, = branch_covers(:while, span(node.location), loop_sides(node))
        While.new(expr(node.predicate), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                  node.begin_modifier?)
      end

      #: (Prism::UntilNode node, Integer line) -> While
      def until_loop(node, line)
        body, = branch_covers(:until, span(node.location), loop_sides(node))
        While.new(falsy(expr(node.predicate), line), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                  node.begin_modifier?)
      end

      #: (Prism::ClassNode node, Integer line) -> ClassDef
      def class_body(node, line)
        scope, name = naming { constant_path(node.constant_path) }
        @loader&.module_defined!(@path, node.constant_path.slice)
        superclass = node.superclass && expr(node.superclass)
        in_definee(node.constant_path.slice, false) do
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            exit_event(node.location.end_line)
            ClassDef.new(scope, name, superclass, with_temps(node.locals), body, line, node.location.end_line)
          end
        end
      end

      #: (Prism::ModuleNode node, Integer line) -> ModuleDef
      def module_body(node, line)
        scope, name = naming { constant_path(node.constant_path) }
        @loader&.module_defined!(@path, node.constant_path.slice)
        in_definee(node.constant_path.slice, false) do
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            exit_event(node.location.end_line)
            ModuleDef.new(scope, name, with_temps(node.locals), body, line, node.location.end_line)
          end
        end
      end

      #: (Prism::SingletonClassNode node, Integer line) -> SingletonClassDef
      def singleton_class_body(node, line)
        target = expr(node.expression)
        in_definee(nil, true) do
          in_scope do
            was, @in_sclass = @in_sclass, true
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            @in_sclass = was
            SingletonClassDef.new(target, with_temps(node.locals), body, line, node.location.end_line)
          end
        end
      end

      # Builds the block's nodes as names only: a constant that `defined?`
      # tests, or that a class path opens, is not a use of the library
      # that it names. pp tests RubyVM::AbstractSyntaxTree and opens its
      # Node class, and links neither the compiler nor the translator.
      #: [T] () { () -> T } -> T
      def naming
        was = @naming
        @naming = true
        begin
          yield
        ensure
          @naming = was
        end
      end

      #: (Prism::ConstantReadNode node, Integer line) -> ConstRead
      def const_read(node, line)
        @loader&.compiles!(node.name) unless @naming || @loader&.module_defined?(@path, node.name)
        gems!(node.name)
        ConstRead.new(nil, node.name, line)
      end

      #: (untyped node, Integer line) -> ConstRead
      def const_path_read(node, line)
        # `Prism::Ruby` is not Ruby::Box: only a top-level `Ruby` compiles.
        @loader&.compiles!(node.name) unless @naming || (node.name == :Ruby && node.parent)
        @loader&.ruby_prisms! if node.name == :Prism && ruby_namespace?(node.parent)
        gems!(node.name) if node.parent.nil?
        scope, name = constant_path(node)
        ConstRead.new(scope, name, line)
      end

      # Whether `node` is the top-level `Ruby` (`Ruby` or `::Ruby`).
      #: (Prism::node? node) -> bool
      def ruby_namespace?(node)
        case node
        when Prism::ConstantReadNode then node.name == :Ruby && !@loader&.module_defined?(@path, :Ruby)
        when Prism::ConstantPathNode then node.parent.nil? && node.name == :Ruby
        else false
        end
      end

      #: (Prism::InterpolatedStringNode node, Integer line) -> node
      def interpolated_string(node, line)
        if node.frozen? then frozen_literal_string(static_text(node), line)
        # Adjacent literals with nothing interpolated are one literal.
        elsif static_string?(node) then Literal.new(static_text(node), line, !node.mutable?)
        else interpolation(node, line)
        end
      end

      #: (Prism::RangeNode node, Integer line) -> RangeLit
      def range_literal(node, line)
        # Fixnum and nil ends make one frozen Range for the site, as
        # CRuby's optimizable_range_item_p decides.
        static = [node.left, node.right].all? do |e|
          e.nil? || e.is_a?(Prism::NilNode) || (e.is_a?(Prism::IntegerNode) && e.value.bit_length <= 62)
        end
        low = node.left ? expr(node.left) : Literal.new(nil, line)
        high = node.right ? expr(node.right) : Literal.new(nil, line)
        # Two String literals make one frozen Range with frozen ends for
        # the site, where CRuby's peephole optimizer folds them.
        if node.left.is_a?(Prism::StringNode) && node.right.is_a?(Prism::StringNode) && !after_label?(node)
          static = true
          low = frozen_literal(node.left, low, line)
          high = frozen_literal(node.right, high, line)
        end
        RangeLit.new(low, high, node.exclude_end?, line, static)
      end

      #: (Prism::AliasMethodNode node, Integer line) -> (Alias | AliasValue)
      def alias_method_names(node, line)
        if (new_name = node.new_name).is_a?(Prism::SymbolNode) && (old_name = node.old_name).is_a?(Prism::SymbolNode)
          Alias.new(new_name.unescaped.to_sym, old_name.unescaped.to_sym, line)
        else
          AliasValue.new(expr(node.new_name), expr(node.old_name), line)
        end
      end

      #: (untyped node, Integer line) -> node
      def alias_global(node, line)
        if node.old_name.is_a?(Prism::GlobalVariableReadNode) && !FRAME_GVARS.include?(node.old_name.name)
          GvarAlias.new(node.new_name.name, node.old_name.name, line)
        else
          # `$&` is a register of the frame that last matched, not a
          # global, so the runtime cannot keep an alias entry for it. The
          # lowering resolves the new name. Ruby does not make an alias
          # that does not run (`if false; alias $x $&; end` leaves `$x`
          # nil). So a conditional alias sets its own flag when it runs,
          # and each use of the name reads the flag.
          flag = certain_alias?(node) ? nil : :"$%alias#{node.new_name.name}"
          @loader&.back_ref!(node.new_name.name, node.old_name, flag)
          flag ? Seq.new([GvarWrite.new(flag, Literal.new(true, line), line, nil), Literal.new(nil, line)], line) : Literal.new(nil, line)
        end
      end

      #: (Prism::CaseNode node, Integer line, taken: bool) -> Case
      def case_when(node, line, taken:)
        covers = branch_covers(:case, span(node.location), case_sides(node, :when))
        # CRuby puts the `else` first and the `when` bodies after it, so a
        # jump to the end follows each body but the last (`jump_event`).
        # The jumps are on the `when` lines, and the `else`'s on its first
        # statement's; a `case` with no subject puts each on its own line.
        last = node.conditions.size - 1
        clauses = node.conditions.map.with_index do |w, i|
          values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? splat(c, line) : expr(c) }
          # With no subject, a `when` of literal tests that never pass is
          # code that CRuby does not compile.
          never = node.predicate.nil? && w.conditions.all? { |c| chooses?(c) == false }
          other = ruby_engine?(node.predicate) && other_engines?(w.conditions)
          body = w.statements ? elsewhere(other) { dead(never) { seq(w.statements, taken: taken) } } : Literal.new(nil, line)
          body = jumping(body, w.statements, node.predicate ? w.location.start_line : line, taken: taken) if i < last
          [values, covered(covers[i], body, line)]
        end
        else_clause = node.else_clause
        other = else_clause && expr(else_clause, taken: taken)
        if other && else_clause && (statements = else_clause.statements)
          other = jumping(other, statements, node.predicate ? statements.location.start_line : line, taken: taken)
        end
        Case.new(node.predicate && expr(node.predicate), clauses, covered(covers.last, other, line), line)
      end

      #: (Prism::IndexOperatorWriteNode | Prism::IndexOrWriteNode | Prism::IndexAndWriteNode node, Integer line) -> IndexOpAssign
      def index_op_assign(node, line)
        unsupported(node, "a block in an index target") if node.block
        args = index_args(node, line)
        op = case node
             when Prism::IndexOperatorWriteNode then node.binary_operator
             when Prism::IndexOrWriteNode then :or
             else :and
             end
        IndexOpAssign.new(expr(node.receiver), args, op, expr(node.value), line)
      end

      #: (Prism::CallOperatorWriteNode | Prism::CallOrWriteNode | Prism::CallAndWriteNode node, Integer line) -> AttrOpAssign
      def attr_op_assign(node, line)
        op = case node
             when Prism::CallOperatorWriteNode then node.binary_operator
             when Prism::CallOrWriteNode then :or
             else :and
             end
        AttrOpAssign.new(expr(node.receiver), node.read_name, op, expr(node.value), line, node.call_operator == "&.")
      end

      #: (Prism::PostExecutionNode node, Integer line) -> Once
      def post_execution(node, line)
        # `END { }` shares the enclosing scope. As in CRuby, a block runs
        # once and registers the body as a block of its own, so the body
        # is two blocks deeper (`block (2 levels) in <main>`).
        body = deepen(deepen(node.statements ? retry_in(:block) { seq(node.statements) } : Literal.new(nil, line), 0), 0)
        none = Params.new([], [], nil, [], [], nil, nil)
        register = Send.of(Core.new(:Kernel, line), :end_proc, [], line, block: Block.new(none, [], body, line))
        # It registers once for its site, however many times the site runs.
        Once.new(Send.of(Core.new(:Kernel, line), :post_exe, [], line, block: Block.new(none, [], register, line)), line)
      end
    end

    # The runtime files whose instance variables a program sees as in
    # ruby: prism's port, which changes the prism gem's nodes after they
    # are built, and openssl's port (its C creates each visible instance
    # variable by name and keeps the rest in hidden slots).
    VISIBLE_IVARS = [
      *%w[mutation ast].map { |name| File.join(Library::Layout::EXT, "prism/ruby/#{name}.rb") },
      File.join(Library::Layout::EXT, "openssl.so.rb"), *Dir[File.join(Library::Layout::EXT, "openssl/ossl/*.rb")].sort
    ].freeze
  end
end

# The rest of `Build`, by topic. They load after the class body, because
# they read `Library::Roots.pure` when they load.
require_relative "preludes"
require_relative "build/loader"
require_relative "build/literals"
require_relative "build/coverage"
require_relative "build/usings"
require_relative "build/requires"
