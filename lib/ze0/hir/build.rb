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
        when Prism::LocalVariableOperatorWriteNode
          Assign.new(node.name, node.depth, Send.new(Local.new(node.name, node.depth, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, node.depth, And.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, node.depth, Or.new(Local.new(node.name, node.depth, line), expr(node.value), line), line)
        when Prism::YieldNode
          args = node.arguments&.arguments || []
          refuse(node, "a splat in a yield is not lowered yet") if args.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::KeywordHashNode) }
          Yield.new(args.map { |a| expr(a) }, line)
        when Prism::BreakNode, Prism::NextNode
          args = node.arguments&.arguments || []
          refuse(node, "a #{node.is_a?(Prism::BreakNode) ? "break" : "next"} of several values is not lowered yet") if args.size > 1
          value = args.empty? ? Literal.new(nil, line) : expr(args.first)
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
        when Prism::ReturnNode
          args = node.arguments&.arguments || []
          refuse(node, "a return of several values is not lowered yet") if args.size > 1
          Return.new(args.empty? ? Literal.new(nil, line) : expr(args.first), line)
        when Prism::AndNode then And.new(expr(node.left), expr(node.right), line)
        when Prism::OrNode then Or.new(expr(node.left), expr(node.right), line)
        when Prism::ClassNode
          refuse(node, "a class body with locals is not lowered yet") unless node.locals.empty?
          scope, name = constant_path(node.constant_path)
          ClassDef.new(scope, name, node.superclass && expr(node.superclass), node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line)
        when Prism::ModuleNode
          scope, name = constant_path(node.constant_path)
          ModuleDef.new(scope, name, node.locals, node.body ? expr(node.body) : Literal.new(nil, line), line)
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
          refuse(node, "a splat in an array literal is not lowered yet") if node.elements.any?(Prism::SplatNode)
          ArrayLit.new(node.elements.map { |e| expr(e) }, line)
        when Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode
          refuse(node, "an operator assignment through [] is not lowered yet")
        when Prism::InstanceVariableReadNode then IvarRead.new(node.name, line)
        when Prism::InstanceVariableWriteNode then IvarWrite.new(node.name, expr(node.value), line)
        when Prism::InstanceVariableOperatorWriteNode
          IvarWrite.new(node.name, Send.new(IvarRead.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::InstanceVariableOrWriteNode
          IvarWrite.new(node.name, Or.new(IvarRead.new(node.name, line), expr(node.value), line), line)
        when Prism::InstanceVariableAndWriteNode
          IvarWrite.new(node.name, And.new(IvarRead.new(node.name, line), expr(node.value), line), line)
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
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
        refuse(node, "a singleton def is not lowered yet") if node.receiver
        params = node.parameters
        if params
          other = params.child_nodes.compact - params.requireds
          refuse(other.first, "#{other.first.class.name.split("::").last.delete_suffix("Node")} is not lowered yet") unless other.empty?
          refuse(params, "a destructuring parameter is not lowered yet") unless params.requireds.all?(Prism::RequiredParameterNode)
        end
        names = params ? params.requireds.map(&:name) : []
        Def.new(node.name, names, node.locals, node.body ? expr(node.body) : Literal.new(nil, node.location.start_line), node.location.start_line)
      end

      # A block literal's parameters: required names only, so far.
      def block(node)
        refuse(node, "a block argument is not lowered yet") if node.is_a?(Prism::BlockArgumentNode)
        params = []
        if node.parameters
          refuse(node.parameters, "a numbered or `it` parameter is not lowered yet") unless node.parameters.is_a?(Prism::BlockParametersNode)
          inner = node.parameters.parameters
          if inner
            other = inner.child_nodes.compact - inner.requireds
            refuse(other.first, "#{other.first.class.name.split("::").last.delete_suffix("Node")} is not lowered yet") unless other.empty?
            refuse(inner, "a destructuring block parameter is not lowered yet") unless inner.requireds.all?(Prism::RequiredParameterNode)
            params = inner.requireds.map(&:name)
          end
          refuse(node.parameters, "a block-local variable is not lowered yet") unless node.parameters.locals.empty?
        end
        Block.new(params, node.locals, node.body ? expr(node.body) : Literal.new(nil, node.location.start_line), node.location.start_line)
      end

      def call(node)
        refuse(node, "a safe-navigation call is not lowered yet") if node.call_operator == "&."
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil?

        args = (node.arguments&.arguments || []).map do |a|
          case a
          when Prism::SplatNode, Prism::KeywordHashNode, Prism::BlockArgumentNode
            refuse(a, "#{a.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
          else expr(a)
          end
        end
        opt = (%i[[] []=].include?(node.name) && node.opening == "[") || (node.name == :<< && node.call_operator.nil? && args.size == 1)
        Send.new(node.receiver && expr(node.receiver), node.name, args, node.location.start_line, node.variable_call?, opt,
                 node.block && block(node.block))
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end
  end
end
