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
        when Hir::Send, Hir::Super
          node.block.is_a?(Hir::Block) || holds_block?(node.kwargs) || holds_block?(node.block) || node.args.any? { |a| holds_block?(a) } ||
            (node.is_a?(Hir::Send) && holds_block?(node.recv))
        when Hir::Lambda then true
        when Hir::Def then holds_block?(node.receiver)
        when Hir::ClassDef, Hir::ModuleDef, nil then false
        when Hir::SingletonClassDef then holds_block?(node.target)
        when Struct then node.to_a.any? { |v| v.is_a?(Struct) ? holds_block?(v) : v.is_a?(Array) && v.any? { |e| holds_block?(e) } }
        else false
        end
      end

      # How many record slots the sends under `node` need at once, past
      # `base`: a send holds its receiver and arguments while an
      # argument's own sends run above them. An ensure body may run from
      # a jump anywhere inside its region, above the value the jump
      # carries.
      def staging(node, base = 0)
        case node
        when Hir::Seq then node.stmts.map { |s| staging(s, base) }.max || base
        when Hir::Send
          extra = (node.kwargs ? 1 : 0) + (node.block ? 1 : 0) + (node.safe ? 1 : 0)
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + extra
          [top, staging(node.recv, top), staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Super
          extra = (node.kwargs ? 1 : 0) + (node.block ? 1 : 0)
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + extra
          [top, staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Lambda then base + 1
        when Hir::Splat, Hir::HashSplat, Hir::BlockPass then staging(node.value, base)
        when Hir::Yield
          parts = node.args + [node.kwargs].compact
          spread?(parts) ? gathered(parts, base) : row(parts, base)
        when Hir::ArrayLit then spread?(node.elements) ? gathered(node.elements, base) : row(node.elements, base)
        when Hir::HashLit then spread?(node.pairs) ? gathered(node.pairs, base) : row(node.pairs, base)
        when Hir::RangeLit then row([node.low, node.high], base)
        when Hir::Interp then row(node.parts, base)
        when Hir::Assign, Hir::IvarWrite, Hir::ConstWrite, Hir::GvarWrite, Hir::CvarWrite then staging(node.value, base)
        when Hir::Not then gathered([node.value], base)
        when Hir::ConstOrWrite then [staging(node.scope, base), staging(node.value, base)].max
        when Hir::Defined then staging(node.target, base + 1)
        when Hir::Slot then base
        when Hir::Case
          top = base + 3
          [top, staging(node.subject, top), staging(node.else_body, top), *node.clauses.flat_map { |values, body| [staging(body, top), *values.map { |v| staging(v, top) }] }].max
        when Hir::IndexOpAssign
          top = base + 3 + node.args.size
          [top, staging(node.recv, top), staging(node.value, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::AttrOpAssign
          top = base + 3
          [top, staging(node.recv, top), staging(node.value, top)].max
        when Hir::MultiAssign
          top = base + 1 + prepared(node.target)
          [staging(node.value, top), top + targets(node.target), *sends_in(node.target).map { |s| staging(s, top) }].max
        when Hir::Break, Hir::Next, Hir::Return then staging(node.value, base + 1)
        when Hir::Begin
          top = base + (node.rescues.empty? ? 0 : 2) + (node.ensure_body ? 2 : 0)
          inside = [top, staging(node.body, top), *node.rescues.map { |r| staging(r, top) }, staging(node.else_body, top)].max
          [inside, staging(node.ensure_body, inside + 1)].max
        when Hir::Rescue then [staging(node.body, base + 2), staging(node.target, base + 1), *node.classes.map { |c| staging(c, base) }].max
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

      # The slots a MultiTarget's Send targets stage ahead of the value:
      # a receiver and arguments each.
      def prepared(target)
        sends_in(target).sum { |s| 2 + s.args.size }
      end

      def sends_in(target)
        (target.lefts + [target.rest] + target.rights).flat_map do |t|
          case t
          when Hir::Send then [t]
          when Hir::MultiTarget then sends_in(t)
          else []
          end
        end
      end

      # The slots destructuring into `target` takes: one Array per level.
      def targets(target)
        nested = (target.lefts + [target.rest] + target.rights).grep(Hir::MultiTarget).map { |t| targets(t) }.max || 0
        1 + nested
      end

      # `parts` evaluated one after another into consecutive slots.
      def row(parts, base)
        top = base + parts.size
        [top, *parts.map { |p| staging(p, top) }].max
      end

      # `parts` pushed one after another into one collection kept in a
      # slot: the form a splat takes.
      def gathered(parts, base)
        [base + 1, *parts.map { |p| staging(p, base + 1) }].max
      end

      def spread?(parts)
        parts.any? { |p| p.is_a?(Hir::Splat) || p.is_a?(Hir::HashSplat) }
      end
    end
  end
end
