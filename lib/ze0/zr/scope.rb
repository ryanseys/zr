# frozen_string_literal: true

require_relative "../hir"

module Ze0
  module Zr
    # What a scope's body asks of its frame record: an Env for the locals
    # a block of its own may capture, and staging slots for sends.
    module Scope
      module_function

      # Whether `node` holds a block literal of this scope (not one inside
      # a nested def or body, which is its own scope).
      def holds_block?(node)
        case node
        when Hir::Send then !node.block.nil? || (node.recv && holds_block?(node.recv)) || node.args.any? { |a| holds_block?(a) }
        when Hir::Def then holds_block?(node.receiver)
        when Hir::ClassDef, Hir::ModuleDef, nil then false
        when Hir::SingletonClassDef then holds_block?(node.target)
        when Struct then node.to_a.any? { |v| v.is_a?(Struct) ? holds_block?(v) : v.is_a?(Array) && v.any? { |e| holds_block?(e) } }
        else false
        end
      end

      # How many record slots the sends under `node` need at once, past
      # `base`: a send holds its receiver and arguments while an
      # argument's own sends run above them.
      def staging(node, base = 0)
        case node
        when Hir::Seq then node.stmts.map { |s| staging(s, base) }.max || base
        when Hir::Send
          top = base + 1 + node.args.size + (node.block ? 1 : 0)
          [top, node.recv ? staging(node.recv, top) : base, *node.args.map { |a| staging(a, top) }].max
        when Hir::Yield then row(node.args, base)
        when Hir::ArrayLit then row(node.elements, base)
        when Hir::HashLit then row(node.pairs, base)
        when Hir::Interp then row(node.parts, base)
        when Hir::Assign, Hir::Not, Hir::IvarWrite, Hir::ConstWrite then staging(node.value, base)
        when Hir::Break, Hir::Next, Hir::Return then staging(node.value, base + 1)
        when Hir::Begin
          top = base + (node.rescues.empty? ? 0 : 2) + (node.ensure_body ? 2 : 0)
          [top, staging(node.body, top), *node.rescues.map { |r| staging(r, top) }, staging(node.else_body, top), staging(node.ensure_body, top)].max
        when Hir::Rescue then [staging(node.body, base), *node.classes.map { |c| staging(c, base) }].max
        when Hir::ClassDef then [staging(node.scope, base), staging(node.superclass, base)].max
        when Hir::SingletonClassDef then staging(node.target, base)
        when Hir::Def then staging(node.receiver, base)
        when Hir::ModuleDef, Hir::ConstRead then staging(node.scope, base)
        when Hir::If then [staging(node.cond, base), staging(node.yes, base), staging(node.no, base)].max
        when Hir::While then [staging(node.cond, base), staging(node.body, base)].max
        when Hir::And, Hir::Or then [staging(node.left, base), staging(node.right, base)].max
        else base
        end
      end

      # `parts` evaluated one after another into consecutive slots.
      def row(parts, base)
        top = base + parts.size
        [top, *parts.map { |p| staging(p, top) }].max
      end
    end
  end
end
