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
          params = Params.new([], [], nil, [], [], nil, nil)
          if node.parameters
            refuse(node.parameters, "a numbered or `it` parameter is not lowered yet") unless node.parameters.is_a?(Prism::BlockParametersNode)
            params = parameters(node.parameters.parameters)
            refuse(node.parameters, "a block-local variable is not lowered yet") unless node.parameters.locals.empty?
          end
          Lambda.new(Block.new(params, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line), line)
        when Prism::SuperNode
          args, kwargs = arguments(node.arguments)
          Super.new(args, kwargs, node.block && block(node.block), line)
        when Prism::ForwardingSuperNode then ZSuper.new(node.block && block(node.block), line)
        when Prism::YieldNode
          args = node.arguments&.arguments || []
          refuse(node, "keywords in a yield are not lowered yet") if args.any?(Prism::KeywordHashNode)
          Yield.new(args.map { |a| a.is_a?(Prism::SplatNode) ? Splat.new(expr(a.expression), line) : expr(a) }, line)
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
          ClassDef.new(scope, name, node.superclass && expr(node.superclass), node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line)
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          ModuleDef.new(scope, name, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line)
        when Prism::SingletonClassNode
          SingletonClassDef.new(expr(node.expression), node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line)
        when Prism::ConstantReadNode then ConstRead.new(nil, node.name, line)
        when Prism::ConstantPathNode
          scope, name = constant_path(node)
          ConstRead.new(scope, name, line)
        when Prism::ConstantWriteNode then ConstWrite.new(nil, node.name, expr(node.value), line)
        when Prism::ConstantPathWriteNode
          scope, name = constant_path(node.target)
          ConstWrite.new(scope, name, expr(node.value), line)
        when Prism::InterpolatedStringNode
          parts = node.parts.map do |part|
            case part
            when Prism::StringNode then Literal.new(part.unescaped, part.location.start_line)
            when Prism::EmbeddedStatementsNode then part.statements ? seq(part.statements) : Literal.new(nil, line)
            else refuse(part, "#{part.class.name.split("::").last.delete_suffix("Node")} in a string is not lowered yet")
            end
          end
          Interp.new(parts, line)
        when Prism::ArrayNode
          ArrayLit.new(node.elements.map { |e| e.is_a?(Prism::SplatNode) ? Splat.new(expr(e.expression), line) : expr(e) }, line)
        when Prism::HashNode then HashLit.new(hash_pairs(node.elements), line)
        when Prism::RangeNode
          RangeLit.new(node.left ? expr(node.left) : Literal.new(nil, line), node.right ? expr(node.right) : Literal.new(nil, line), node.exclude_end?, line)
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::GlobalVariableReadNode then GvarRead.new(node.name, line)
        when Prism::GlobalVariableWriteNode then GvarWrite.new(node.name, expr(node.value), line)
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
            values = w.conditions.map { |c| c.is_a?(Prism::SplatNode) ? refuse(c, "a splat in a when is not lowered yet") : expr(c) }
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
          clause = Rescue.new([], nil, nil, expr(node.rescue_expression), line)
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
        refuse(node, "a splat in a rescue clause is not lowered yet") if node.exceptions.any?(Prism::SplatNode)
        name = depth = nil
        if node.reference
          refuse(node.reference, "a rescue into anything but a local is not lowered yet") unless node.reference.is_a?(Prism::LocalVariableTargetNode)
          name = node.reference.name
          depth = node.reference.depth
        end
        Rescue.new(node.exceptions.map { |e| expr(e) }, name, depth, node.statements ? seq(node.statements) : Literal.new(nil, line), line)
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
        body = node.body ? expr(node.body) : Literal.new(nil, node.location.start_line)
        Def.new(node.name, parameters(node.parameters), node.locals, body, node.location.start_line, node.receiver && expr(node.receiver))
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
        block = node.block && (node.block.name or refuse(node.block, "an anonymous block parameter is not lowered yet"))
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
        when Prism::RestParameterNode, Prism::KeywordRestParameterNode
          node.name or refuse(node, "an anonymous rest parameter is not lowered yet")
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      # A block literal, or the `&value` a call passes on.
      def block(node)
        return BlockPass.new(node.expression ? expr(node.expression) : refuse(node, "an anonymous block argument is not lowered yet"), node.location.start_line) if node.is_a?(Prism::BlockArgumentNode)

        params = Params.new([], [], nil, [], [], nil, nil)
        if node.parameters
          refuse(node.parameters, "a numbered or `it` parameter is not lowered yet") unless node.parameters.is_a?(Prism::BlockParametersNode)
          params = parameters(node.parameters.parameters)
          refuse(node.parameters, "a block-local variable is not lowered yet") unless node.parameters.locals.empty?
        end
        Block.new(params, node.locals, node.body ? expr(node.body) : Literal.new(nil, node.location.start_line), node.location.start_line)
      end

      def call(node)
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil?

        args, kwargs = arguments(node.arguments)
        opt = (%i[[] []=].include?(node.name) && node.opening == "[") || (node.name == :<< && node.call_operator.nil? && args.size == 1)
        Send.new(node.receiver && expr(node.receiver), node.name, args, node.location.start_line, node.variable_call?, opt,
                 node.block && block(node.block), kwargs, node.call_operator == "&.")
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

      # `[args, kwargs]` of an argument list: Splats among the args, the
      # keywords as one HashLit or nil.
      def arguments(node)
        kwargs = nil
        args = (node&.arguments || []).filter_map do |a|
          case a
          when Prism::SplatNode then Splat.new(expr(a.expression), a.location.start_line)
          when Prism::KeywordHashNode
            kwargs = HashLit.new(hash_pairs(a.elements), a.location.start_line)
            nil
          else expr(a)
          end
        end
        [args, kwargs]
      end

      # A hash's elements as a flat pair list; a `**value` is a HashSplat
      # key with a nil value.
      def hash_pairs(elements)
        elements.flat_map do |e|
          case e
          when Prism::AssocNode
            refuse(e, "a hash shorthand `{x:}` is not lowered yet") if e.value.is_a?(Prism::ImplicitNode)
            [expr(e.key), expr(e.value)]
          when Prism::AssocSplatNode
            [HashSplat.new(e.value ? expr(e.value) : refuse(e, "an anonymous double splat is not lowered yet"), e.location.start_line), nil]
          end
        end
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end
  end
end
