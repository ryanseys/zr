# frozen_string_literal: true

require "prism"
require_relative "node"

module Ze0
  module Hir
    class Refused < StandardError; end

    # Prism to HIR. A form the HIR does not hold yet is refused by name at
    # its line: the contract is CRuby-identical or refused, never a guess.
    class Build
      # Ruby's own pure-ruby stdlib, unedited.
      VENDOR = File.expand_path("../../../vendor/lib", __dir__)

      # The extensions whose native half is ours. A file here is part of
      # the runtime, so it may name a kernel def through `Primitive`.
      EXT = File.expand_path("../../../rt/ext", __dir__)

      # The ruby half of an extension, as its gem ships it. A gem is on
      # the path only once its native half answers, so a require of one
      # we do not carry stops by name instead of failing halfway in.
      GEMS = %w[prism].map { |name| File.expand_path("../../../vendor/ext/#{name}/lib", __dir__) }.freeze

      STDLIB = [VENDOR, EXT, *GEMS].freeze

      # The compiler itself, which a program that evals carries.
      EVAL_ROAD = File.expand_path("../eval.rb", __dir__)

      # `road` is false for an eval: the program it runs inside already
      # carries the compiler, so the eval must not compile it again.
      def self.program(source, file, roots: [], road: true)
        loader = Loader.new(roots + STDLIB)
        main = loader.unit(file, source)
        body = road && loader.evals? ? Seq.new([eval_road(loader), main.body], 0) : main.body
        Program.new(main.file, main.locals, body, main.frozen, loader.units, main.warnings)
      end

      # A require of the eval road, ahead of everything the program does.
      # Only a program that names an eval carries the compiler, so an
      # eval-free one links nothing extra.
      def self.eval_road(loader)
        Require.new(:require, "ze0/eval", EVAL_ROAD, loader.add(EVAL_ROAD), 0)
      end

      # The files a program reaches through require, require_relative
      # and load, each parsed and built once. A require searches the
      # roots: the -I roots, and the directories a file adds to
      # $LOAD_PATH with a literal (`$LOAD_PATH.unshift(File.expand_path
      # ("lib", __dir__))` and the like), read before the file's body.
      class Loader
        attr_reader :units

        def initialize(roots)
          @roots = roots.map { |r| File.expand_path(r) }
          @units = []
          @index = {}
          @evals = false
        end

        # A program that names one of these compiles ruby while it runs.
        # The block forms do not: only a string argument needs a compiler.
        EVAL_FORMS = %i[class_eval module_eval instance_eval].freeze

        def evals? = @evals

        def evals!(name, args)
          @evals = true if name == :eval || (EVAL_FORMS.include?(name) && !args.empty?)
        end

        def unit(file, source = File.read(file))
          result = Prism.parse(source, filepath: file)
          unless result.errors.empty?
            e = result.errors.first
            raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
          end

          @roots.concat(load_path_roots(result.value, file))
          frozen = result.magic_comments.any? { |c| c.key == "frozen_string_literal" && c.value == "true" }
          build = Build.new(file, self, result.encoding)
          body = build.seq(result.value.statements, hoist: true)
          Unit.new(file, result.value.locals + build.temps, body, frozen, warnings(result, file),
                   file.start_with?("#{EXT}/"))
        end

        # Ruby's parse-time warnings for the file, `key :k is duplicated
        # and overwritten on line 24` and friends, as ruby prints them.
        # prism knows the rules and the line each one names; `-w` tier
        # warnings are not printed by a plain run.
        def warnings(result, file)
          result.warnings.filter_map do |w|
            next unless w.level == :default

            "#{file}:#{w.location.start_line}: warning: #{w.message}"
          end
        end

        # The index of `path`'s unit, built on first sight. The row is
        # claimed before the file is read, so two files that require each
        # other end where ruby ends them: the second require answers
        # false and the first one finishes.
        def add(path)
          return @index[path] if @index.key?(path)

          i = @units.size
          @index[path] = i
          @units << nil
          @units[i] = unit(path)
          i
        end

        # A unit that stops by name when it runs, which is what an
        # autoload of a feature this runtime has no file for becomes:
        # the row is real, and reading the constant is what stops.
        def stop_unit(what, line)
          i = @units.size
          @units << Unit.new(what, [], Stop.new(what, line), false, [], false)
          i
        end

        # The file `feature` names from `from`, or nil.
        def resolve(kind, feature, from)
          if kind == :require_relative
            candidate(File.expand_path(feature, File.dirname(from)))
          elsif feature.start_with?("/", "./", "../", "~")
            # A name against the working directory, which the program can
            # change; the file that names it is the second place to look.
            candidate(File.expand_path(feature)) || candidate(File.expand_path(feature, File.dirname(from)))
          else
            @roots.each do |root|
              found = candidate(File.join(root, feature))
              return found if found
            end
            nil
          end
        end

        def candidate(path)
          return path if path.end_with?(".rb") && File.file?(path)

          File.file?("#{path}.rb") ? "#{path}.rb" : nil
        end

        def load_path_roots(node, file)
          roots = []
          walk = lambda do |n|
            if n.is_a?(Prism::CallNode) && n.receiver.is_a?(Prism::GlobalVariableReadNode) && %i[$LOAD_PATH $:].include?(n.receiver.name) &&
               %i[unshift push <<].include?(n.name) && n.arguments
              n.arguments.arguments.each { |a| (r = literal_path(a, file)) && roots << r }
            end
            n.compact_child_nodes.each { |c| walk.call(c) }
          end
          walk.call(node)
          roots
        end

        # A path a literal names, absolute: a String, `File.expand_path(str,
        # __dir__)` or `File.join(__dir__, str...)`; nil for anything else.
        def literal_path(node, file)
          dir = File.dirname(file)
          case node
          when Prism::StringNode then File.expand_path(node.unescaped)
          when Prism::InterpolatedStringNode
            parts = node.parts
            return nil unless parts.size == 2 && parts[0].is_a?(Prism::EmbeddedStatementsNode) && parts[0].statements&.body&.size == 1 &&
                              dir_call?(parts[0].statements.body[0]) && parts[1].is_a?(Prism::StringNode)

            File.expand_path(dir + parts[1].unescaped)
          when Prism::CallNode
            return nil unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :File && node.arguments

            args = node.arguments.arguments
            if node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && dir_call?(args[1])
              File.expand_path(args[0].unescaped, dir)
            elsif node.name == :join && dir_call?(args[0]) && args[1..].all?(Prism::StringNode)
              File.join(dir, *args[1..].map(&:unescaped))
            end
          end
        end

        def dir_call?(node)
          node.is_a?(Prism::CallNode) && node.name == :__dir__ && node.receiver.nil? && node.arguments.nil?
        end
      end

      def initialize(file, loader = nil, encoding = ::Encoding::UTF_8)
        @file = file
        @loader = loader
        @encoding = encoding
        @block_depth = 0
        @temps = [[]]
        @scopes = [@temps.first]
      end

      # The hidden locals the toplevel scope needs.
      def temps = @temps.first

      # The names of the anonymous parameters `*`, `**`, `&` and `...`,
      # as locals of the def that declares them.
      ANONYMOUS = { rest: :*, kwrest: :**, block: :& }.freeze

      # `body` lowered one block scope deeper.
      def in_block
        @block_depth += 1
        @temps.push([])
        yield
      ensure
        @block_depth -= 1
        @temps.pop
      end

      # `body` lowered in a fresh scope: a def or a class body.
      def in_scope
        was = [@block_depth, @def_params]
        @block_depth = 0
        @def_params = nil
        @temps.push([])
        @scopes.push(@temps.last)
        yield
      ensure
        @block_depth, @def_params = was
        @temps.pop
        @scopes.pop
      end

      # A scope's locals: the parser's, then the hidden ones its body made.
      def with_temps(locals) = locals + @temps.last

      GVAR_ALIASES = { :$PROGRAM_NAME => :$0, :$: => :$LOAD_PATH, :$" => :$LOADED_FEATURES, :$> => :$stdout }.freeze

      # `$PROGRAM_NAME`, `$:` and `$"` are the other names of `$0`,
      # `$LOAD_PATH` and `$LOADED_FEATURES`.
      def gvar_name(name)
        GVAR_ALIASES.fetch(name, name)
      end

      # `$&`, `` $` ``, `$'` and `$+`: what the last match answers, nil
      # without one.
      def back_reference(node, line)
        match = GvarRead.new(:$~, line)
        case node.name
        when :$& then Send.new(match, :[], [Literal.new(0, line)], line, false, nil, nil, nil, true)
        when :$` then Send.new(match, :pre_match, [], line, false, nil, nil, nil, true)
        when :$' then Send.new(match, :post_match, [], line, false, nil, nil, nil, true)
        when :$+ then Send.new(match, :last_group, [], line, false, nil, nil, nil, true)
        else refuse(node, "#{node.name} is not lowered yet")
        end
      end

      # `a..b` in a condition is a flip-flop: it answers true from the run
      # where the left side is true to the run where the right side is. The
      # state is a hidden local of the enclosing def, so a block shares the
      # state of the method it hangs in, which is where ruby keeps it too.
      def flip_flop(node, line)
        state = flip_flop_state
        depth = @block_depth
        ends = -> { If.new(end_test(node.right, line), Assign.new(state, depth, Literal.new(false, line), line), nil, line) }
        # `...` waits for the next run before it can turn off; `..` asks the
        # right side at once, so a one-run range ends where it started.
        started = [Assign.new(state, depth, Literal.new(true, line), line)]
        started << ends.call unless node.exclude_end?
        started << Literal.new(true, line)
        If.new(Local.new(state, depth, line),
               Seq.new([ends.call, Literal.new(true, line)], line),
               If.new(end_test(node.left, line), Seq.new(started, line), Literal.new(false, line), line),
               line)
      end

      # An end of a flip-flop. A missing one never fires.
      def end_test(node, line) = node ? expr(node) : Literal.new(nil, line)

      def flip_flop_state
        @flip_flops = (@flip_flops || 0) + 1
        name = :"%flip_flop#{@flip_flops}"
        @scopes.last << name
        name
      end

      # `# shareable_constant_value:` over a constant write. A value the
      # compiler can see is a literal is deep-frozen; any other value must
      # already be shareable, which is ruby's own split.
      def shareable_constant(node, line)
        write = expr(node.write)
        ractor = ConstRead.new(nil, :Ractor, line)
        write.value =
          if node.literal? && !shareable_literal?(node.write.value)
            Send.new(ractor, :ensure_shareable, [write.value, Literal.new(constant_written(node.write), line)], line, false)
          elsif node.experimental_copy?
            Send.new(ractor, :make_shareable, [write.value], line, false, nil, nil, HashLit.new([Literal.new(:copy, line), Literal.new(true, line)], line))
          else
            Send.new(ractor, :make_shareable, [write.value], line, false)
          end
        write
      end

      # The name a shareable constant write names, for the error.
      def constant_written(write)
        write.respond_to?(:name) ? write.name.to_s : write.target.name.to_s
      end

      # Whether a value is built only of literals, so freezing it can hurt
      # nothing that the program still holds.
      def shareable_literal?(node)
        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
             Prism::SymbolNode, Prism::StringNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
             Prism::RegularExpressionNode, Prism::SourceFileNode, Prism::SourceLineNode, Prism::SourceEncodingNode
          true
        when Prism::ArrayNode then node.elements.all? { |e| shareable_literal?(e) }
        when Prism::HashNode
          node.elements.all? { |e| e.is_a?(Prism::AssocNode) && shareable_literal?(e.key) && shareable_literal?(e.value) }
        when Prism::RangeNode
          (node.left.nil? || shareable_literal?(node.left)) && (node.right.nil? || shareable_literal?(node.right))
        else false
        end
      end

      # A regexp literal's option bits, as Regexp.new takes them.
      # `i`, `x` and `m`, then the two encoding bits: `n` declares the
      # pattern encoding-agnostic, and `e`, `s` and `u` pin it to one.
      def regexp_options(node)
        (node.ignore_case? ? 1 : 0) | (node.extended? ? 2 : 0) | (node.multi_line? ? 4 : 0) |
          (regexp_encoding(node) ? 16 : 0) | (node.ascii_8bit? ? 32 : 0)
      end

      # The encoding a flag letter pins the pattern to, or nil.
      def regexp_encoding(node)
        if node.euc_jp? then ::Encoding::EUC_JP
        elsif node.windows_31j? then ::Encoding::Windows_31J
        elsif node.utf_8? then ::Encoding::UTF_8
        end
      end

      # ruby, the oracle, checks the pattern: one it refuses is a syntax
      # error here too.
      def interpolated_regexp(node, line)
        pinned = regexp_encoding(node)
        args = [interpolation(node, line), Literal.new(regexp_options(node), line),
                Literal.new(pinned && ::Encoding.list.index(pinned), line)]
        made = Send.new(ConstRead.new(nil, :Regexp, line), :interpolated, args, line, false)
        node.once? ? RegexpOnce.new(made, line) : made
      end

      def regexp_literal(node, line)
        begin
          Regexp.new(node.unescaped, regexp_options(node) & 7)
        rescue RegexpError => e
          refuse(node, "#{e.message.sub(/: \/.*\z/m, "")}: /#{node.unescaped}/")
        end
        RegexpLit.new(node.unescaped, regexp_options(node), regexp_encoding(node), line)
      end

      # The parts of an interpolated string, each a String or the value
      # of an embedded expression.
      def interpolation(node, line)
        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then Literal.new(part.unescaped, part.location.start_line)
          when Prism::EmbeddedStatementsNode then part.statements ? seq(part.statements) : Literal.new(nil, line)
          when Prism::EmbeddedVariableNode then expr(part.variable)
          when Prism::InterpolatedStringNode then interpolation(part, line)
          else refuse(part, "#{part.class.name.split("::").last.delete_suffix("Node")} in a string is not lowered yet")
          end
        end
        Interp.new(parts, line)
      end

      # `hoist` puts the `BEGIN { }` blocks of a file first, in their
      # order, before anything else runs.
      def seq(node, hoist: false)
        return Seq.new([], 1) if node.nil?

        body = node.body
        body = body.partition { |s| s.is_a?(Prism::PreExecutionNode) }.flatten if hoist
        Seq.new(body.map { |s| expr(s) }, node.location.start_line)
      end

      def expr(node)
        line = node.location.start_line
        case node
        when Prism::StatementsNode then seq(node)
        when Prism::ParenthesesNode then node.body ? expr(node.body) : Literal.new(nil, line)
        when Prism::IntegerNode, Prism::FloatNode then Literal.new(node.value, line)
        when Prism::RationalNode then Send.new(nil, :Rational, [Literal.new(node.numerator, line), Literal.new(node.denominator, line)], line, false)
        when Prism::ImaginaryNode then Send.new(nil, :Complex, [Literal.new(0, line), expr(node.numeric)], line, false)
        when Prism::StringNode then Literal.new(node.unescaped, line)
        when Prism::SymbolNode then Literal.new(node.unescaped.to_sym, line)
        when Prism::NilNode then Literal.new(nil, line)
        when Prism::TrueNode then Literal.new(true, line)
        when Prism::FalseNode then Literal.new(false, line)
        when Prism::SelfNode then SelfRef.new(line)
        when Prism::CallNode then call(node)
        when Prism::DefNode then define(node)
        when Prism::LocalVariableReadNode then Local.new(node.name, node.depth, line)
        when Prism::LocalVariableWriteNode then Assign.new(node.name, node.depth, expr(node.value), line)
        when Prism::MultiWriteNode then MultiAssign.new(multi_target(node), expr(node.value), line)
        when Prism::LocalVariableOperatorWriteNode
          Assign.new(node.name, node.depth, Send.new(Local.new(node.name, node.depth, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LambdaNode
          in_block do
            params, extra = block_params(node.parameters)
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            Lambda.new(Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line), line)
          end
        when Prism::ItLocalVariableReadNode then Local.new(:it, 0, line)
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
          If.new(expr(node.predicate), node.statements && seq(node.statements), node.subsequent && expr(node.subsequent), line)
        when Prism::CaseMatchNode then case_match(node)
        when Prism::MatchRequiredNode then match_required(node)
        when Prism::MatchPredicateNode then match_predicate(node)
        when Prism::MatchWriteNode then match_write(node)
        when Prism::UnlessNode
          If.new(expr(node.predicate), node.else_clause && seq(node.else_clause.statements), node.statements && seq(node.statements), line)
        when Prism::ElseNode then node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::WhileNode
          While.new(expr(node.predicate), node.statements && seq(node.statements), line, node.begin_modifier?)
        when Prism::UntilNode
          While.new(Not.new(expr(node.predicate), line), node.statements && seq(node.statements), line, node.begin_modifier?)
        when Prism::ReturnNode then Return.new(jump_value(node.arguments, line), line)
        when Prism::AndNode then And.new(expr(node.left), expr(node.right), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right), line)
        when Prism::ClassNode
          scope, name = constant_path(node.constant_path)
          superclass = node.superclass && expr(node.superclass)
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            ClassDef.new(scope, name, superclass, with_temps(node.locals), body, line)
          end
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            ModuleDef.new(scope, name, with_temps(node.locals), body, line)
          end
        when Prism::SingletonClassNode
          target = expr(node.expression)
          in_scope do
            body = node.body ? expr(node.body) : Literal.new(nil, line)
            SingletonClassDef.new(target, with_temps(node.locals), body, line)
          end
        when Prism::ConstantReadNode then ConstRead.new(nil, node.name, line)
        when Prism::ConstantPathNode
          scope, name = constant_path(node)
          ConstRead.new(scope, name, line)
        when Prism::ConstantWriteNode then ConstWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathWriteNode
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when Prism::InterpolatedStringNode then interpolation(node, line)
        when Prism::SourceFileNode then Literal.new(@file, line)
        when Prism::SourceLineNode then Literal.new(line, line)
        when Prism::SourceEncodingNode
          Send.new(ConstRead.new(nil, :Encoding, line), :find, [Literal.new(@encoding.name, line)], line, false)
        when Prism::InterpolatedSymbolNode then Send.new(interpolation(node, line), :to_sym, [], line, false)
        when Prism::XStringNode then Send.new(nil, :`, [Literal.new(node.unescaped, line)], line, false)
        when Prism::NumberedReferenceReadNode then Send.new(GvarRead.new(:$~, line), :[], [Literal.new(node.number, line)], line, false, nil, nil, nil, true)
        when Prism::BackReferenceReadNode then back_reference(node, line)
        when Prism::RegularExpressionNode then regexp_literal(node, line)
        when Prism::InterpolatedRegularExpressionNode then interpolated_regexp(node, line)
        when Prism::MatchLastLineNode
          # A bare regexp as a condition matches `$_`.
          Send.new(regexp_literal(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedMatchLastLineNode
          Send.new(interpolated_regexp(node, line), :=~, [GvarRead.new(:$_, line)], line, false)
        when Prism::InterpolatedXStringNode then Send.new(nil, :`, [interpolation(node, line)], line, false)
        when Prism::ArrayNode
          ArrayLit.new(node.elements.map { |e| e.is_a?(Prism::SplatNode) ? Splat.new(expr(e.expression), line) : expr(e) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
        when Prism::FlipFlopNode then flip_flop(node, line)
        when Prism::ShareableConstantNode then shareable_constant(node, line)
        when Prism::RangeNode
          RangeLit.new(node.left ? expr(node.left) : Literal.new(nil, line), node.right ? expr(node.right) : Literal.new(nil, line), node.exclude_end?, line)
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::GlobalVariableReadNode
          node.name == :$@ ? Send.new(GvarRead.new(:$!, line), :backtrace, [], line, false, nil, nil, nil, true) : GvarRead.new(gvar_name(node.name), line)
        when Prism::GlobalVariableWriteNode then GvarWrite.new(gvar_name(node.name), expr(node.value), line)
        when Prism::GlobalVariableOperatorWriteNode
          GvarWrite.new(node.name, Send.new(GvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::GlobalVariableOrWriteNode then GvarWrite.new(node.name, Or.new(GvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::GlobalVariableAndWriteNode then GvarWrite.new(node.name, And.new(GvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::ClassVariableReadNode then CvarRead.new(node.name, line)
        when Prism::ClassVariableWriteNode then CvarWrite.new(node.name, expr(node.value), line)
        when Prism::ClassVariableOperatorWriteNode
          CvarWrite.new(node.name, Send.new(CvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::ClassVariableOrWriteNode
          If.new(Defined.new(:cvar, node.name, line), Or.new(CvarRead.new(node.name, line), CvarWrite.new(node.name, expr(node.value), line), line), CvarWrite.new(node.name, expr(node.value), line), line)
        when Prism::DefinedNode then defined(node.value, line)
        when Prism::ClassVariableAndWriteNode then CvarWrite.new(node.name, And.new(CvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::ConstantOrWriteNode then ConstOrWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathOrWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstOrWrite.new(scope, name, expr(node.value), line), line)
        when Prism::ConstantAndWriteNode
          ConstWrite.new(nil, node.name, And.new(ConstRead.new(nil, node.name, line), expr(node.value), line), line)
        when Prism::ConstantPathAndWriteNode
          scope, name, prelude = constant_scope(node.target, line)
          with_scope(prelude, ConstWrite.new(scope, name, And.new(ConstRead.new(scope, name, line), expr(node.value), line), line), line)
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
          # `$&` and its family live in the frame, not the global table,
          # so an alias of one has nothing to read.
          refuse(node, "an alias of #{node.old_name.name} is not lowered yet") unless node.old_name.is_a?(Prism::GlobalVariableReadNode)

          GvarAlias.new(node.new_name.name, node.old_name.name, line)
        when Prism::CaseNode
          clauses = node.conditions.map do |w|
            values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? Splat.new(expr(c.expression), line) : expr(c) }
            [values, w.statements ? seq(w.statements) : Literal.new(nil, line)]
          end
          Case.new(node.predicate && expr(node.predicate), clauses, node.else_clause && expr(node.else_clause), line)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode
          refuse(node, "a block in an index target is not lowered yet") if node.block
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
          # `END { }` shares the enclosing scope, so its body reads one
          # block deeper as an at_exit block.
          body = deepen(node.statements ? seq(node.statements) : Literal.new(nil, line), 0)
          block = Block.new(Params.new([], [], nil, [], [], nil, nil), [], body, line)
          Send.new(nil, :at_exit, [], line, false, false, block, nil, false)
        when Prism::PreExecutionNode
          refuse(node, "BEGIN { } outside the toplevel is not lowered yet") unless @block_depth.zero?
          node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::InstanceVariableWriteNode then IvarWrite.new(node.name, expr(node.value), line)
        when Prism::InstanceVariableOperatorWriteNode
          IvarWrite.new(node.name, Send.new(IvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::InstanceVariableOrWriteNode
          IvarWrite.new(node.name, Or.new(IvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::InstanceVariableAndWriteNode
          IvarWrite.new(node.name, And.new(IvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::BeginNode then protected_region(node)
        when Prism::RescueModifierNode
          clause = Rescue.new([], nil, expr(node.rescue_expression), line)
          Begin.new(expr(node.expression), [clause], nil, nil, line)
        when Prism::RetryNode then Retry.new(line)
        when Prism::RedoNode then Redo.new(line)
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # `begin ... end` with its clauses; a bare `begin ... end` is its body.
      def protected_region(node)
        line = node.location.start_line
        body = node.statements ? seq(node.statements) : Literal.new(nil, line)
        return body if node.rescue_clause.nil? && node.ensure_clause.nil?

        rescues = []
        clause = node.rescue_clause
        while clause
          rescues << rescue_clause(clause)
          clause = clause.subsequent
        end
        else_body = node.else_clause && (node.else_clause.statements ? seq(node.else_clause.statements) : Literal.new(nil, line))
        ensure_body = node.ensure_clause && (node.ensure_clause.statements ? seq(node.ensure_clause.statements) : Literal.new(nil, line))
        Begin.new(body, rescues, else_body, ensure_body, line)
      end

      def rescue_clause(node)
        line = node.location.start_line
        classes = node.exceptions.map { |e| e.is_a?(Prism::SplatNode) ? Splat.new(expr(e.expression), line) : expr(e) }
        Rescue.new(classes, node.reference && target(node.reference), node.statements ? seq(node.statements) : Literal.new(nil, line), line)
      end

      # What `return`, `break` and `next` carry: nothing is nil, one
      # value is itself, several are an Array.
      def jump_value(arguments, line)
        args = arguments&.arguments || []
        return Literal.new(nil, line) if args.empty?

        elements = args.map { |a| a.is_a?(Prism::SplatNode) ? Splat.new(expr(a.expression), line) : expr(a) }
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
        else refuse(node, "a dynamic constant path is not lowered yet")
        end
      end

      # The scope of a constant read and written by `A::B op= v`. A path
      # of constants reads the same twice; anything computed is held in a
      # hidden local, so the program sees it evaluated once.
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
        receiver = node.receiver && expr(node.receiver)
        in_scope do
          params = parameters(node.parameters)
          @def_params = params
          body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
          locals = with_temps(node.locals + (params.names - node.locals))
          Def.new(node.name, params, locals, body, node.location.start_line, receiver)
        end
      end

      # A bare `super`: the method's parameters passed on as they stand,
      # a `Super` with the locals of the def this block sits in.
      def zsuper(node, line)
        p = @def_params or return ZSuper.new(node.block && block(node.block), line)

        local = ->(name) { Local.new(name.is_a?(MultiTarget) ? name.whole : name, @block_depth, line) }
        positional = (p.required + p.optional.map(&:first)).map(&local)
        positional << Splat.new(local.call(p.rest), line) if p.rest && p.rest != :implicit
        positional += p.post.map(&local)
        # The rest goes in first, which is the order ruby's own zsuper
        # builds the hash in.
        pairs = p.kwrest && p.kwrest != :nokey ? [HashSplat.new(local.call(p.kwrest), line), nil] : []
        pairs += p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        kwargs = pairs.empty? ? nil : HashLit.new(pairs, line)
        block = node.block ? block(node.block) : (p.block && BlockPass.new(local.call(p.block), line))
        Super.new(positional, kwargs, block, line)
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

      # A required parameter: its name, or a MultiTarget for `(a, b)`.
      # A bare super passes such an argument as it arrived, so the whole
      # of it is kept in a hidden local beside the names it takes apart.
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
               else refuse(node.rest, "#{node.rest.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
               end
        MultiTarget.new(node.lefts.map { |t| target(t) }, rest, node.rights.map { |t| target(t) }, line)
      end

      # One target of a multiple assignment.
      def target(node)
        line = node.location.start_line
        case node
        when Prism::LocalVariableTargetNode, Prism::RequiredParameterNode then Assign.new(node.name, node.respond_to?(:depth) ? node.depth : 0, nil, line)
        when Prism::InstanceVariableTargetNode then IvarWrite.new(node.name, nil, line)
        when Prism::GlobalVariableTargetNode then GvarWrite.new(node.name, nil, line)
        when Prism::ClassVariableTargetNode then CvarWrite.new(node.name, nil, line)
        when Prism::ConstantTargetNode then ConstWrite.new(nil, node.name, nil, line)
        when Prism::ConstantPathTargetNode
          scope, name = constant_path(node)
          ConstWrite.new(scope, name, nil, line)
        when Prism::MultiTargetNode then multi_target(node)
        when Prism::IndexTargetNode
          args = index_args(node, line)
          Send.new(expr(node.receiver), :[]=, args, line, false, args.none?(Splat), nil, nil)
        when Prism::CallTargetNode
          refuse(node, "a safe-navigation target is not lowered yet") if node.call_operator == "&."
          Send.new(expr(node.receiver), node.name, [], line, false, false, nil, nil)
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} as an assignment target is not lowered yet")
        end
      end

      # The indexes an index target names. A splat among them takes the
      # inline `[]` path away, since the count is only known at run time.
      def index_args(node, line)
        (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? Splat.new(expr(a.expression), line) : expr(a) }
      end

      # A rest parameter's name; `|a, |` has an implicit one that binds
      # nothing.
      def rest_name(node)
        case node
        when Prism::ImplicitRestNode then :implicit
        when Prism::RestParameterNode then node.name || ANONYMOUS[:rest]
        when Prism::KeywordRestParameterNode then node.name || ANONYMOUS[:kwrest]
        when Prism::ForwardingParameterNode then ANONYMOUS[:kwrest]
        when Prism::NoKeywordsParameterNode then :nokey
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # A block literal, or the `&value` a call passes on.
      def block(node)
        line = node.location.start_line
        return BlockPass.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:block], @block_depth, line), line) if node.is_a?(Prism::BlockArgumentNode)

        in_block do
          params, extra = block_params(node.parameters)
          body = node.body ? expr(node.body) : Literal.new(nil, line)
          Block.new(params, with_temps(node.locals + extra + (params.names - node.locals - extra)), body, line)
        end
      end

      # A block's Params and the locals prism leaves implicit: `it`, or
      # the numbered parameters.
      def block_params(node)
        none = Params.new([], [], nil, [], [], nil, nil)
        case node
        when nil then [none, []]
        when Prism::ItParametersNode then [Params.new([:it], [], nil, [], [], nil, nil), [:it]]
        when Prism::NumberedParametersNode
          names = (1..node.maximum).map { |i| :"_#{i}" }
          [Params.new(names, [], nil, [], [], nil, nil), []]
        when Prism::BlockParametersNode
          # A block-local (`|x; y|`) is already among the block's locals,
          # where prism resolves it at depth 0, fresh each call.
          [parameters(node.parameters), []]
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      REQUIRES = %i[require require_relative load].freeze

      def call(node)
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil?
        return FrozenString.new(node.receiver.unescaped, node.location.start_line) if node.name == :freeze && node.receiver.is_a?(Prism::StringNode) && node.arguments.nil? && node.block.nil?
        return require_node(node) if REQUIRES.include?(node.name) && node.receiver.nil? && node.block.nil? && literal_feature(node)
        return autoload_node(node) if node.name == :autoload && node.block.nil? && literal_autoload?(node)

        args, kwargs, forwarded = arguments(node.arguments)
        @loader.evals!(node.name, args)
        opt = (%i[[] []=].include?(node.name) && node.opening == "[") || (node.name == :<< && node.call_operator.nil? && args.size == 1)
        Send.new(node.receiver && expr(node.receiver), node.name, args, node.location.start_line, node.variable_call?, opt,
                 node.block ? block(node.block) : forwarded, kwargs, node.call_operator == "&.", node.attribute_write?)
      end

      # The name a require names at compile time: a String literal, or a
      # path built from `__dir__` with a literal.
      def literal_feature(node)
        args = node.arguments&.arguments
        return nil unless args&.size == 1

        args[0].is_a?(Prism::StringNode) ? args[0].unescaped : @loader.literal_path(args[0], @file)
      end

      # A require of a literal name resolves now: the file becomes a unit
      # of the program. A name ruby itself answers but no root here holds
      # stops by name; every other name raises LoadError when it runs, as
      # it does in ruby.
      # The features ruby loads before a program starts, so a require of
      # one answers false.
      PRELOADED = %w[set set.rb monitor monitor.rb].freeze

      def require_node(node)
        line = node.location.start_line
        feature = literal_feature(node)
        return Literal.new(false, line) if node.name == :require && PRELOADED.include?(feature)

        path = @loader.resolve(node.name, feature, @file)
        stop = path.nil? && node.name != :require_relative && stop_for(node, feature)
        return stop if stop

        Require.new(node.name, feature, path || missing_path(node.name, feature), path && @loader.add(path), line)
      end

      # A feature ruby carries, which this runtime has no file for. The
      # stop waits until the program runs the require: a guarded one that
      # the program never reaches costs it nothing.
      def stop_for(node, feature)
        return unless FEATURES.include?(feature.to_s.delete_suffix(".rb"))

        line = node.location.start_line
        Stop.new("#{@file}:#{line}: #{node.name} of #{feature.inspect}", line)
      end

      # What a LoadError names: a require_relative shows the whole path,
      # every other form the name the program wrote.
      def missing_path(kind, feature)
        kind == :require_relative ? File.expand_path(feature, File.dirname(@file)) : feature
      end

      def literal_autoload?(node)
        args = node.arguments&.arguments
        args&.size == 2 && args[0].is_a?(Prism::SymbolNode) && (args[1].is_a?(Prism::StringNode) || @loader.literal_path(args[1], @file))
      end

      # `autoload :Name, "feature"` resolves the feature as a require
      # would, so the file is a unit of the program.
      def autoload_node(node)
        line = node.location.start_line
        name_node, path_node = node.arguments.arguments
        feature = path_node.is_a?(Prism::StringNode) ? path_node.unescaped : @loader.literal_path(path_node, @file)
        path = @loader.resolve(:require, feature, @file)
        stop = path.nil? && stop_for(node, feature)
        unit = stop ? @loader.stop_unit(stop.what, line) : (path && @loader.add(path))
        Autoload.new(node.receiver && expr(node.receiver), name_node.unescaped.to_sym, feature, path || feature, unit, line)
      end

      # `defined?(value)`: the form decides at compile time; only an
      # ivar, gvar, cvar, constant, method, yield or super asks at run time.
      def defined(node, line)
        case node
        when Prism::LocalVariableReadNode then Defined.new(:local, node.name, line)
        when Prism::InstanceVariableReadNode then Defined.new(:ivar, node.name, line)
        when Prism::GlobalVariableReadNode then Defined.new(:gvar, node.name, line)
        when Prism::ClassVariableReadNode then Defined.new(:cvar, node.name, line)
        when Prism::ConstantReadNode, Prism::ConstantPathNode then Defined.new(:const, expr(node), line)
        when Prism::CallNode then Defined.new(:method, call(node), line)
        when Prism::YieldNode then Defined.new(:yield, nil, line)
        when Prism::SuperNode, Prism::ForwardingSuperNode then Defined.new(:super, nil, line)
        when Prism::SelfNode then Defined.new(:self, nil, line)
        when Prism::NilNode then Defined.new(:nil, nil, line)
        when Prism::TrueNode then Defined.new(:true, nil, line)
        when Prism::FalseNode then Defined.new(:false, nil, line)
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::GlobalVariableWriteNode, Prism::ClassVariableWriteNode,
             Prism::ConstantWriteNode, Prism::MultiWriteNode, Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode
          Defined.new(:assignment, nil, line)
        else Defined.new(:expression, nil, line)
        end
      end

      # `for x in list; body; end` is `list.each { |x| body }` with the
      # body in the enclosing scope: its locals move one scope out.
      def for_loop(node)
        line = node.location.start_line
        target = deepen(target(node.index), 0)
        body = node.statements ? deepen(seq(node.statements), 0) : Literal.new(nil, line)
        value = Local.new(:"*for", 0, line)
        if target.is_a?(MultiTarget)
          # `for a, b in o` takes every value yielded, as `|a, b|` does:
          # the block collects them, and one alone stands for itself.
          got = Local.new(:"*for", 0, line)
          one = Send.new(Send.new(got, :size, [], line, false, false, nil, nil, false, false), :==, [Literal.new(1, line)], line, false, false, nil, nil, false, false)
          first = Send.new(got, :[], [Literal.new(0, line)], line, false, false, nil, nil, false, false)
          bind = MultiAssign.new(target, If.new(one, first, got, line), line)
          params = Params.new([], [], :"*for", [], [], nil, nil)
        else
          bind = target.is_a?(Send) ? target.tap { |t| t.args << value } : target.tap { |t| t.value = value }
          params = Params.new([:"*for"], [], nil, [], [], nil, nil)
        end
        block = Block.new(params, [:"*for"], Seq.new([bind, body], line), line)
        Send.new(expr(node.collection), :each, [], line, false, false, block, nil, false)
      end

      # `node` as it reads one block scope deeper: every local that
      # reaches `level` or beyond is one further out.
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
          node.scope = deepen(node.scope, level) if node.scope.is_a?(Struct)
          node.superclass = deepen(node.superclass, level) if node.superclass
          node
        when ModuleDef
          node.scope = deepen(node.scope, level) if node.scope.is_a?(Struct)
          node
        when SingletonClassDef
          node.target = deepen(node.target, level)
          node
        when Struct
          node.each_pair { |k, v| node[k] = deepen(v, level) if v.is_a?(Struct) || v.is_a?(Array) }
          node
        when Array then node.map! { |v| v.is_a?(Struct) || v.is_a?(Array) ? deepen(v, level) : v }
        else node
        end
      end

      # `[args, kwargs, block]` of an argument list: Splats among the
      # args, the keywords as one HashLit or nil, and the block `...`
      # forwards, or nil.
      def arguments(node)
        kwargs = nil
        block = nil
        args = (node&.arguments || []).filter_map do |a|
          line = a.location.start_line
          case a
          when Prism::SplatNode then Splat.new(a.expression ? expr(a.expression) : Local.new(ANONYMOUS[:rest], @block_depth, line), line)
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

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end
  end
end
