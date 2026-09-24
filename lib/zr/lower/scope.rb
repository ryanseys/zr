# frozen_string_literal: true

require_relative "../hir"

module Zr
  class Lower
    # What a scope's body needs in its frame record: an Env for the locals
    # that its blocks can capture, and staging slots for sends.
    module Scope
      module_function

      # Whether `node` contains a block literal of this scope (not one in
      # a nested def or body, which is a different scope).
      def holds_block?(node)
        case node
        when Hir::Send, Hir::Super
          node.block.is_a?(Hir::Block) || holds_block?(node.kwargs) || holds_block?(node.block) || node.args.any? { |a| holds_block?(a) } ||
            (node.is_a?(Hir::Send) && holds_block?(node.recv))
        when Hir::Lambda then true
        when Hir::Def then holds_block?(node.receiver)
        when Hir::ClassDef, Hir::ModuleDef, nil then false
        when Hir::SingletonClassDef then holds_block?(node.target)
        when Record then node.to_a.any? { |v| holds_block?(v) }
        when Array then node.any? { |v| holds_block?(v) }
        else false
        end
      end

      # The count of assignments that the body `node` makes to each local
      # of its scope, as a Hash with default zero. A block sees the scope's
      # locals one level further out. A def, class or module body is a
      # different scope, so only its expressions in this scope (a singleton
      # def's receiver, a superclass) are read.
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
        when Record, Array then node.each { |child| assignments(child, level, counts) }
        end
        counts
      end

      # The sends that make a scope keep its locals in an Env: an eval
      # reads and writes them there, a Binding keeps them after the frame
      # is gone, and `local_variables` lists them.
      OPEN_FORMS = %i[eval binding local_variables].freeze

      # The evals that run a string with a different self. The string
      # reads this scope's locals as `eval` does. The block forms do not.
      STRING_EVALS = %i[class_eval module_eval instance_eval].freeze

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
        when Hir::Send
          OPEN_FORMS.include?(node.name) || (STRING_EVALS.include?(node.name) && !node.args.empty?) || named_open_form?(node) ||
            node.to_a.any? { |v| opens_locals?(v) }
        when Hir::Block, Hir::Lambda, Hir::ClassDef, Hir::ModuleDef, nil then false
        when Hir::Def then opens_locals?(node.receiver)
        when Hir::SingletonClassDef then opens_locals?(node.target)
        when Record then node.to_a.any? { |v| opens_locals?(v) }
        when Array then node.any? { |v| opens_locals?(v) }
        else false
        end
      end

      # `send(:binding)` and the rest of BY_NAME, when the name is a
      # literal symbol.
      def named_open_form?(node)
        return false unless BY_NAME.include?(node.name)

        first = node.args.first
        first.is_a?(Hir::Literal) && OPEN_FORMS.include?(first.value)
      end

      # The iterators that a site with a block literal runs inline
      # (Function::Iterators), each with the maximum parameter count of
      # its block.
      ITERATORS = { each: 1, times: 1 }.freeze

      # Whether `node` is a send of one of ITERATORS that a site can run
      # inline. It needs no arguments, an explicit receiver, and a block
      # literal with at most one plain parameter. The block must contain no
      # block, open no binding, and pass `loop_body?`. The block keeps its
      # locals in the site's record, so `staging` counts them.
      def iterator_template?(node)
        return false unless node.is_a?(Hir::Send) && node.block.is_a?(Hir::Block) && ITERATORS.key?(node.name)
        return false unless node.args.empty? && node.kwargs.nil? && node.recv && node.using.nil?

        p = node.block.params
        return false unless p.plain? && p.block.nil? && p.required.size <= ITERATORS.fetch(node.name) && p.required.all?(Symbol)

        body = node.block.body
        !holds_block?(body) && !opens_locals?(body) && loop_body?(body)
      end

      # Whether a block body can run in the frame of its enclosing scope.
      # Nothing in it can need the block's own frame or define under it:
      # no super, no def or class body, and no trace or coverage entry (a
      # traced program keeps every frame).
      def loop_body?(node)
        case node
        when Hir::Super, Hir::ZSuper, Hir::Def, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef, Hir::Trace, Hir::Cover then false
        when Record then node.to_a.all? { |v| loop_body?(v) }
        when Array then node.all? { |v| loop_body?(v) }
        else true
        end
      end

      # The maximum record slots above `base` that the sends under `node`
      # need at one time. A send keeps its receiver and arguments while an
      # argument's own sends run above them. An ensure body can run from a
      # jump anywhere in its region, above the jump's value. An operator
      # assignment keeps its receiver, arguments and current value during
      # the read and the write.
      def staging(node, base = 0)
        case node
        when Hir::Seq then node.stmts.map { |s| staging(s, base) }.max || base
        when Hir::Send
          # A safe call keeps its receiver, and a `new` its new object.
          extra = keyword_slots(node.kwargs) + (node.safe ? 1 : 0) + (node.name == :new ? 1 : 0)
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + extra
          # An inline iterator keeps its block's locals and its index
          # above the receiver, and the body stages above those.
          inside = iterator_template?(node) ? staging(node.block.body, top + node.block.locals.size + 1) : top
          [top, inside, staging(node.recv, top), staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Super
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + keyword_slots(node.kwargs)
          [top, staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Lambda then base
        when Hir::Autoload then [base + 2, staging(node.recv, base)].max
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
          # A literal list whose value is not used stays in its slots
          # while the targets (and nested targets) read it.
          spread = node.value.is_a?(Hir::ArrayLit) && !spread?(node.value.elements) ? node.value.elements.size : 0
          [staging(node.value, top), top + spread + targets(node.target), *staged_in(node.target).map { |t| staging(t.is_a?(Hir::ConstWrite) ? t.scope : t, top) }].max
        when Hir::Break, Hir::Next, Hir::Return then staging(node.value, base + 1)
        when Hir::Begin
          # An ensure keeps three slots. During a pending unwind, its body
          # runs in a region with two more slots, which restores `$!` if
          # the body jumps out.
          top = base + (node.rescues.empty? ? 0 : 2) + (node.ensure_body ? 3 : 0)
          inside = [top, staging(node.body, top), *node.rescues.map { |r| staging(r, top) }, staging(node.else_body, top)].max
          node.ensure_body ? [inside + 2, staging(node.ensure_body, inside + 3)].max : inside
        when Hir::Rescue
          # A `rescue => a.b` or `=> h[k]` target keeps its receiver,
          # arguments and value in slots below the clause's own two.
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

      # The slots that a MultiTarget's targets stage before the value: a
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

      # The slots for destructuring into `target`: one Array per level.
      def targets(target)
        nested = (target.lefts + [target.rest] + target.rights).grep(Hir::MultiTarget).map { |t| targets(t) }.max || 0
        1 + nested
      end

      # `parts` evaluated one after another into consecutive slots.
      def row(parts, base)
        top = base + parts.size
        [top, *parts.map { |p| staging(p, top) }].max
      end

      # `parts` pushed one after another into one collection in a slot,
      # as for a splat.
      def gathered(parts, base)
        [base + 1, *parts.map { |p| staging(p, base + 1) }].max
      end

      # A hash literal with a `**`: the hash in one slot, each plain pair
      # staged in two slots above it, and each spread evaluated there.
      def spread_pairs(pairs, base)
        tops = pairs.each_slice(2).map do |key, value|
          key.is_a?(Hir::HashSplat) ? staging(key.value, base + 1) : row([key, value], base + 1)
        end
        [base + 1, *tops].max
      end

      def spread?(parts)
        parts.any? { |p| p.is_a?(Hir::Splat) || p.is_a?(Hir::HashSplat) }
      end

      # Whether a call's keywords are `k: v` pairs with distinct Symbol
      # keys and no `**`. These go as trailing values with a static table
      # of the keys (runtime/kernel/send.rb, `zr_kw_pass`). All other
      # keywords go as one Hash.
      def literal_keywords?(kwargs)
        keys = kwargs.pairs.each_slice(2).map(&:first)
        keys.all? { |key| key.is_a?(Hir::Literal) && key.value.is_a?(Symbol) } && keys.map(&:value).uniq.size == keys.size
      end

      # The record slots for a call's keywords, in addition to its arguments.
      def keyword_slots(kwargs)
        return 0 unless kwargs

        literal_keywords?(kwargs) ? kwargs.pairs.size / 2 : 1
      end
    end
  end
end
