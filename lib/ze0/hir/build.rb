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

        Program.new(file, result.value.locals, new(file).seq(result.value.statements))
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
        when Prism::LocalVariableReadNode then Local.new(node.name, line)
        when Prism::LocalVariableWriteNode then Assign.new(node.name, expr(node.value), line)
        when Prism::LocalVariableOperatorWriteNode
          Assign.new(node.name, Send.new(Local.new(node.name, line), node.binary_operator, [expr(node.value)], line, false), line)
        when Prism::LocalVariableAndWriteNode
          Assign.new(node.name, And.new(Local.new(node.name, line), expr(node.value), line), line)
        when Prism::LocalVariableOrWriteNode
          Assign.new(node.name, Or.new(Local.new(node.name, line), expr(node.value), line), line)
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
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
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

      def call(node)
        refuse(node, "a block is not lowered yet") if node.block
        refuse(node, "a safe-navigation call is not lowered yet") if node.call_operator == "&."
        return Not.new(expr(node.receiver), node.location.start_line) if node.name == :! && node.receiver && node.arguments.nil?

        args = (node.arguments&.arguments || []).map do |a|
          case a
          when Prism::SplatNode, Prism::KeywordHashNode, Prism::BlockArgumentNode
            refuse(a, "#{a.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
          else expr(a)
          end
        end
        Send.new(node.receiver && expr(node.receiver), node.name, args, node.location.start_line, node.variable_call?)
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.location.start_line}: #{message}"
      end
    end
  end
end
