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
        when Struct then node.to_a.any? { |v| holds_block?(v) }
        when Array then node.any? { |v| holds_block?(v) }
        else false
        end
      end

      # How many assignments `node` makes to each local of the scope it is
      # the body of, as a Hash counting from zero. A block reaches the
      # scope's locals one level further out; a def, class or module body
      # is a scope of its own, and only the expressions that stand in this
      # scope around it (a singleton def's receiver, a superclass) are read.
      def assignments(node, level = 0, counts = Hash.new(0))
        case node
        when Hir::Assign
          counts[node.name] += 1 if node.depth == level
          assignments(node.value, level, counts)
        when Hir::Block then assignments([node.params, node.body], level + 1, counts)
        when Hir::Def then assignments(node.receiver, level, counts)
        when Hir::ClassDef then assignments([node.scope, node.superclass], level, counts)
        when Hir::ModuleDef then assignments(node.scope, level, counts)
        when Hir::SingletonClassDef then assignments(node.target, level, counts)
        when Struct, Array then node.each { |child| assignments(child, level, counts) }
        end
        counts
      end

      # The sends that make a scope keep its locals in an Env: an eval
      # reads and writes them there, a Binding holds them after the frame
      # is gone, and `local_variables` names them.
      OPEN_FORMS = %i[eval binding local_variables].freeze

      # The evals that run a string under another self, which reads this
      # scope's locals as `eval` does; the block forms do not.
      STRING_EVALS = %i[class_eval module_eval instance_eval].freeze

      # The sends that carry a method name as their first argument, so
      # `send(:binding)` opens the scope that `binding` would.
      BY_NAME = %i[send __send__ public_send method public_method].freeze

      # Whether `node` names one of those in this scope's own body. The
      # receiver is not read: `Kernel.binding` and `self.binding` answer
      # for this scope as the bare form does. A scope that holds a block
      # already has an Env, so a block body is not walked: it answers for
      # itself.
      def opens_locals?(node)
        case node
        when Hir::Send
          OPEN_FORMS.include?(node.name) || (STRING_EVALS.include?(node.name) && !node.args.empty?) || named_open_form?(node) ||
            node.to_a.any? { |v| opens_locals?(v) }
        when Hir::Block, Hir::Lambda, Hir::ClassDef, Hir::ModuleDef, nil then false
        when Hir::Def then opens_locals?(node.receiver)
        when Hir::SingletonClassDef then opens_locals?(node.target)
        when Struct then node.to_a.any? { |v| opens_locals?(v) }
        when Array then node.any? { |v| opens_locals?(v) }
        else false
        end
      end

      # `send(:binding)` and the rest of BY_NAME, where the name is a
      # symbol the compile can read.
      def named_open_form?(node)
        return false unless BY_NAME.include?(node.name)

        first = node.args.first
        first.is_a?(Hir::Literal) && OPEN_FORMS.include?(first.value)
      end

      # How many record slots the sends under `node` need at once, past
      # `base`: a send holds its receiver and arguments while an
      # argument's own sends run above them. An ensure body may run from
      # a jump anywhere inside its region, above the value the jump
      # carries. An operator assignment keeps its receiver, arguments
      # and current value while the read and the write are sent.
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
        when Hir::Splat, Hir::HashSplat, Hir::BlockPass, Hir::Using then staging(node.value, base)
        when Hir::KwSplatElement then staging(node.pairs, base)
        when Hir::Once then staging(node.body, base)
        when Hir::Yield
          parts = node.args + [node.kwargs].compact
          spread?(parts) ? gathered(parts, base) : row(parts, base)
        when Hir::ArrayLit then spread?(node.elements) ? gathered(node.elements, base) : row(node.elements, base)
        when Hir::HashLit then spread?(node.pairs) ? spread_pairs(node.pairs, base) : row(node.pairs, base)
        when Hir::AliasValue then row([node.new_name, node.old_name], base)
        when Hir::UndefValue then row(node.names, base)
        when Hir::RegexpOnce then staging(node.value, base)
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
          # The receiver, the arguments and the current value keep slots;
          # the operator send (`current op value`) stages two more above.
          top = base + 2 + node.args.size
          [top + 2 + node.args.size, staging(node.recv, top), staging(node.value, top + 2), *node.args.map { |a| staging(a, top) }].max
        when Hir::AttrOpAssign
          top = base + 2
          [top + 2, staging(node.recv, top), staging(node.value, top + 2)].max
        when Hir::MultiAssign
          top = base + 1 + prepared(node.target)
          [staging(node.value, top), top + targets(node.target), *staged_in(node.target).map { |t| staging(t.is_a?(Hir::ConstWrite) ? t.scope : t, top) }].max
        when Hir::Break, Hir::Next, Hir::Return then staging(node.value, base + 1)
        when Hir::Begin
          top = base + (node.rescues.empty? ? 0 : 2) + (node.ensure_body ? 2 : 0)
          inside = [top, staging(node.body, top), *node.rescues.map { |r| staging(r, top) }, staging(node.else_body, top)].max
          [inside, staging(node.ensure_body, inside + 1)].max
        when Hir::Rescue
          # A `rescue => a.b` or `=> h[k]` target holds its receiver,
          # arguments and value in slots under the clause's own two.
          held = node.target.is_a?(Hir::Send) ? 2 + node.target.args.size : 0
          [staging(node.target, base), staging(node.body, base + held + 2), *node.classes.map { |c| staging(c, base) }].max
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

      # The slots a MultiTarget's targets stage ahead of the value: a
      # receiver and arguments for each send, and the scope of each
      # constant written through an expression (`a::B, c = ...`).
      def prepared(target)
        staged_in(target).sum { |t| t.is_a?(Hir::Send) ? 2 + t.args.size : 1 }
      end

      def staged_in(target)
        (target.lefts + [target.rest] + target.rights).flat_map do |t|
          case t
          when Hir::Send then [t]
          when Hir::ConstWrite then t.scope.nil? || t.scope == :top ? [] : [t]
          when Hir::MultiTarget then staged_in(t)
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

      # A hash literal with a `**`: the hash in one slot, each plain pair
      # staged as a row of two above it, each spread evaluated there.
      def spread_pairs(pairs, base)
        tops = pairs.each_slice(2).map do |key, value|
          key.is_a?(Hir::HashSplat) ? staging(key.value, base + 1) : row([key, value], base + 1)
        end
        [base + 1, *tops].max
      end

      def spread?(parts)
        parts.any? { |p| p.is_a?(Hir::Splat) || p.is_a?(Hir::HashSplat) }
      end
    end
  end
end
