# frozen_string_literal: true

require_relative "../parse"
require_relative "../paths"
require_relative "../refused"
require_relative "../library/layout"
require_relative "../library/roots"
require_relative "../target"
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
      # @rbs @using: using
      # @rbs @usings: Integer
      # @rbs @in_def: bool
      # @rbs @in_sclass: bool
      # @rbs @dead: Integer
      # @rbs @activations: Integer
      # @rbs @temps: Array[Array[Symbol]]
      # @rbs @scopes: Array[Array[Symbol]]
      # @rbs @last_lines: Array[Integer]
      # @rbs @warnings: Array[String]
      # @rbs @def_depths: Hash[Symbol, Integer]?
      # @rbs @def_params: Params?
      # @rbs @flip_flops: Integer?
      # @rbs @guarded: Integer
      # @rbs @certain: Hash[Prism::node, bool]?
      # @rbs @after_label: Hash[Prism::node, bool]?
      # @rbs @temp_serial: Integer?

      # The named calls that a site lowers to a kernel entry with a core
      # fast path (Zr::Lower::Function::Sends::OPT_ENTRIES), with each
      # one's argument count. A call with a different count, or with a
      # block, keywords or a splat, raises or does something different,
      # and only the real call can tell.
      OPT_CALLS = { getbyte: 1, setbyte: 2, push: 1, pop: 0, shift: 0, empty?: 0 }.freeze

      # `eval_support` is false for an eval: the program already contains
      # the compiler, so the eval must not compile it again. It is true to
      # build the compiler into a program with eval. `prebuilt` is an
      # EvalSupport that is already built (`Zr::EvalSupport`), or nil. With
      # it, a program with eval refers to eval support's units and does not
      # build them, also for every file that it shares with eval support.
      # Only the end of a build knows if the program evals, so such a
      # program is built again with eval support.
      # `method` is the parameters of the method that an eval's string
      # runs inside, as from Method#parameters, or nil outside a method:
      # a `yield` has a block only inside a method, and a bare `super`
      # passes those parameters.
      # `trace` arms the events from the start, for an eval under an
      # enabled TracePoint.
      # `gem_set` is a GemSet (lib/zr/gem_set.rb): the gems that come
      # before zr's standard library, or nil. `gate` stops the build at a
      # require in the program's own files that no root has (Loader).
      # `switches` are the ruby switches of the build (`Hir::Switches`):
      # their prelude runs after the other preludes, before the main file.
      # @rbs source: String
      # @rbs file: String
      # @rbs roots: Array[String]
      # @rbs eval_support: bool
      # @rbs prebuilt: untyped
      # @rbs line: Integer
      # @rbs scopes: Array[Array[Symbol]]?
      # @rbs method: Array[[Symbol, Symbol?]]?
      # @rbs activations: Integer?
      # @rbs target: Target
      # @rbs trace: bool
      # @rbs gem_set: GemSet?
      # @rbs gate: bool | Symbol
      # @rbs switches: Switches
      # @rbs using: Integer?
      # @rbs def_base: Integer?
      # @rbs return: Program
      def self.program(source, file, roots: [], eval_support: true, prebuilt: nil, line: 1, scopes: nil, method: nil, activations: nil, target: Target.default,
                       trace: false, gem_set: nil, gate: false, switches: Switches::NONE, using: nil, def_base: nil)
        # The main file's name came from the build's command line, in the
        # build's locale. A program's locale is UTF-8
        # (Encoding.locale_charmap), and the name must not depend on the
        # build machine.
        file = file.dup.force_encoding(::Encoding::UTF_8) if eval_support && file.encoding != ::Encoding::UTF_8
        # @type var built: ^(untyped, bool, bool, bool) -> [Loader, Unit, Require?]
        built = lambda do |external, trace, evals, covers|
          loader = Loader.new(roots + (gem_set&.roots || []) + Library::Roots.stdlib(target), eval: !eval_support, external: external, trace: trace,
                              evals: evals, covers: covers, activations: activations, prebuilt_eval: prebuilt, gem_set: gem_set,
                              gate: gate, description: Library::Roots.description(target), switches: switches, def_base: def_base || 0)
          loader.main!(file)
          loader.eval_using = using
          # Built before the main file, so that the main file's requires
          # search the -I roots that the prelude adds. It runs as a load: it
          # is not in $LOADED_FEATURES, and what its -r requires is the
          # program's, not hidden as a runtime file's requires are.
          switched = (Require.new(:load, "zr/ruby_switches", Library::Roots::SWITCHES, loader.add(Library::Roots::SWITCHES), 0) if switches.prelude)
          [loader, loader.unit(file, source, line, scopes, method: method), switched]
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
        loader, main, switched = built.call(external, trace, evals, covers)
        preludes = eval_support ? Build.preludes(loader, target) : [] #: Array[node]
        loop do
          over = loader.evals? ? prebuilt : nil
          break if over.equal?(external) && (loader.traces? || trace) == trace && (loader.covers? || !def_base.nil?) == covers

          evals = loader.evals?
          external = over
          trace ||= loader.traces?
          covers = loader.covers? || !def_base.nil?
          loader, main, switched = built.call(external, trace, evals, covers)
          preludes = eval_support ? Build.preludes(loader, target) : []
        end
        # A program with eval numbers its `using` entries here. A compile
        # at run time cannot see how many there are, because an entry
        # under a condition is made only if the condition is true. So all
        # entries are taken before the first line, and a compile at run
        # time starts after the last of them.
        preludes += [Activations.new(loader.activations, 0)] if eval_support && loader.evals? && loader.activations.positive?
        preludes << switched if switched
        body = preludes.empty? ? main.body : Seq.new([*preludes, main.body], 0)
        body = Seq.new([data(main, loader.data_at(main.file)), body], 0) if loader.data_at(main.file)
        spots = [main, *loader.units].filter_map { |unit| [unit.file, unit.spots] if unit.spots && !unit.spots.empty? }.to_h
        # A compile at run time gives its lines to a Coverage that runs
        # already, whether or not the file names Coverage.
        coverable = loader.covers? || !eval_support ? loader.coverable : {} #: Hash[String, [Integer, Array[Integer]]]
        Program.new(main.file, main.locals, body, loader.units, main_warnings(main.warnings, switches.verbose), eval_support && loader.evals?, loader.entries, loader.tracing?,
                    main.node_ids, spots, coverable, loader.activations, loader.covers? ? loader.branches : {},
                    loader.covers? ? loader.defs : {})
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
        @shadowed = shadowed
        @path = [Object.name]
        @singleton = false
        @body_marks = []
        @block_depth = 0
        # An eval starts under the refinements of its call site.
        @using = eval ? loader&.eval_using : nil
        # The number of `using` entries that this build made. `statement`
        # reads it to know if a search of its new statement can find one.
        @usings = 0
        @in_def = false
        @in_sclass = false
        @dead = 0
        @activations = -1
        @temps = [[]]
        @scopes = [@temps.first]
        # The line of each scope's last `:line` event, in the compiler's
        # statement order (ruby's last_line).
        @last_lines = [-1]
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

      # Builds `body` one block scope deeper. A `using` in a block at the
      # top level of a file refines the file's own scope, so it applies to
      # the rest of the file after the block, as in ruby.
      #: [T] () { () -> T } -> T
      def in_block
        @block_depth += 1
        using = @using
        @temps.push([])
        @last_lines.push(-1)
        begin
          yield
        ensure
          @block_depth -= 1
          @using = using unless @path == [Object.name] && !@in_def
          @temps.pop
          @last_lines.pop
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
        begin
          yield
        ensure
          @block_depth = was_depth
          @def_params = was_params
          @def_depths = was_depths
          @temps.pop
          @scopes.pop
          @last_lines.pop
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
      # checked backtrace of `$!` (Exception.errat), or the global itself.
      #: (Symbol name, Integer line) -> node
      def gvar_read(name, line)
        aliased = @loader&.back_ref(name)
        if aliased && (flag = @loader.alias_flag(name))
          return If.new(GvarRead.new(flag, line), expr(aliased), GvarRead.new(gvar_name(name), line), line)
        end
        return expr(aliased) if aliased
        return Send.of(Core.new(:Exception, line), :errat, [GvarRead.new(:$!, line)], line) if name == :$@

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
      # method's state, as in ruby.
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
        name = :"%flip_flop#{@flip_flops}"
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
        body = node.is_a?(Prism::PreExecutionNode) && node.statements&.body
        return [node] unless body

        nested, rest = body.partition { |s| s.is_a?(Prism::PreExecutionNode) }
        return [node] if nested.empty?

        [*nested.flat_map { |s| pre_executions(s) }, node.copy(statements: node.statements&.copy(body: rest))]
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
        traced = line_event(node)
        out = using_activation(node) || assigned_using(node) || expr(node, taken: taken)
        out = Seq.new([traced, out], traced.line) if traced
        mark_using(out, {}) if @using
        return out if out.is_a?(Using)
        return out if @usings == made

        nested = usings_in(out, {}).sort_by(&:id)
        return out if nested.empty?

        line = node.location.start_line
        Seq.new([UsingDefaults.new(nested.map { |u| [u.id, u.from] }, line), out], line)
      end

      # The `using` entries in a statement, below its top level, which a
      # condition can skip.
      #: (untyped node, Hash[Integer, bool] seen, ?Array[Using] out) -> Array[Using]
      def usings_in(node, seen, out = [])
        return out if node.nil? || seen.key?(node.object_id)

        if node.is_a?(Array)
          node.each { |child| usings_in(child, seen, out) }
          return out
        end
        return out unless node.is_a?(Node)

        seen[node.object_id] = true
        out << node if node.is_a?(Using)
        node.each_pair { |_, child| usings_in(child, seen, out) }
        out
      end

      # `using mod` where ruby permits it: at toplevel or in a class or
      # module body, never in a method, and never as a send whose value
      # is used.
      #: (Prism::node node) -> Using?
      def using_activation(node)
        return nil if @in_def
        return nil unless node.is_a?(Prism::CallNode) && node.name == :using && node.block.nil?
        return nil unless node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

        args = node.arguments&.arguments
        return nil unless args && args.size == 1 && !args[0].is_a?(Prism::SplatNode)

        value = expr(args[0])
        from = @using.is_a?(Integer) ? @using : -1
        @using = @loader ? @loader.next_activation : (@activations += 1)
        @usings += 1
        Using.new(@using, from, value, node.location.start_line)
      end

      # `x = using mod`: the activation, whose value (self) the local gets.
      #: (Prism::node node) -> Assign?
      def assigned_using(node)
        return nil unless node.is_a?(Prism::LocalVariableWriteNode)

        activation = using_activation(node.value) or return nil
        Assign.new(node.name, node.depth, activation, node.location.start_line)
      end

      #: (untyped node, Hash[Integer, bool] seen) -> void
      def mark_using(node, seen)
        return if node.nil? || seen.key?(node.object_id)

        if node.is_a?(Array)
          node.each { |child| mark_using(child, seen) }
          return
        end
        return unless node.is_a?(Node)

        seen[node.object_id] = true
        case node
        when Send, Super, AttrOpAssign, IndexOpAssign, Case then node.using ||= @using
        end
        node.each_pair { |_, child| mark_using(child, seen) }
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

      #: (Prism::node node, ?taken: bool) -> node
      def built(node, taken: true)
        line = node.location.start_line
        case node
        when Prism::StatementsNode then seq(node, taken: taken)
        when Prism::ParenthesesNode then node.body ? expr(node.body, taken: taken) : Literal.new(nil, line)
        when Prism::IntegerNode, Prism::FloatNode then Literal.new(node.value, line)
        # `3r` and `2i` use the core's Kernel, even if self has no Kernel.
        when Prism::RationalNode then Send.of(Core.new(:Kernel, line), :Rational, [Literal.new(node.numerator, line), Literal.new(node.denominator, line)], line)
        when Prism::ImaginaryNode then Send.of(Core.new(:Kernel, line), :Complex, [Literal.new(0, line), expr(node.numeric)], line)
        when Prism::StringNode then literal_string(node, unescaped(node), line)
        when Prism::SymbolNode then literal_symbol(node, line)
        when Prism::NilNode then Literal.new(nil, line)
        when Prism::TrueNode then Literal.new(true, line)
        when Prism::FalseNode then Literal.new(false, line)
        when Prism::SelfNode then SelfRef.new(line)
        when Prism::CallNode then call(node)
        when Prism::DefNode then define(node)
        when Prism::LocalVariableReadNode then Local.new(node.name, node.depth, line)
        when Prism::LocalVariableWriteNode then Assign.new(node.name, node.depth, expr(node.value), line)
        when Prism::MultiWriteNode then MultiAssign.new(multi_target(node), expr(node.value), line, taken)
        when Prism::LocalVariableOperatorWriteNode
          Assign.new(node.name, node.depth, noted(Send.of(Local.new(node.name, node.depth, line), node.binary_operator, [expr(node.value)], line), node), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LambdaNode then lambda_literal(node, line)
        when Prism::ItLocalVariableReadNode then Local.new(IT, 0, line)
        when Prism::UndefNode then undef_names(node, line)
        when Prism::SuperNode then super_call(node, line)
        when Prism::ForwardingSuperNode then zsuper(node, line)
        when Prism::YieldNode
          args, kwargs, = arguments(node.arguments)
          Yield.new(args, line, kwargs)
        when Prism::BreakNode, Prism::NextNode
          value = jump_value(node.arguments, line)
          node.is_a?(Prism::BreakNode) ? Break.new(value, line) : Next.new(value, line)
        when Prism::IfNode then if_branch(node, line, taken: taken)
        when Prism::CaseMatchNode then case_match(node, taken: taken)
        when Prism::MatchRequiredNode then match_required(node)
        when Prism::MatchPredicateNode then match_predicate(node)
        when Prism::MatchWriteNode then match_write(node)
        when Prism::UnlessNode then unless_branch(node, line, taken: taken)
        when Prism::ElseNode then node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line)
        when Prism::WhileNode then while_loop(node, line)
        when Prism::UntilNode then until_loop(node, line)
        when Prism::ReturnNode
          top_return_warning if node.arguments
          Return.new(jump_value(node.arguments, line), line)
        # The left side decides, so its value is always used. The right
        # side is the result, so it has the pair's `taken`.
        when Prism::AndNode then And.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::ClassNode then class_body(node, line)
        when Prism::ModuleNode then module_body(node, line)
        when Prism::SingletonClassNode then singleton_class_body(node, line)
        when Prism::ConstantReadNode then const_read(node, line)
        when Prism::ConstantPathNode then const_path_read(node, line)
        when Prism::ConstantWriteNode then ConstWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathWriteNode
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when Prism::InterpolatedStringNode then interpolated_string(node, line)
        when Prism::SourceFileNode then source_file(node, line)
        when Prism::SourceLineNode then Literal.new(line, line)
        when Prism::SourceEncodingNode
          Send.of(ConstRead.new(nil, :Encoding, line), :find, [Literal.new(@encoding.name, line)], line)
        when Prism::InterpolatedSymbolNode then Send.of(interpolation(node, line), :to_sym, [], line)
        # A static command is a frozen String, as CRuby passes it to `.
        when Prism::XStringNode then Send.of(nil, :`, [frozen_literal_string(node.unescaped, line)], line)
        # Prism gives 0 for a number too big for a variable, which is always nil.
        when Prism::NumberedReferenceReadNode then node.number.zero? ? Literal.new(nil, line) : BackRef.new(:nth, node.number, line)
        when Prism::BackReferenceReadNode then back_reference(node, line)
        when Prism::RegularExpressionNode then regexp_literal(node, line, taken: taken)
        when Prism::InterpolatedRegularExpressionNode then interpolated_regexp(node, line)
        when Prism::MatchLastLineNode
          # A bare regexp as a condition matches `$_`.
          Send.of(regexp_literal(node, line), :=~, [GvarRead.new(:$_, line)], line)
        when Prism::InterpolatedMatchLastLineNode
          Send.of(interpolated_regexp(node, line), :=~, [GvarRead.new(:$_, line)], line)
        when Prism::InterpolatedXStringNode then Send.of(nil, :`, [interpolation(node, line)], line)
        when Prism::ArrayNode then ArrayLit.new(node.elements.map { |e| array_element(e, line) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
        when Prism::FlipFlopNode then flip_flop(node, line)
        when Prism::ShareableConstantNode then shareable_constant(node, line)
        when Prism::RangeNode then range_literal(node, line)
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::GlobalVariableReadNode then gvar_read(node.name, line)
        when Prism::GlobalVariableWriteNode then gvar_write(node.name, expr(node.value), line)
        when Prism::GlobalVariableOperatorWriteNode
          gvar_write(node.name, Send.of(gvar_read(node.name, line), node.binary_operator, [expr(node.value)], line), line)
        # `x ||= v` is `x || (x = v)`, and `x &&= v` is `x && (x = v)`. The
        # write occurs only if necessary. A frozen receiver, a global's
        # setter and a constant's redefinition warning can see this.
        when Prism::GlobalVariableOrWriteNode then Or.new(quiet_gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::GlobalVariableAndWriteNode then And.new(gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::ClassVariableReadNode then CvarRead.new(node.name, line)
        when Prism::ClassVariableWriteNode then CvarWrite.new(node.name, expr(node.value), line)
        when Prism::ClassVariableOperatorWriteNode
          CvarWrite.new(node.name, Send.of(CvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line), line)
        when Prism::ClassVariableOrWriteNode
          If.new(Defined.new(:cvar, node.name, line), Or.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line), CvarWrite.new(node.name, expr(node.value), line), line)
        # Ruby compiles nothing for a `defined?` whose value is not used.
        when Prism::DefinedNode then taken ? defined(node.value, line) : Literal.new(nil, line)
        when Prism::ClassVariableAndWriteNode then And.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::ConstantOrWriteNode then ConstOrWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathOrWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstOrWrite.new(scope, name, expr(node.value), line), line)
        when Prism::ConstantAndWriteNode
          And.new(ConstRead.new(nil, node.name, line), ConstWrite.new(nil, node.name, expr(node.value), line), line)
        when Prism::ConstantPathAndWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, And.new(ConstRead.new(scope, name, line), ConstWrite.new(scope, name, expr(node.value), line), line), line)
        when Prism::ConstantOperatorWriteNode
          ConstWrite.new(nil, node.name, Send.of(ConstRead.new(nil, node.name, line), node.binary_operator, [expr(node.value)], line), line)
        when Prism::ConstantPathOperatorWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstWrite.new(scope, name, Send.of(ConstRead.new(scope, name, line), node.binary_operator, [expr(node.value)], line), line), line)
        when Prism::AliasMethodNode then alias_method_names(node, line)
        when Prism::AliasGlobalVariableNode then alias_global(node, line)
        when Prism::CaseNode then case_when(node, line, taken: taken)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode then index_op_assign(node, line)
        when Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode then attr_op_assign(node, line)
        when Prism::ForNode then for_loop(node)
        when Prism::PostExecutionNode then post_execution(node, line)
        when Prism::PreExecutionNode
          unsupported(node, "BEGIN { } outside the toplevel") unless @block_depth.zero?
          node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::InstanceVariableWriteNode then IvarWrite.new(node.name, expr(node.value), line)
        when Prism::InstanceVariableOperatorWriteNode
          IvarWrite.new(node.name, Send.of(IvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line), line)
        when Prism::InstanceVariableOrWriteNode
          Or.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::InstanceVariableAndWriteNode
          And.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::BeginNode then protected_region(node, taken: taken)
        when Prism::RescueModifierNode
          clause = Rescue.new([], nil, expr(node.rescue_expression), line)
          Begin.new(expr(node.expression), [clause], nil, nil, line)
        # Ruby's compiler writes no code for a branch that it knows is
        # never taken, so a `retry` there is never an error.
        when Prism::RetryNode then @dead.positive? ? Literal.new(nil, line) : Retry.new(line)
        when Prism::RedoNode then Redo.new(line)
        else unsupported(node)
        end
      end

      # `begin ... end` with its clauses. A bare `begin ... end` is its
      # body. A region's body and its `else` give the region's value, and
      # have its `taken`. An `ensure` runs only for its effect, so its
      # value is never used. A `rescue` body is different: ruby reads a
      # regexp there even if the region's value is not used.
      #: (Prism::BeginNode node, ?taken: bool) -> node
      def protected_region(node, taken: true)
        line = node.location.start_line
        body = guarded(node.rescue_clause) { node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line) }
        return body if node.rescue_clause.nil? && node.ensure_clause.nil?

        rescues = [] #: Array[Rescue]
        # @type var clause: Prism::RescueNode?
        clause = node.rescue_clause
        while clause
          rescues << rescue_clause(clause)
          clause = clause.subsequent
        end
        else_body = node.else_clause && (node.else_clause.statements ? seq(node.else_clause.statements, taken: taken) : Literal.new(nil, line))
        ensure_body = node.ensure_clause && (node.ensure_clause.statements ? seq(node.ensure_clause.statements, taken: false) : Literal.new(nil, line))
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

      #: (Prism::RescueNode node) -> Rescue
      def rescue_clause(node)
        line = node.location.start_line
        classes = node.exceptions.map { |e| e.is_a?(Prism::SplatNode) ? splat(e, line) : expr(e) }
        Rescue.new(classes, node.reference && target(node.reference), node.statements ? seq(node.statements) : Literal.new(nil, line), line)
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
          begin
            in_scope do
              params = parameters(node.parameters)
              @def_params = params
              body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
              body = marked(body, marks, node.location.start_line) unless marks.empty?
              locals = with_temps(node.locals + (params.names - node.locals))
              Def.new(node.name, params, locals, body, node.location.start_line, receiver, evals?(node.body), node.location.end_line,
                      method_cover(node))
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
        @singleton = singleton
        @body_marks = []
        begin
          yield
        ensure
          @path.pop if name
          @singleton = was
          @using = using
          @body_marks = marks
        end
      end

      # A bare `super`: passes the method's parameters with their current
      # values, as a `Super` with the locals of the enclosing def.
      #: (Prism::ForwardingSuperNode node, Integer line) -> (ZSuper | Super)
      def zsuper(node, line)
        p = @def_params or return ZSuper.new(node.block && block(node.block), line)

        local = lambda do |name|
          name = name.whole if name.is_a?(MultiTarget)
          depths = @def_depths
          Local.new(name, @block_depth + (depths ? depths.fetch(name) : 0), line)
        end
        positional = (p.required + p.optional.map(&:first)).map(&local) #: Array[node]
        positional << Splat.new(local.call(p.rest), line) if p.rest && p.rest != :implicit
        positional += p.post.map(&local)
        # The rest goes in first, in the order that ruby's own zsuper
        # builds the hash.
        pairs = p.kwrest && p.kwrest != :nokey ? [HashSplat.new(local.call(p.kwrest), line), nil] : [] #: Array[node?]
        pairs += p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        kwargs = pairs.empty? ? nil : HashLit.new(pairs, line)
        block = node.block ? block(node.block) : (p.block && BlockPass.new(local.call(p.block), line))
        Super.new(positional, kwargs, block, line, @block_depth.positive?)
      end

      # A ParametersNode as one Params.
      #: (Prism::ParametersNode? node) -> Params
      def parameters(node)
        return Params.new([], [], nil, [], [], nil, nil) if node.nil?

        required = node.requireds.map { |p| name_of(p) }
        optional = node.optionals.map { |p| optional_param(p) }
        rest = node.rest && rest_name(node.rest)
        post = node.posts.map { |p| name_of(p) }
        keywords = node.keywords.map do |k|
          case k
          when Prism::RequiredKeywordParameterNode then [k.name, nil]
          when Prism::OptionalKeywordParameterNode then [k.name, expr(k.value)]
          end
        end
        kwrest = node.keyword_rest && rest_name(node.keyword_rest)
        if node.keyword_rest.is_a?(Prism::ForwardingParameterNode)
          rest = ANONYMOUS[:rest]
          kwrest = ANONYMOUS[:kwrest]
          block = ANONYMOUS[:block]
        else
          block = node.block && (node.block.name || ANONYMOUS[:block])
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
        rest = case node.rest
               when nil then nil
               when Prism::ImplicitRestNode then :implicit
               when Prism::SplatNode then node.rest.expression ? target(node.rest.expression) : :implicit
               else unsupported(node.rest)
               end
        MultiTarget.new(node.lefts.map { |t| target(t) }, rest, node.rights.map { |t| target(t) }, line)
      end

      # One target of a multiple assignment.
      #: (Prism::node node) -> node
      def target(node)
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
          noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                          node.location.end_line, method_cover(node)), node)
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
        # The core's `+"text"` under its frozen_string_literal comment: a
        # new String, as its C makes, with no send of +@.
        return Literal.new(unescaped(node.receiver), node.location.start_line, false) if node.name == :+@ && node.receiver.is_a?(Prism::StringNode) && node.block.nil? && Library::Roots.runtime_file?(@file)
        return require_node(node) if REQUIRES.include?(node.name) && node.receiver.nil? && node.block.nil? && !shadowed?(node.name) && !@loader&.eval? && literal_feature(node)
        return autoload_node(node) if node.name == :autoload && node.block.nil? && literal_autoload?(node)
        return newarray_send(node) if newarray_send?(node)

        send = plain_call(node)
        relative_in_file(node, send)
      end

      # compile.c's opt_newarray_send: `[a, b].min` or `.max` on a literal
      # that is not static and has no splat runs without Array#min, which
      # compares in the other order. The core's own files keep the send, and
      # so does a site under `using`, where a refinement may answer.
      #: (Prism::CallNode node) -> bool
      def newarray_send?(node)
        %i[min max].include?(node.name) && node.receiver.is_a?(Prism::ArrayNode) && !node.receiver.static_literal? &&
          node.receiver.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) } &&
          node.arguments.nil? && node.block.nil? && node.call_operator != "&." && !Library::Roots.runtime_file?(@file) && @using.nil?
      end

      # The program itself sends the method when it is redefined, so the
      # send sees what the program sees.
      #: (Prism::CallNode node) -> Seq
      def newarray_send(node)
        line = node.location.start_line
        items = temp("items")
        optimized = send_to(core(:Array, line), :newarray_optimized?, [Literal.new(node.name, line)], line)
        fast = send_to(core(:Array, line), :"newarray_#{node.name}", [read(items, line)], line)
        Seq.new([set(items, expr(node.receiver), line), If.new(optimized, fast, send_to(read(items, line), node.name, [], line), line)], line)
      end

      # A file of the program uses rubygems' API. rubygems' own files and
      # the runtime's files do not count.
      #: (Symbol name) -> void
      def gems!(name)
        @loader.gems!(name) if @loader && !@loader.ahead?(@file) && !Library::Roots.runtime_file?(@file)
      end

      # `Primitive.attr! :ruby`, `:hidden`, `:ivars`, `:sends_each` or `:sends_ops` in a
      # class body of the core library: every later def in that body gets
      # the attribute, as if each def started with it. `:ruby` marks
      # methods that CRuby writes in Ruby. `:hidden` marks a class of
      # helpers that CRuby writes as a C struct. `:ivars` marks a class
      # whose instance variables CRuby shows. `:sends_each` marks methods
      # that send `each` by name, as CRuby's rb_block_call does. `:sends_ops`
      # marks methods whose operators send by name, as CRuby's f_add does.
      #: (Prism::CallNode node) -> Symbol?
      def body_mark(node)
        mark = node.arguments&.arguments&.first
        return unless !@in_def && node.name == :attr! && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Primitive &&
                      mark.is_a?(Prism::SymbolNode) && %w[ruby hidden ivars sends_each sends_ops].include?(mark.unescaped)

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
        kernel = compiles && ((node.receiver.nil? && !shadowed?(node.name)) ||
                              (node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Kernel))
        @loader.evals!(node.name, args, kernel: kernel)
        gems!(:Gem) if node.name == :gem && node.receiver.nil?
        @loader.load_path_changed!(node, @file)
        @loader.normalizes!(node.name, args)
        # `&:name` calls that method, as a call with that name does.
        if node.block.is_a?(Prism::BlockArgumentNode) && node.block.expression.is_a?(Prism::SymbolNode)
          @loader.normalizes!(node.block.expression.unescaped.to_sym, [])
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
        blk = node.block ? in_refine(node) { block(node.block) } : forwarded
        safe = node.call_operator == "&."
        # Both branches of a safe call have the call's location, as CRuby
        # records. `branch_covers` returns nils if nothing is measured, and
        # then the Send has no covers.
        covers = safe ? branch_covers(:"&.", span(node.location), [[:then, span(node.location)], [:else, span(node.location)]]) : nil
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
        when Prism::ConstantReadNode, Prism::ConstantPathNode then Defined.new(:const, expr(node), line)
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

          inner = node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 ? node.body.body.first : nil
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
                   MultiTarget.new([], index.expression ? target(index.expression) : :implicit, [], line)
                 else
                   target(index)
                 end
        target = deepen(target, 0)
        body = node.statements ? deepen(seq(node.statements), 0) : Literal.new(nil, line)
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
        block = Block.new(params, [:"*for"], Seq.new([bind, RedoPoint.new(line), body], line), line)
        Send.of(expr(node.collection), :each, [], line, block: block)
      end

      # `node` as read from one block scope deeper: every local at
      # `level` or more is one scope further out.
      #: (untyped node, Integer level) -> untyped
      def deepen(node, level)
        case node
        when Local, Assign
          node.depth += 1 if node.depth >= level
          node.value = deepen(node.value, level) if node.is_a?(Assign) && node.value
          node
        when Block
          node.body = deepen(node.body, level + 1)
          node.params.optional.each { |pair| pair[1] = deepen(pair[1], level + 1) }
          node.params.keywords.each { |pair| pair[1] = deepen(pair[1], level + 1) if pair[1] }
          node
        when Def
          node.receiver = deepen(node.receiver, level) if node.receiver
          node
        when ClassDef
          node.scope = deepen(node.scope, level) if Hir.node?(node.scope)
          node.superclass = deepen(node.superclass, level) if node.superclass
          node
        when ModuleDef
          node.scope = deepen(node.scope, level) if Hir.node?(node.scope)
          node
        when SingletonClassDef
          node.target = deepen(node.target, level)
          node
        when Node
          node.each_pair { |k, v| node[k] = deepen(v, level) if Hir.node?(v) || v.is_a?(Array) }
          node
        when Array then node.map! { |v| Hir.node?(v) || v.is_a?(Array) ? deepen(v, level) : v }
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
          else expr(a)
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
      def splat(node, line)
        Splat.new(node.expression ? expr(node.expression) : anonymous(:rest, line), line)
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
          Lambda.new(noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, node.opening_loc.start_line,
                                     node.location.end_line, method_cover(node)), node), line)
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
        Super.new(args, kwargs, node.block ? block(node.block) : forwarded, line)
      end

      #: (Prism::IfNode node, Integer line, taken: bool) -> If
      def if_branch(node, line, taken:)
        chosen = chooses?(node.predicate)
        # The predicate gets its number first, because ruby's compiler
        # writes it first. If ruby decides the predicate at compile time,
        # it drops the whole branch, and Coverage records nothing.
        predicate = expr(node.predicate)
        then_cover, else_cover = chosen.nil? ? branch_covers(:if, span(node.location), if_sides(node)) : [nil, nil]
        If.new(predicate,
               covered(then_cover, node.statements && dead(chosen == false) { seq(node.statements, taken: taken && chosen != false) }, line),
               covered(else_cover, node.subsequent && dead(chosen == true) { expr(node.subsequent, taken: taken && chosen != true) }, line), line)
      end

      #: (Prism::UnlessNode node, Integer line, taken: bool) -> If
      def unless_branch(node, line, taken:)
        chosen = chooses?(node.predicate)
        # Ruby lists an `unless`'s else before its then, and numbers them
        # in that order. The branch test is the same.
        predicate = expr(node.predicate)
        else_cover, then_cover = chosen.nil? ? branch_covers(:unless, span(node.location), unless_sides(node)) : [nil, nil]
        If.new(predicate,
               covered(else_cover, node.else_clause && dead(chosen == false) { seq(node.else_clause.statements, taken: taken && chosen != false) }, line),
               covered(then_cover, node.statements && dead(chosen == true) { seq(node.statements, taken: taken && chosen != true) }, line), line)
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
        scope, name = constant_path(node.constant_path)
        @loader&.module_defined!(@path, node.constant_path.slice)
        superclass = node.superclass && expr(node.superclass)
        in_definee(node.constant_path.slice, false) do
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            ClassDef.new(scope, name, superclass, with_temps(node.locals), body, line, node.location.end_line)
          end
        end
      end

      #: (Prism::ModuleNode node, Integer line) -> ModuleDef
      def module_body(node, line)
        scope, name = constant_path(node.constant_path)
        @loader&.module_defined!(@path, node.constant_path.slice)
        in_definee(node.constant_path.slice, false) do
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
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

      #: (Prism::ConstantReadNode node, Integer line) -> ConstRead
      def const_read(node, line)
        @loader&.compiles!(node.name) unless @loader&.module_defined?(@path, node.name)
        gems!(node.name)
        ConstRead.new(nil, node.name, line)
      end

      #: (untyped node, Integer line) -> ConstRead
      def const_path_read(node, line)
        # `Prism::Ruby` is not Ruby::Box: only a top-level `Ruby` compiles.
        @loader&.compiles!(node.name) unless node.name == :Ruby && node.parent
        gems!(node.name) if node.parent.nil?
        scope, name = constant_path(node)
        ConstRead.new(scope, name, line)
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
        if node.new_name.is_a?(Prism::SymbolNode) && node.old_name.is_a?(Prism::SymbolNode)
          Alias.new(node.new_name.unescaped.to_sym, node.old_name.unescaped.to_sym, line)
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
        clauses = node.conditions.map.with_index do |w, i|
          values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? splat(c, line) : expr(c) }
          [values, covered(covers[i], w.statements ? seq(w.statements, taken: taken) : Literal.new(nil, line), line)]
        end
        other = node.else_clause && expr(node.else_clause, taken: taken)
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
        body = deepen(deepen(node.statements ? seq(node.statements) : Literal.new(nil, line), 0), 0)
        none = Params.new([], [], nil, [], [], nil, nil)
        register = Send.of(Core.new(:Kernel, line), :at_exit, [], line, block: Block.new(none, [], body, line))
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
require_relative "build/requires"
