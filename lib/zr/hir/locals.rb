# frozen_string_literal: true

module Zr
  module Hir
    # What makes a scope keep its locals in an Env and not in its frame
    # record: a block that captures them, or a send that opens them. The
    # lowering (`Lower::Function`) and the walker on CRuby
    # (`Machine::Host::Walk`) both read it.
    module Locals
      module_function

      # Whether `node` contains a block literal of this scope (not one in
      # a nested def or body, which is a different scope).
      def holds_block?(node)
        case node
        when Send, Super
          node.block.is_a?(Block) || holds_block?(node.kwargs) || holds_block?(node.block) || node.args.any? { |a| holds_block?(a) } ||
            (node.is_a?(Send) && holds_block?(node.recv))
        when Lambda then true
        when Def then holds_block?(node.receiver)
        when ClassDef, ModuleDef, nil then false
        when SingletonClassDef then holds_block?(node.target)
        when Node, Array then Hir.each_child(node).any? { |v| holds_block?(v) }
        else false
        end
      end

      # The sends that make a scope keep its locals in an Env: an eval
      # reads and writes them there, a Binding keeps them after the frame
      # is gone, and `local_variables` lists them.
      OPEN_FORMS = %i[eval binding local_variables].freeze

      # The sends that take a method name as their first argument, so
      # `send(:binding)` opens the scope as `binding` does.
      BY_NAME = %i[send __send__ public_send method public_method].freeze

      # Whether this scope's own body `node` calls one of those. The
      # receiver is ignored: `Kernel.binding` and `self.binding` open this
      # scope as the bare form does. A scope that contains a block already
      # has an Env, so this does not walk a block body; the block is
      # checked separately.
      def opens_locals?(node)
        case node
        when Send
          OPEN_FORMS.include?(node.name) || (STRING_EVALS.include?(node.name) && !node.args.empty?) || named_open_form?(node) ||
            node.to_a.any? { |v| opens_locals?(v) }
        when Block, Lambda, ClassDef, ModuleDef, nil then false
        when Def then opens_locals?(node.receiver)
        when SingletonClassDef then opens_locals?(node.target)
        when Node, Array then Hir.each_child(node).any? { |v| opens_locals?(v) }
        else false
        end
      end

      # `send(:binding)` and the rest of BY_NAME, when the name is a
      # literal symbol.
      def named_open_form?(node)
        return false unless BY_NAME.include?(node.name)

        first = node.args.first
        first.is_a?(Literal) && OPEN_FORMS.include?(first.value)
      end
    end
  end
end
