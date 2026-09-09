# frozen_string_literal: true

require "prism"
require_relative "node"

module Ze0
  module Hir
    class Refused < StandardError; end

    # Prism to HIR. A form the HIR does not hold yet is refused by name at
    # its line: the contract is CRuby-identical or refused, never a guess.
    class Build
      def self.program(source, file)
        result = Prism.parse(source, filepath: file)
        unless result.errors.empty?
          e = result.errors.first
          raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
        end

        frozen = result.magic_comments.any? { |c| c.key == "frozen_string_literal" && c.value == "true" }
        Program.new(file, result.value.locals, new(file).seq(result.value.statements), frozen)
      end

      def initialize(file)
        @file = file
        @block_depth = 0
      end

      # The names of the anonymous parameters `*`, `**`, `&` and `...`,
      # as locals of the def that declares them.
      ANONYMOUS = { rest: :*, kwrest: :**, block: :& }.freeze

      # `body` lowered one block scope deeper.
      def in_block
        @block_depth += 1
        yield
      ensure
        @block_depth -= 1
      end

      # `body` lowered in a fresh scope: a def or a class body.
      def in_scope
        was = [@block_depth, @def_params]
        @block_depth = 0
        @def_params = nil
        yield
      ensure
        @block_depth, @def_params = was
      end

      # `$PROGRAM_NAME` is the other name of `$0`.
      def gvar_name(name)
        name == :$PROGRAM_NAME ? :$0 : name
      end

      # The parts of an interpolated string, each a String or the value
      # of an embedded expression.
      def interpolation(node, line)
        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then Literal.new(part.unescaped, part.location.start_line)
          when Prism::EmbeddedStatementsNode then part.statements ? seq(part.statements) : Literal.new(nil, line)
          else refuse(part, "#{part.class.name.split("::").last.delete_suffix("Node")} in a string is not lowered yet")
          end
        end
        Interp.new(parts, line)
      end

      def seq(node)
        return Seq.new([], 1) if node.nil?

        Seq.new(node.body.map { |s| expr(s) }, node.location.start_line)
      end

      def expr(node)
        line = node.location.start_line
        case node
        when Prism::StatementsNode then seq(node)
        when Prism::ParenthesesNode then node.body ? expr(node.body) : Literal.new(nil, line)
        when Prism::IntegerNode then Literal.new(node.value, line)
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
            Lambda.new(Block.new(params, node.locals + extra, node.body ? expr(node.body) : Literal.new(nil, line), line), line)
          end
        when Prism::ItLocalVariableReadNode then Local.new(:it, 0, line)
        when Prism::UndefNode
          names = node.names.map { |n| n.is_a?(Prism::SymbolNode) ? n.unescaped.to_sym : refuse(n, "an undef of a dynamic symbol is not lowered yet") }
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
        when Prism::UnlessNode
          If.new(expr(node.predicate), node.else_clause && seq(node.else_clause.statements), node.statements && seq(node.statements), line)
        when Prism::ElseNode then node.statements ? seq(node.statements) : Literal.new(nil, line)
        when Prism::WhileNode
          refuse(node, "a do-while loop is not lowered yet") if node.begin_modifier?
          While.new(expr(node.predicate), node.statements && seq(node.statements), line)
        when Prism::UntilNode
          refuse(node, "a do-until loop is not lowered yet") if node.begin_modifier?
          While.new(Not.new(expr(node.predicate), line), node.statements && seq(node.statements), line)
        when Prism::ReturnNode then Return.new(jump_value(node.arguments, line), line)
        when Prism::AndNode then And.new(expr(node.left), expr(node.right), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right), line)
        when Prism::ClassNode
          scope, name = constant_path(node.constant_path)
          superclass = node.superclass && expr(node.superclass)
          in_scope { ClassDef.new(scope, name, superclass, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line) }
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          in_scope { ModuleDef.new(scope, name, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line) }
        when Prism::SingletonClassNode
          target = expr(node.expression)
          in_scope { SingletonClassDef.new(target, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line) }
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
        when Prism::InterpolatedSymbolNode then Send.new(interpolation(node, line), :to_sym, [], line, false)
        when Prism::ArrayNode
          ArrayLit.new(node.elements.map { |e| e.is_a?(Prism::SplatNode) ? Splat.new(expr(e.expression), line) : expr(e) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
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
        when Prism::AliasMethodNode
          refuse(node, "an alias of a dynamic symbol is not lowered yet") unless node.new_name.is_a?(Prism::SymbolNode) && node.old_name.is_a?(Prism::SymbolNode)
          Alias.new(node.new_name.unescaped.to_sym, node.old_name.unescaped.to_sym, line)
        when Prism::CaseNode
          clauses = node.conditions.map do |w|
            values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? Splat.new(expr(c.expression), line) : expr(c) }
            [values, w.statements ? seq(w.statements) : Literal.new(nil, line)]
          end
          Case.new(node.predicate && expr(node.predicate), clauses, node.else_clause && expr(node.else_clause), line)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode
          refuse(node, "a block in an index target is not lowered yet") if node.block
          args = (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? refuse(a, "a splat in an index target is not lowered yet") : expr(a) }
          op = case node
               when Prism::IndexOperatorWriteNode then node.binary_operator
               when Prism::IndexOrWriteNode then :or
               else :and
               end
          IndexOpAssign.new(expr(node.receiver), args, op, expr(node.value), line)
        when Prism::CallOperatorWriteNode, Prism::CallOrWriteNode, Prism::CallAndWriteNode
          refuse(node, "a safe-navigation attribute assignment is not lowered yet") if node.call_operator == "&."
          op = case node
               when Prism::CallOperatorWriteNode then node.binary_operator
               when Prism::CallOrWriteNode then :or
               else :and
               end
          AttrOpAssign.new(expr(node.receiver), node.read_name, op, expr(node.value), line)
        when Prism::ForNode then for_loop(node)
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
        when Prism::ConstantPathNode
          [node.parent ? expr(node.parent) : :top, node.name]
        else refuse(node, "a dynamic constant path is not lowered yet")
        end
      end

      def define(node)
        receiver = node.receiver && expr(node.receiver)
        in_scope do
          params = parameters(node.parameters)
          @def_params = params
          body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
          locals = node.locals + (params.names - node.locals)
          Def.new(node.name, params, locals, body, node.location.start_line, receiver)
        end
      end

      # A bare `super`: the method's parameters passed on as they stand,
      # a `Super` with the locals of the def this block sits in.
      def zsuper(node, line)
        p = @def_params or return ZSuper.new(node.block && block(node.block), line)

        refuse(node, "a bare super with a destructuring parameter is not lowered yet") if (p.required + p.post).any?(MultiTarget)
        local = ->(name) { Local.new(name, @block_depth, line) }
        positional = (p.required + p.optional.map(&:first)).map(&local)
        positional << Splat.new(local.call(p.rest), line) if p.rest && p.rest != :implicit
        positional += p.post.map(&local)
        pairs = p.keywords.flat_map { |name, _| [Literal.new(name, line), local.call(name)] }
        pairs += [HashSplat.new(local.call(p.kwrest), line), nil] if p.kwrest
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
      def name_of(param)
        return multi_target(param) if param.is_a?(Prism::MultiTargetNode)

        param.name
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
        when Prism::MultiTargetNode then multi_target(node)
        when Prism::IndexTargetNode
          args = (node.arguments&.arguments || []).map { |a| a.is_a?(Prism::SplatNode) ? refuse(a, "a splat in an index target is not lowered yet") : expr(a) }
          Send.new(expr(node.receiver), :[]=, args, line, false, true, nil, nil)
        when Prism::CallTargetNode
          refuse(node, "a safe-navigation target is not lowered yet") if node.call_operator == "&."
          Send.new(expr(node.receiver), node.name, [], line, false, false, nil, nil)
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} as an assignment target is not lowered yet")
        end
      end

      # A rest parameter's name; `|a, |` has an implicit one that binds
      # nothing.
      def rest_name(node)
        case node
        when Prism::ImplicitRestNode then :implicit
        when Prism::RestParameterNode then node.name || ANONYMOUS[:rest]
        when Prism::KeywordRestParameterNode then node.name || ANONYMOUS[:kwrest]
        when Prism::ForwardingParameterNode then ANONYMOUS[:kwrest]
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # A block literal, or the `&value` a call passes on.
      def block(node)
        line = node.location.start_line
        return BlockPass.new(node.expression ? expr(node.expression) : Local.new(ANONYMOUS[:block], @block_depth, line), line) if node.is_a?(Prism::BlockArgumentNode)

        in_block do
          params, extra = block_params(node.parameters)
          Block.new(params, node.locals + extra, node.body ? expr(node.body) : Literal.new(nil, line), line)
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
          refuse(node, "a block-local variable is not lowered yet") unless node.locals.empty?
          [parameters(node.parameters), []]
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      def call(node)
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil?

        args, kwargs, forwarded = arguments(node.arguments)
        opt = (%i[[] []=].include?(node.name) && node.opening == "[") || (node.name == :<< && node.call_operator.nil? && args.size == 1)
        Send.new(node.receiver && expr(node.receiver), node.name, args, node.location.start_line, node.variable_call?, opt,
                 node.block ? block(node.block) : forwarded, kwargs, node.call_operator == "&.", node.attribute_write?)
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
        bind = target.is_a?(MultiTarget) ? MultiAssign.new(target, Local.new(:"*for", 0, line), line) : target.tap { |t| t.value = Local.new(:"*for", 0, line) }
        params = Params.new([:"*for"], [], nil, [], [], nil, nil)
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
