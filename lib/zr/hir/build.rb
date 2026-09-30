# frozen_string_literal: true

require_relative "../parse"
require_relative "../paths"
require_relative "../refused"
require_relative "../libraries"
require_relative "../ports"
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

    # A literal require in the program's own files that no root has, in a
    # build with the gate (`Build#gate!`). It is an error in the program's
    # setup, not a form of Ruby that zr refuses.
    class Missing < StandardError; end

    # Prism to HIR. A form that the HIR does not support yet is refused,
    # with a message that gives the form and the line. The rule: the same
    # as CRuby, or refused. Never a guess.
    class Build
      # Ruby's own library and the default gems, from vendor/
      # (lib/zr/libraries.rb).
      def self.pure = Libraries.root

      # The extensions whose native part is zr's. A file here is part of
      # the runtime, so it can call a kernel def through `Primitive`.
      EXT = Layout::EXT
      # The runtime's own Ruby, the core library and the extensions: code
      # that a TracePoint never sees.
      RUNTIME = Paths::RUNTIME
      # The named calls that a site lowers to a kernel entry with a core
      # fast path (Zr::Lower::Function::Sends::OPT_ENTRIES), with each
      # one's argument count. A call with a different count, or with a
      # block, keywords or a splat, raises or does something different,
      # and only the real call can tell.
      OPT_CALLS = { getbyte: 1, setbyte: 2, push: 1, pop: 0, shift: 0, empty?: 0 }.freeze

      def self.runtime_file?(file) = File.expand_path(file).start_with?("#{RUNTIME}/")

      # The gems whose C zr ports, at zr's versions, as vendor/ holds
      # them (lib/zr/ports.rb).
      GEMS = Ports.roots.freeze
      # The bundled gems, each in its own directory, as ruby installs them.
      def self.bundled = Libraries.apart

      # The library roots for `target`, in search order. zr's own code
      # comes first: the OS layer's native parts and tables, then the
      # portable ones. A file there replaces an upstream file of the same
      # name (runtime/ext/date.rb, not ruby's date.rb). Then the port gems,
      # which win over ruby's own copies as an installed gem wins over a
      # default gem (json 3.0.2, not 2.18.0), then ruby's own library,
      # then the bundled gems in their own directories.
      def self.stdlib(target = Target.default)
        (@stdlib ||= {})[target.triple] ||= [Layout.ext_os(target), EXT, *GEMS, pure, *bundled].freeze
      end

      # The compiler that a program with eval links in, and the
      # tree-walking interpreter for a program that cannot write machine
      # code into itself. Both contain the same front end. `Zr::Eval`
      # gives the back end that each one runs.
      EVAL_COMPILER = File.expand_path("../eval.rb", __dir__)
      EVAL_INTERPRETER = File.expand_path("../eval/walk.rb", __dir__)

      # The eval support file for `target`. `ZR_EVAL=walk` selects the
      # tree-walking interpreter where the eval compiler (JIT) could run.
      # The tests use this to check the interpreter against the JIT.
      def self.eval_file(target = Target.default)
        target.jits? && !Config.current.eval_walk? ? EVAL_COMPILER : EVAL_INTERPRETER
      end

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
      def self.program(source, file, roots: [], eval_support: true, prebuilt: nil, line: 1, scopes: nil, method: nil, activations: nil, target: Target.default,
                       trace: false, gem_set: nil, gate: false)
        # The main file's name came from the build's command line, in the
        # build's locale. A program's locale is UTF-8
        # (Encoding.locale_charmap), and the name must not depend on the
        # build machine.
        file = file.dup.force_encoding(::Encoding::UTF_8) if eval_support && file.encoding != ::Encoding::UTF_8
        built = lambda do |external, trace, evals, covers|
          loader = Loader.new(roots + (gem_set&.roots || []) + stdlib(target), eval: !eval_support, external: external, trace: trace,
                              evals: evals, covers: covers, activations: activations, prebuilt_eval: prebuilt, gem_set: gem_set,
                              gate: gate)
          loader.own!(file)
          [loader, loader.unit(file, source, line, scopes, method: method)]
        end
        # A build knows three facts only after it reads every file: that
        # the program uses eval, TracePoint, or Coverage. Each fact needs
        # a different build: with eval support (its files are referred to,
        # not read), with the events armed, or with the branch counters. A
        # prelude can also cause any of them (`binding.irb` loads
        # fileutils, and fileutils evals). So the build repeats: read, add
        # the preludes, and build again while any fact changed. Each fact
        # can only change from false to true, so the loop ends.
        loader = main = preludes = nil
        evals = covers = false
        external = nil
        loop do
          loader, main = built.call(external, trace, evals, covers)
          preludes = eval_support ? Build.preludes(loader, target) : []
          over = loader.evals? ? prebuilt : nil
          break if over.equal?(external) && (loader.traces? || trace) == trace && loader.covers? == covers

          evals = loader.evals?
          external = over
          trace ||= loader.traces?
          covers = loader.covers?
        end
        # A program with eval numbers its `using` entries here. A compile
        # at run time cannot see how many there are, because an entry
        # under a condition is made only if the condition is true. So all
        # entries are taken before the first line, and a compile at run
        # time starts after the last of them.
        preludes += [Activations.new(loader.activations, 0)] if eval_support && loader.evals? && loader.activations.positive?
        body = preludes.empty? ? main.body : Seq.new([*preludes, main.body], 0)
        body = Seq.new([data(main, loader.data_at(main.file)), body], 0) if loader.data_at(main.file)
        spots = [main, *loader.units].filter_map { |unit| [unit.file, unit.spots] if unit.spots && !unit.spots.empty? }.to_h
        coverable = loader.covers? ? loader.coverable : {}
        Program.new(main.file, main.locals, body, loader.units, main.warnings, eval_support && loader.evals?, loader.entries, loader.tracing?,
                    main.node_ids, spots, coverable, loader.activations, loader.covers? ? loader.branches : {},
                    loader.covers? ? loader.defs : {})
      end

      def initialize(file, loader = nil, encoding = ::Encoding::UTF_8, shadowed: {}, root: nil, eval: false)
        @file = file
        @eval = eval
        @loader = loader
        @root = root
        # The prism node id of each HIR node that this file builds, by
        # identity. The file's Unit keeps it, and the lowering drops it
        # with the unit's tree (`Lower#spent`).
        @node_ids = loader && {}.compare_by_identity
        @encoding = encoding
        @shadowed = shadowed
        @path = [Object.name]
        @singleton = false
        @body_marks = []
        @block_depth = 0
        @using = nil
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
      def within_method(rows, scopes)
        return if rows.any? { |_, name| name.nil? || scopes.none? { |names| names.include?(name) } }

        required, optional, post, keywords = [], [], [], []
        rest = kwrest = block = nil
        rows.each do |kind, name|
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
        @def_depths = rows.to_h { |_, name| [name, 1 + scopes.index { |names| names.include?(name) }] }
      end

      # The warnings ruby's compiler gives for the file's regexp literals,
      # after the parser's own.
      attr_reader :warnings

      # The prism node id of each HIR node that this file built, or nil.
      attr_reader :node_ids

      # Ruby's compiler warns as it compiles a file (not an eval) with a
      # `return` of a value at its top level, where the value goes
      # nowhere. The warning has the file and no line. A `return` in a
      # `class << self` body belongs to a method or a block, never to the top level.
      def top_return_warning
        return if @eval || @in_def || @in_sclass || @block_depth.positive? || @path != [Object.name]

        @warnings << "#{Paths.shown(@file)}: warning: argument of top-level return is ignored"
      end

      # The hidden locals the toplevel scope needs.
      def temps = @temps.first

      # The names of the anonymous parameters `*`, `**`, `&` and `...`,
      # as locals of the def that declares them.
      ANONYMOUS = { rest: :*, kwrest: :**, block: :& }.freeze

      # Builds `body` in a branch that a literal condition never takes,
      # if `never` is true.
      def dead(never)
        @dead += 1 if never
        yield
      ensure
        @dead -= 1 if never
      end

      # Builds `body` one block scope deeper. A `using` in a block at the
      # top level of a file refines the file's own scope, so it applies to
      # the rest of the file after the block, as in ruby.
      def in_block
        @block_depth += 1
        using = @using
        @temps.push([])
        @last_lines.push(-1)
        yield
      ensure
        @block_depth -= 1
        @using = using unless @path == [Object.name] && !@in_def
        @temps.pop
        @last_lines.pop
      end

      # Builds `body` in a new scope: a def or a class body.
      def in_scope
        was = [@block_depth, @def_params, @def_depths]
        @block_depth = 0
        @def_params = nil
        @def_depths = nil
        @temps.push([])
        @scopes.push(@temps.last)
        @last_lines.push(-1)
        yield
      ensure
        @block_depth, @def_params, @def_depths = was
        @temps.pop
        @scopes.pop
        @last_lines.pop
      end

      # A scope's locals: the parser's, then the hidden ones from its body.
      def with_temps(locals) = locals + @temps.last

      # The globals that are in the frame or the task, not the global
      # table. An alias of one is a second name that the lowering resolves.
      FRAME_GVARS = %i[$~ $_ $! $@].freeze

      # The other names ruby gives one global.
      GVAR_ALIASES = {
        :$PROGRAM_NAME => :$0, :$: => :$LOAD_PATH, :$-I => :$LOAD_PATH, :$" => :$LOADED_FEATURES, :$> => :$stdout,
        :$-0 => :$/, :$-F => :$;, :$-v => :$VERBOSE, :$-w => :$VERBOSE, :$-d => :$DEBUG
      }.freeze

      def gvar_name(name)
        GVAR_ALIASES.fetch(name, name)
      end

      # A `$name` read: through an alias of a frame global, `$@` as the
      # backtrace of `$!`, or the global itself.
      def gvar_read(name, line)
        aliased = @loader&.back_ref(name)
        if aliased && (flag = @loader.alias_flag(name))
          return If.new(GvarRead.new(flag, line), expr(aliased), GvarRead.new(gvar_name(name), line), line)
        end
        return expr(aliased) if aliased
        return Send.of(GvarRead.new(:$!, line), :backtrace, [], line, safe: true) if name == :$@

        GvarRead.new(gvar_name(name), line)
      end

      # `$name = value`: a write through an alias of a frame global goes to
      # that global, and keeps the program's name for error messages.
      # Every back reference is read-only, as `$&` is.
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
      def flip_flop(node, line)
        state = flip_flop_state
        depth = @block_depth
        ends = -> { If.new(end_test(node.right, line), Assign.new(state, depth, Literal.new(false, line), line), nil, line) }
        # `...` waits for the next run before it can turn off. `..` tests
        # the right side at once, so a one-run range ends where it started.
        started = [Assign.new(state, depth, Literal.new(true, line), line)]
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
      def end_test(node, line)
        return Literal.new(nil, line) unless node
        return Send.new(gvar_read(:$., line), :==, [expr(node)], line, false) if node.is_a?(Prism::IntegerNode)

        expr(node)
      end

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
      def seq(node, hoist: false, taken: true)
        return Seq.new([], 1) if node.nil?

        body = node.body
        if hoist
          early, rest = body.partition { |s| s.is_a?(Prism::PreExecutionNode) }
          body = early + rest
        end
        last = body.size - 1
        Seq.new(body.each_with_index.map { |s, i| statement(s, taken: taken && i == last) }, node.location.start_line)
      end

      # One statement. Each send in it gets the activation that is active
      # at the statement. A `using` changes the activation for the
      # statements after it.
      def statement(node, taken: true)
        # `using_activation` makes every `using` entry, so a statement that
        # made none contains none. Then skip the walk below, which reads
        # all of the new statement, for every statement of every file.
        # Almost no file has a `using`.
        made = @usings
        traced = line_event(node)
        out = using_activation(node) || expr(node, taken: taken)
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

      def mark_using(node, seen)
        return if node.nil? || seen.key?(node.object_id)

        if node.is_a?(Array)
          node.each { |child| mark_using(child, seen) }
          return
        end
        return unless node.is_a?(Node)

        seen[node.object_id] = true
        node.using = @using if [Send, Super, AttrOpAssign, IndexOpAssign].any? { |type| node.is_a?(type) } && node.using.nil?
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
      def expr(node, taken: true)
        noted(built(node, taken), node)
      end

      # `hir` came from prism's `node`. Its frame reports that node's id,
      # as node_id_for_backtrace_location reads it. A HIR node that an
      # inner prism node already built keeps the inner node's id.
      def noted(hir, node)
        @node_ids[hir] ||= node.node_id if @node_ids && hir.is_a?(Node)
        hir
      end

      def built(node, taken = true)
        line = node.location.start_line
        case node
        when Prism::StatementsNode then seq(node, taken: taken)
        when Prism::ParenthesesNode then node.body ? expr(node.body, taken: taken) : Literal.new(nil, line)
        when Prism::IntegerNode, Prism::FloatNode then Literal.new(node.value, line)
        # `3r` and `2i` use the core's Kernel, even if self has no Kernel.
        when Prism::RationalNode then Send.new(Core.new(:Kernel, line), :Rational, [Literal.new(node.numerator, line), Literal.new(node.denominator, line)], line, false)
        when Prism::ImaginaryNode then Send.new(Core.new(:Kernel, line), :Complex, [Literal.new(0, line), expr(node.numeric)], line, false)
        when Prism::StringNode then literal_string(node, unescaped(node), line)
        when Prism::SymbolNode then Literal.new(node.unescaped.to_sym, line)
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
          Assign.new(node.name, node.depth, noted(Send.new(Local.new(node.name, node.depth, line), node.binary_operator, [expr(node.value)], line, false), node), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LambdaNode
          in_block do
            params, extra = block_params(node.parameters)
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            Lambda.new(noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                                       node.location.end_line, method_cover(node)), node), line)
          end
        when Prism::ItLocalVariableReadNode then Local.new(IT, 0, line)
        when Prism::UndefNode
          return UndefValue.new(node.names.map { |n| expr(n) }, line) unless node.names.all?(Prism::SymbolNode)

          names = node.names.map { |n| n.unescaped.to_sym }
          Undef.new(names, line)
        when Prism::SuperNode
          args, kwargs, forwarded = arguments(node.arguments)
          Super.new(args, kwargs, node.block ? block(node.block) : forwarded, line)
        when Prism::ForwardingSuperNode then zsuper(node, line)
        when Prism::YieldNode
          args, kwargs, = arguments(node.arguments)
          Yield.new(args, line, kwargs)
        when Prism::BreakNode, Prism::NextNode
          value = jump_value(node.arguments, line)
          node.is_a?(Prism::BreakNode) ? Break.new(value, line) : Next.new(value, line)
        when Prism::IfNode
          chosen = chooses?(node.predicate)
          # The predicate gets its number first, because ruby's compiler
          # writes it first. If ruby decides the predicate at compile time,
          # it drops the whole branch, and Coverage records nothing.
          predicate = expr(node.predicate)
          then_cover, else_cover = chosen.nil? ? branch_covers(:if, span(node.location), if_sides(node)) : [nil, nil]
          If.new(predicate,
                 covered(then_cover, node.statements && dead(chosen == false) { seq(node.statements, taken: taken && chosen != false) }, line),
                 covered(else_cover, node.subsequent && dead(chosen == true) { expr(node.subsequent, taken: taken && chosen != true) }, line), line)
        when Prism::CaseMatchNode then case_match(node, taken)
        when Prism::MatchRequiredNode then match_required(node)
        when Prism::MatchPredicateNode then match_predicate(node)
        when Prism::MatchWriteNode then match_write(node)
        when Prism::UnlessNode
          chosen = chooses?(node.predicate)
          # Ruby lists an `unless`'s else before its then, and numbers them
          # in that order. The branch test is the same.
          predicate = expr(node.predicate)
          else_cover, then_cover = chosen.nil? ? branch_covers(:unless, span(node.location), unless_sides(node)) : [nil, nil]
          If.new(predicate,
                 covered(else_cover, node.else_clause && dead(chosen == false) { seq(node.else_clause.statements, taken: taken && chosen != false) }, line),
                 covered(then_cover, node.statements && dead(chosen == true) { seq(node.statements, taken: taken && chosen != true) }, line), line)
        when Prism::ElseNode then node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line)
        # A loop returns nil, so its body's value is not used.
        when Prism::WhileNode
          body, = branch_covers(:while, span(node.location), loop_sides(node))
          While.new(expr(node.predicate), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                    node.begin_modifier?)
        when Prism::UntilNode
          body, = branch_covers(:until, span(node.location), loop_sides(node))
          While.new(falsy(expr(node.predicate), line), covered(body, node.statements && seq(node.statements, taken: false), line), line,
                    node.begin_modifier?)
        when Prism::ReturnNode
          top_return_warning if node.arguments
          Return.new(jump_value(node.arguments, line), line)
        # The left side decides, so its value is always used. The right
        # side is the result, so it has the pair's `taken`.
        when Prism::AndNode then And.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right, taken: taken), line)
        when Prism::ClassNode
          scope, name = constant_path(node.constant_path)
          superclass = node.superclass && expr(node.superclass)
          in_definee(node.constant_path.slice, false) do
            in_scope do
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              ClassDef.new(scope, name, superclass, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          in_definee(node.constant_path.slice, false) do
            in_scope do
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              ModuleDef.new(scope, name, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::SingletonClassNode
          target = expr(node.expression)
          in_definee(nil, true) do
            in_scope do
              was, @in_sclass = @in_sclass, true
              body = node.body ? expr(node.body) : Literal.new(nil, line)
              @in_sclass = was
              SingletonClassDef.new(target, with_temps(node.locals), body, line, node.location.end_line)
            end
          end
        when Prism::ConstantReadNode
          @loader&.compiles!(node.name)
          gems!(node.name)
          ConstRead.new(nil, node.name, line)
        when Prism::ConstantPathNode
          @loader&.compiles!(node.name)
          gems!(node.name) if node.parent.nil?
          scope, name = constant_path(node)
          ConstRead.new(scope, name, line)
        when Prism::ConstantWriteNode then ConstWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathWriteNode
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when Prism::InterpolatedStringNode
          if node.frozen? then frozen_literal_string(static_text(node), line)
          # Adjacent literals with nothing interpolated are one literal.
          elsif static_string?(node) then Literal.new(static_text(node), line, !node.mutable?)
          else interpolation(node, line)
          end
        when Prism::SourceFileNode then literal_string(node, Paths.shown(@file), line)
        when Prism::SourceLineNode then Literal.new(line, line)
        when Prism::SourceEncodingNode
          Send.new(ConstRead.new(nil, :Encoding, line), :find, [Literal.new(@encoding.name, line)], line, false)
        when Prism::InterpolatedSymbolNode then Send.new(interpolation(node, line), :to_sym, [], line, false)
        when Prism::XStringNode then Send.new(nil, :`, [Literal.new(node.unescaped, line)], line, false)
        when Prism::NumberedReferenceReadNode then BackRef.new(:nth, node.number, line)
        when Prism::BackReferenceReadNode then back_reference(node, line)
        when Prism::RegularExpressionNode then regexp_literal(node, line, taken)
        when Prism::InterpolatedRegularExpressionNode then interpolated_regexp(node, line)
        when Prism::MatchLastLineNode
          # A bare regexp as a condition matches `$_`.
          Send.new(regexp_literal(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedMatchLastLineNode
          Send.new(interpolated_regexp(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedXStringNode then Send.new(nil, :`, [interpolation(node, line)], line, false)
        when Prism::ArrayNode then ArrayLit.new(node.elements.map { |e| array_element(e, line) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
        when Prism::FlipFlopNode then flip_flop(node, line)
        when Prism::ShareableConstantNode then shareable_constant(node, line)
        when Prism::RangeNode
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
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::GlobalVariableReadNode then gvar_read(node.name, line)
        when Prism::GlobalVariableWriteNode then gvar_write(node.name, expr(node.value), line)
        when Prism::GlobalVariableOperatorWriteNode
          gvar_write(node.name, Send.new(gvar_read(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        # `x ||= v` is `x || (x = v)`, and `x &&= v` is `x && (x = v)`. The
        # write occurs only if necessary. A frozen receiver, a global's
        # setter and a constant's redefinition warning can see this.
        when Prism::GlobalVariableOrWriteNode then Or.new(gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::GlobalVariableAndWriteNode then And.new(gvar_read(node.name, line), gvar_write(node.name, expr(node.value), line), line)
        when Prism::ClassVariableReadNode then CvarRead.new(node.name, line)
        when Prism::ClassVariableWriteNode then CvarWrite.new(node.name, expr(node.value), line)
        when Prism::ClassVariableOperatorWriteNode
          CvarWrite.new(node.name, Send.new(CvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::ClassVariableOrWriteNode
          If.new(Defined.new(:cvar, node.name, line), Or.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line), CvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::DefinedNode then defined(node.value, line)
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
          ConstWrite.new(nil, node.name, Send.new(ConstRead.new(nil, node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::ConstantPathOperatorWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstWrite.new(scope, name, Send.new(ConstRead.new(scope, name, line), node.binary_operator, [expr(node.value)], line, false), line), line)
        when Prism::AliasMethodNode
          if node.new_name.is_a?(Prism::SymbolNode) && node.old_name.is_a?(Prism::SymbolNode)
            Alias.new(node.new_name.unescaped.to_sym, node.old_name.unescaped.to_sym, line)
          else
            AliasValue.new(expr(node.new_name), expr(node.old_name), line)
          end
        when Prism::AliasGlobalVariableNode
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
        when Prism::CaseNode
          covers = branch_covers(:case, span(node.location), case_sides(node, :when))
          clauses = node.conditions.map.with_index do |w, i|
            values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? splat(c, line) : expr(c) }
            [values, covered(covers[i], w.statements ? seq(w.statements, taken: taken) : Literal.new(nil, line), line)]
          end
          other = node.else_clause && expr(node.else_clause, taken: taken)
          Case.new(node.predicate && expr(node.predicate), clauses, covered(covers.last, other, line), line)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode
          unsupported(node, "a block in an index target") if node.block
          args = index_args(node, line)
          op = case node
               when Prism::IndexOperatorWriteNode then node.binary_operator
               when Prism::IndexOrWriteNode then :or
               else :and
               end
          IndexOpAssign.new(expr(node.receiver), args, op, expr(node.value), line)
        when Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode
          op = case node
               when Prism::CallOperatorWriteNode then node.binary_operator
               when Prism::CallOrWriteNode then :or
               else :and
               end
          AttrOpAssign.new(expr(node.receiver), node.read_name, op, expr(node.value), line, node.call_operator == "&.")
        when Prism::ForNode then for_loop(node)
        when Prism::PostExecutionNode
          # `END { }` shares the enclosing scope, so its body is one block
          # deeper, as an at_exit block.
          body = deepen(node.statements ? seq(node.statements) : Literal.new(nil, line), 0)
          block = Block.new(Params.new([], [], nil, [], [], nil, nil), [], body, line)
          # It registers once for its site, however many times the site runs.
          Once.new(Send.of(Core.new(:Kernel, line), :at_exit, [], line, block: block), line)
        when Prism::PreExecutionNode
          unsupported(node, "BEGIN { } outside the toplevel") unless @block_depth.zero?
          node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::InstanceVariableWriteNode then IvarWrite.new(node.name, expr(node.value), line)
        when Prism::InstanceVariableOperatorWriteNode
          IvarWrite.new(node.name, Send.new(IvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::InstanceVariableOrWriteNode
          Or.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::InstanceVariableAndWriteNode
          And.new(IvarRead.new(node.name, line), IvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::BeginNode then protected_region(node, taken)
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
      def protected_region(node, taken = true)
        line = node.location.start_line
        body = guarded(node.rescue_clause) { node.statements ? seq(node.statements, taken: taken) : Literal.new(nil, line) }
        return body if node.rescue_clause.nil? && node.ensure_clause.nil?

        rescues = []
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
      def guarded(clause)
        rescues = false
        while clause
          rescues ||= clause.exceptions.any? { |e| e.is_a?(Prism::ConstantReadNode) && LOAD_RESCUES.include?(e.name) }
          clause = clause.subsequent
        end
        @guarded = (@guarded || 0) + 1 if rescues
        yield
      ensure
        @guarded -= 1 if rescues
      end

      def rescue_clause(node)
        line = node.location.start_line
        classes = node.exceptions.map { |e| e.is_a?(Prism::SplatNode) ? splat(e, line) : expr(e) }
        Rescue.new(classes, node.reference && target(node.reference), node.statements ? seq(node.statements) : Literal.new(nil, line), line)
      end

      # The value of `return`, `break` and `next`: none is nil, one value
      # is itself, and several are an Array.
      def jump_value(arguments, line)
        args = arguments&.arguments || []
        return Literal.new(nil, line) if args.empty?

        elements = args.map { |a| a.is_a?(Prism::SplatNode) ? splat(a, line) : expr(a) }
        return elements.first if elements.size == 1 && !elements.first.is_a?(Splat)

        ArrayLit.new(elements, line)
      end

      # `[scope, name]` of a constant path: nil for a bare name, :top for
      # `::Name`, else the expression before the last `::`.
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
      def constant_scope(node, line)
        scope, name = constant_path(node)
        return [scope, name, nil] if scope.nil? || scope == :top || constant_only?(scope)

        slot = temp(:scope)
        [read(slot, line), name, set(slot, scope, line)]
      end

      def with_scope(prelude, node, line)
        prelude ? Seq.new([prelude, node], line) : node
      end

      def constant_only?(scope)
        scope.is_a?(ConstRead) && (scope.scope.nil? || scope.scope == :top || constant_only?(scope.scope))
      end

      def define(node)
        @loader.loads_by_def!(node)
        marks = @body_marks
        receiver = node.receiver && expr(node.receiver)
        in_definee(nil, !receiver.nil?) do
          was = @in_def
          @in_def = true
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

      # The body with the `Primitive.attr!` calls of `marks` first, where
      # a def's own attributes are.
      def marked(body, marks, line)
        return Begin.new(*body.to_a).tap { |b| b.body = marked(body.body, marks, line) } if body.is_a?(Begin)

        rows = marks.map { |mark| Send.new(ConstRead.new(nil, :Primitive, line), :attr!, [Literal.new(mark, line)], line, false) }
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
      def evals?(node, sclass = false)
        return false if node.nil? || node.is_a?(Prism::DefNode)
        return true if node.is_a?(Prism::CallNode) && eval_call?(node)
        return true if sclass && node.is_a?(Prism::ReturnNode)

        sclass ||= node.is_a?(Prism::SingletonClassNode)
        node.child_nodes.any? { |child| evals?(child, sclass) }
      end

      # `Build.eval_call?` for a prism call, whose arguments are still
      # nodes. A leading Symbol literal is the method name that a send
      # calls or a fetch returns.
      def eval_call?(node)
        args = node.arguments&.arguments || []
        named = args.first.unescaped.to_sym if args.first.is_a?(Prism::SymbolNode)
        Build.eval_call?(node.name, named: named, argc: args.size)
      end

      # Runs a body with its definee: one step down the lexical path, and
      # whether it is the singleton side. A `using` in a body applies to
      # the rest of that body and to nothing outside it.
      def in_definee(name, singleton)
        @path.push(name) if name
        was = @singleton
        using = @using
        marks = @body_marks
        @singleton = singleton
        @body_marks = []
        yield
      ensure
        @path.pop if name
        @singleton = was
        @using = using
        @body_marks = marks
      end

      # A bare `super`: passes the method's parameters with their current
      # values, as a `Super` with the locals of the enclosing def.
      def zsuper(node, line)
        p = @def_params or return ZSuper.new(node.block && block(node.block), line)

        local = lambda do |name|
          name = name.whole if name.is_a?(MultiTarget)
          Local.new(name, @block_depth + (@def_depths ? @def_depths.fetch(name) : 0), line)
        end
        positional = (p.required + p.optional.map(&:first)).map(&local)
        positional << Splat.new(local.call(p.rest), line) if p.rest && p.rest != :implicit
        positional += p.post.map(&local)
        # The rest goes in first, in the order that ruby's own zsuper
        # builds the hash.
        pairs = p.kwrest && p.kwrest != :nokey ? [HashSplat.new(local.call(p.kwrest), line), nil] : []
        pairs += p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        kwargs = pairs.empty? ? nil : HashLit.new(pairs, line)
        block = node.block ? block(node.block) : (p.block && BlockPass.new(local.call(p.block), line))
        Super.new(positional, kwargs, block, line, @block_depth.positive?)
      end

      # A ParametersNode as one Params.
      def parameters(node)
        return Params.new([], [], nil, [], [], nil, nil) if node.nil?

        required = node.requireds.map { |p| name_of(p) }
        optional = node.optionals.map { |p| [p.name, expr(p.value)] }
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
      def name_of(param)
        return param.name unless param.is_a?(Prism::MultiTargetNode)

        target = multi_target(param)
        target.whole = temp(:arg)
        target
      end

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
      def target(node)
        line = node.location.start_line
        case node
        when Prism::LocalVariableTargetNode, Prism::RequiredParameterNode then Assign.new(node.name, node.respond_to?(:depth) ? node.depth : 0, nil, line)
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
      def index_args(node, line)
        (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? splat(a, line) : expr(a) }
      end

      # A rest parameter's name. `|a, |` has an implicit rest that binds
      # nothing.
      def rest_name(node)
        case node
        when Prism::ImplicitRestNode then :implicit
        when Prism::RestParameterNode then node.name || ANONYMOUS[:rest]
        when Prism::KeywordRestParameterNode then node.name || ANONYMOUS[:kwrest]
        when Prism::ForwardingParameterNode then ANONYMOUS[:kwrest]
        when Prism::NoKeywordsParameterNode then :nokey
        else unsupported(node)
        end
      end

      # A block literal, or the `&value` a call passes on.
      def block(node)
        line = node.location.start_line
        return BlockPass.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:block], @block_depth, line), line) if node.is_a?(Prism::BlockArgumentNode)

        in_block do
          params, extra = block_params(node.parameters)
          body = node.body ? expr(node.body) : Literal.new(nil, line)
          noted(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line,
                          node.location.end_line, method_cover(node)), node)
        end
      end

      # A block's Params and the locals prism leaves implicit: `it`, or
      # the numbered parameters.
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
      def shadowed?(name) = @shadowed.key?([@path.join("::"), @singleton, name])

      def call(node)
        mark = body_mark(node)
        @body_marks |= [mark] if mark
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil? && node.call_operator != "&."
        return FrozenString.new(unescaped(node.receiver), node.location.start_line) if node.name == :freeze && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil? && node.block.nil?
        # The core's `+"text"` under its frozen_string_literal comment: a
        # new String, as its C makes, with no send of +@.
        return Literal.new(unescaped(node.receiver), node.location.start_line, false) if node.name == :+@ && node.receiver.is_a?(Prism::StringNode) && node.block.nil? && Build.runtime_file?(@file)
        return require_node(node) if REQUIRES.include?(node.name) && node.receiver.nil? && node.block.nil? && !shadowed?(node.name) && !@loader&.eval? && literal_feature(node)
        return autoload_node(node) if node.name == :autoload && node.block.nil? && literal_autoload?(node)
        return newarray_send(node) if newarray_send?(node)

        send = plain_call(node)
        relative_in_file(node, send)
      end

      # compile.c's opt_newarray_send: `[a, b].min` or `.max` on a literal
      # that is not static and has no splat runs without Array#min, which
      # compares in the other order. The core's own files keep the send.
      def newarray_send?(node)
        %i[min max].include?(node.name) && node.receiver.is_a?(Prism::ArrayNode) && !node.receiver.static_literal? &&
          node.receiver.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) } &&
          node.arguments.nil? && node.block.nil? && node.call_operator != "&." && !Build.runtime_file?(@file)
      end

      # The program itself sends the method when it is redefined, so the
      # send sees what the program sees.
      def newarray_send(node)
        line = node.location.start_line
        items = temp("items")
        optimized = send_to(core(:Array, line), :newarray_optimized?, [Literal.new(node.name, line)], line)
        fast = send_to(core(:Array, line), :"newarray_#{node.name}", [read(items, line)], line)
        Seq.new([set(items, expr(node.receiver), line), If.new(optimized, fast, send_to(read(items, line), node.name, [], line), line)], line)
      end

      # A file of the program uses rubygems' API. rubygems' own files and
      # the runtime's files do not count.
      def gems!(name)
        @loader.gems!(name) if @loader && !@loader.ahead?(@file) && !Build.runtime_file?(@file)
      end

      # `Primitive.attr! :ruby`, `:hidden`, `:ivars` or `:sends_each` in a
      # class body of the core library: every later def in that body gets
      # the attribute, as if each def started with it. `:ruby` marks
      # methods that CRuby writes in Ruby. `:hidden` marks a class of
      # helpers that CRuby writes as a C struct. `:ivars` marks a class
      # whose instance variables CRuby shows. `:sends_each` marks methods
      # that send `each` by name, as CRuby's rb_block_call does.
      def body_mark(node)
        mark = node.arguments&.arguments&.first
        return unless !@in_def && node.name == :attr! && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Primitive &&
                      mark.is_a?(Prism::SymbolNode) && %w[ruby hidden ivars sends_each].include?(mark.unescaped)

        mark.unescaped.to_sym
      end

      # A string compiled at run time from a file with a location (loaded
      # by `load`, or given a file by an eval) keeps its literal
      # require_relative as a send. The name that it passes is made from
      # that file's directory, which the runtime's frame cannot know.
      def relative_in_file(node, send)
        return send unless @loader&.eval? && node.name == :require_relative && node.receiver.nil? && File.absolute_path?(@file)

        feature = literal_feature(node)
        return send unless feature

        send.args = [Literal.new(File.expand_path(feature, File.dirname(@file)), send.line)]
        send
      end

      # A call as a plain Send, with none of the special forms above.
      # `defined?` uses it, because it never runs the call. `compiles` is
      # false for a require of a literal name that no root contains. The
      # call searches at run time, and finds a file that was not compiled
      # in only if the program changed $LOAD_PATH. That change already
      # links in the compiler.
      def plain_call(node, compiles: true)
        args, kwargs, forwarded = arguments(node.arguments)
        kernel = compiles && (node.receiver.nil? || (node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Kernel))
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
        blk = node.block ? in_refine(node.name) { block(node.block) } : forwarded
        safe = node.call_operator == "&."
        # Both branches of a safe call have the call's location, as CRuby
        # records. `branch_covers` returns nils if nothing is measured, and
        # then the Send has no covers.
        covers = safe ? branch_covers(:"&.", span(node.location), [[:then, span(node.location)], [:else, span(node.location)]]) : nil
        Send.new(recv, node.name, args, message_line(node), node.variable_call?, opt,
                 blk, kwargs, safe, node.attribute_write?, nil, covers&.first && covers)
      end

      def in_refine(name)
        return yield unless name == :refine

        was = @using
        @using = :owner
        begin
          yield
        ensure
          @using = was
        end
      end

      # A call's line is its name's line, which can differ from the
      # receiver's if the receiver has several lines.
      def message_line(node) = node.message_loc&.start_line || node.location.start_line

      # The globals that ruby always has. Their `defined?` is
      # "global-variable" whether they have a value or not (CRuby's hooked
      # variables).
      SPECIAL_GVARS = %i[$! $@ $~ $_ $; $, $/ $\\ $0 $* $$ $? $: $" $< $> $. $stdin $stdout $stderr
                         $VERBOSE $DEBUG $FILENAME $LOAD_PATH $LOADED_FEATURES $PROGRAM_NAME].freeze

      # `defined?(value)`, as CRuby's defined_expr0: the result of each
      # form. The form decides at compile time. Only an ivar, gvar, cvar,
      # constant, method, yield or super is tested at run time.
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
        # An Array or Hash literal is defined if every part is defined.
        when Prism::ArrayNode
          node.elements.any?(Prism::SplatNode) ? Defined.new(:expression, nil, line) : Defined.new(:list, node.elements.map { |e| expr(e) }, line)
        when Prism::HashNode then Defined.new(:list, [HashLit.new(hash_pairs(node.elements), line)], line)
        # `(x)` tests `x`, and `()` or an empty `begin` is nil.
        when Prism::ParenthesesNode
          return Defined.new(:nil, nil, line) if node.body.nil?

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
      def assignment?(node) = node.class.name.end_with?("WriteNode") && !node.is_a?(Prism::MatchWriteNode)

      # `for x in list; body; end` is `list.each { |x| body }` with the
      # body in the enclosing scope: its locals move one scope out.
      def for_loop(node)
        line = node.location.start_line
        target = deepen(target(node.index), 0)
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
        block = Block.new(params, [:"*for"], Seq.new([bind, body], line), line)
        Send.of(expr(node.collection), :each, [], line, block: block)
      end

      # `node` as read from one block scope deeper: every local at
      # `level` or more is one scope further out.
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
      def arguments(node)
        kwargs = nil
        block = nil
        args = (node&.arguments || []).filter_map do |a|
          line = a.location.start_line
          case a
          when Prism::SplatNode then splat(a, line)
          when Prism::KeywordHashNode
            kwargs = HashLit.new(hash_pairs(a.elements), line)
            nil
          when Prism::ForwardingArgumentsNode
            kwargs = HashLit.new([HashSplat.new(Local.new(ANONYMOUS[:kwrest], @block_depth, line), line), nil], line)
            block = BlockPass.new(Local.new(ANONYMOUS[:block], @block_depth, line), line)
            Splat.new(Local.new(ANONYMOUS[:rest], @block_depth, line), line)
          else expr(a)
          end
        end
        [args, kwargs, block]
      end

      # A string literal as prism flags it: frozen if the file's magic
      # comment says so (as CRuby reads the comment), and then the one
      # frozen String of its text, as CRuby interns it.
      def literal_string(node, text, line) = node.frozen? ? frozen_literal_string(text, line) : Literal.new(text, line, !node.mutable?)

      # A literal that a frozen_string_literal comment freezes: the one
      # frozen String of its text, with no send of `freeze` (ruby never
      # sends it for this case).
      def frozen_literal_string(text, line) = FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)

      # Whether prism found a string static (`"a" "b"`, a heredoc with no
      # interpolation). `static_text` joins its parts.
      def static_string?(node)
        node.parts.all? { |part| part.is_a?(Prism::StringNode) || (part.is_a?(Prism::InterpolatedStringNode) && static_string?(part)) }
      end

      def static_text(node) = node.parts.map { |part| part.is_a?(Prism::StringNode) ? unescaped(part) : static_text(part) }.join

      # A string part's text with ruby's encoding: a \u escape makes it
      # UTF-8, and a non-ASCII \x escape in a US-ASCII file makes it
      # binary, whatever the file's encoding. Prism flags both, but gives
      # the text in the file's encoding.
      def unescaped(node)
        text = node.unescaped
        if node.forced_utf8_encoding? then text.dup.force_encoding(Encoding::UTF_8)
        elsif node.forced_binary_encoding? then text.dup.force_encoding(Encoding::BINARY)
        else text
        end
      end

      # An element of an array literal. `[1, a: 2]` contains a Hash.
      # Keywords that are only `**` splats add it only if it is not empty.
      def array_element(node, line)
        case node
        when Prism::SplatNode then splat(node, line)
        when Prism::KeywordHashNode
          hash = HashLit.new(hash_pairs(node.elements), line)
          node.elements.all?(Prism::AssocSplatNode) ? Splat.new(KwSplatElement.new(hash, line), line) : hash
        else expr(node)
        end
      end

      # `*value`, or a bare `*`: the anonymous rest parameter that the
      # method forwards, anywhere a splat can be.
      def splat(node, line)
        Splat.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:rest], @block_depth, line), line)
      end

      # A hash's elements as a flat pair list; a `**value` is a HashSplat
      # key with a nil value.
      def hash_pairs(elements)
        elements.flat_map do |e|
          case e
          when Prism::AssocNode
            [expr(e.key), expr(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value)]
          when Prism::AssocSplatNode
            [HashSplat.new(e.value ? expr(e.value) : Local.new(ANONYMOUS[:kwrest], @block_depth, e.location.start_line), e.location.start_line), nil]
          end
        end
      end

      # The bodies that a file always runs when it loads: its own
      # statements, a class or a module body, and a `begin` for grouping.
      # A branch, a loop, a block and a method body are not included.
      def self.always_run(node)
        case node
        when Prism::ProgramNode, Prism::BeginNode then [node.statements]
        when Prism::StatementsNode then node.body
        when Prism::ModuleNode, Prism::ClassNode, Prism::SingletonClassNode then [node.body]
        end
      end

      # Every `alias $x $&` the file always runs, by identity.
      def self.certain_aliases(node, out = {}.compare_by_identity)
        (always_run(node) || []).compact.each do |child|
          out[child] = true if child.is_a?(Prism::AliasGlobalVariableNode)
          certain_aliases(child, out)
        end
        out
      end

      # Whether this file always runs `node`. The walk occurs at the first
      # call, which for almost every file never occurs.
      def certain_alias?(node)
        return true unless @root

        (@certain ||= Build.certain_aliases(@root)).key?(node)
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end

      # A form of Ruby that zr does not support yet, at the node's line and
      # column. `form` is in user words (Refused.form_of).
      def unsupported(node, form = Refused.form_of(node))
        raise Refused.unsupported(form, file: @file, line: node.location.start_line, column: node.location.start_column + 1)
      end

      # A refusal of a form that ruby also refuses. A program that compiles
      # it at run time gets the SyntaxError that ruby raises.
      def invalid(node, message)
        raise Invalid, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end

    # The runtime files whose instance variables a program sees as in
    # ruby: prism's port, which changes the prism gem's nodes after they
    # are built, and openssl's port (its C creates each visible instance
    # variable by name and keeps the rest in hidden slots).
    VISIBLE_IVARS = [
      *%w[mutation ast].map { |name| File.join(Build::EXT, "prism/ruby/#{name}.rb") },
      File.join(Build::EXT, "openssl.so.rb"), *Dir[File.join(Build::EXT, "openssl/ossl/*.rb")].sort
    ].freeze
  end
end

# The rest of `Build`, by topic. They load after the class body, because
# they read its constants (`EXT`, `Build.pure`) when they load.
require_relative "preludes"
require_relative "loader"
require_relative "build/literals"
require_relative "build/coverage"
require_relative "build/requires"
