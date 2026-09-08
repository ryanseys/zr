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

        Program.new(file, new(file).seq(result.value.statements))
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
        else refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not lowered yet")
        end
      end

      def call(node)
        refuse(node, "a block is not lowered yet") if node.block
        refuse(node, "a safe-navigation call is not lowered yet") if node.call_operator == "&."
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
