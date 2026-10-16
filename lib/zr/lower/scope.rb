# frozen_string_literal: true

require_relative "../hir"

module Zr
  class Lower
    # What a scope's body needs in its frame record: staging slots for
    # sends. Whether it needs an Env is `Hir::Locals`.
    module Scope
      module_function

      # The iterators that a site with a block literal runs inline
      # (Function::Iterators), each with the maximum parameter count of
      # its block.
      ITERATORS = { each: 1, times: 1, map: 1, select: 1, upto: 1 }.freeze #: Hash[Symbol, Integer]
      # The iterators that take arguments, with their count: `upto` takes
      # its limit.
      ITERATOR_ARGS = { upto: 1 }.freeze #: Hash[Symbol, Integer]

      # The record slots that an inline iterator keeps above its receiver:
      # its block's locals and its index. `map` and `select` also keep the
      # Array that they make.
      #: (Hir::Send node) -> Integer
      def loop_slots(node)
        # An iterator template's block is a block literal.
        block = node.block #: Hir::Block
        block.locals.size + (%i[map select].include?(node.name) ? 2 : 1)
      end

      # Whether `node` is a send of one of ITERATORS that a site can run
      # inline. It needs its plain arguments (ITERATOR_ARGS, else none), an
      # explicit receiver, and a block literal with at most one plain
      # parameter. The block must contain no block, open no binding, and
      # pass `loop_body?`. The block keeps its locals in the site's
      # record, so `staging` counts them.
      #: (Hir::Send node) -> bool
      def iterator_template?(node)
        block = node.block
        return false unless block.is_a?(Hir::Block) && ITERATORS.key?(node.name)
        return false unless node.args.size == ITERATOR_ARGS.fetch(node.name, 0) && !spread?(node.args)
        return false unless node.kwargs.nil? && node.recv && node.using.nil?

        p = block.params
        return false unless p.plain? && p.block.nil? && p.required.size <= ITERATORS.fetch(node.name) && p.required.all?(Symbol)

        body = block.body
        !Hir::Locals.holds_block?(body) && !Hir::Locals.opens_locals?(body) && loop_body?(body)
      end

      # Whether a block body can run in the frame of its enclosing scope.
      # Nothing in it can need the block's own frame or define under it:
      # no super, no def or class body, and no trace or coverage entry (a
      # traced program keeps every frame).
      #: (untyped node) -> bool
      def loop_body?(node)
        case node
        when Hir::Super, Hir::ZSuper, Hir::Def, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef, Hir::Trace, Hir::Cover then false
        when Hir::Node, Array then Hir.all_children?(node) { |v| loop_body?(v) }
        else true
        end
      end

      # Whether a constant write keeps its scope in a slot while its value
      # runs: a scope that only an expression holds (`m::Z = v`). A
      # constant, `self` or a core class stays alive without one.
      #: (Hir::scope scope) -> bool
      def held_scope?(scope) = scope.is_a?(Hir::Node) && [Hir::ConstRead, Hir::SelfRef, Hir::Core].none? { scope.is_a?(_1) }

      # The maximum record slots above `base` that the sends under `node`
      # need at one time. A send keeps its receiver and arguments while an
      # argument's own sends run above them. An ensure body can run from a
      # jump anywhere in its region, above the jump's value. An operator
      # assignment keeps its receiver, arguments and current value during
      # the read and the write.
      #: (untyped node, ?Integer base) -> Integer
      def staging(node, base = 0)
        case node
        when Hir::Seq then node.stmts.map { |s| staging(s, base) }.max || base
        when Hir::Send
          # A safe call or an interpolated part's `to_s` keeps its receiver,
          # and a `new` its new object.
          extra = keyword_slots(node.kwargs) + (node.safe || node.interp ? 1 : 0) + (node.name == :new ? 1 : 0)
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + extra
          # An inline iterator keeps its block's locals and its index
          # above the receiver, and the body stages above those.
          block = node.block
          inside = block.is_a?(Hir::Block) && iterator_template?(node) ? staging(block.body, top + loop_slots(node)) : top
          [top, inside, staging(node.recv, top), staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Super
          top = base + (spread?(node.args) ? 2 : 1 + node.args.size) + keyword_slots(node.kwargs)
          [top, staging(node.kwargs, top), staging(node.block, top), *node.args.map { |a| staging(a, top) }].max
        when Hir::Lambda then base
        # autoload_unit reserves its two slots, then reads the receiver
        # above them.
        when Hir::Autoload then staging(node.recv, base + 2)
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
        when Hir::Assign, Hir::IvarWrite, Hir::GvarWrite, Hir::CvarWrite then staging(node.value, base)
        when Hir::ConstWrite
          held_scope?(node.scope) ? [base + 1, staging(node.scope, base + 1), staging(node.value, base + 1)].max : staging(node.value, base)
        when Hir::Not then gathered([node.value], base)
        when Hir::ConstOrWrite then [staging(node.scope, base), staging(node.value, base)].max
        when Hir::Defined then staging(node.target, base + 1)
        when Hir::Slot then base
        when Hir::Case
          top = base + 3
          clauses = node.clauses.flat_map { |values, body| [staging(body, top), *values.map { |v| staging(v, top) }] }
          [top, staging(node.subject, top), staging(node.else_body, top), *clauses].max
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
          inner = staged_in(node.target).map { |t| staging(t.is_a?(Hir::ConstWrite) ? t.scope : t, top) }
          [staging(node.value, top), top + spread + targets(node.target), *inner].max
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
        end #: Integer
      end

      # The slots that a MultiTarget's targets stage before the value: a
      # receiver and arguments for each send, and the scope of each
      # constant written through an expression (`a::B, c = ...`).
      #: (Hir::MultiTarget target) -> Integer
      def prepared(target)
        staged_in(target).sum { |t| t.is_a?(Hir::Send) ? 2 + t.args.size : 1 }
      end

      #: (Hir::MultiTarget target) -> Array[Hir::Send | Hir::ConstWrite]
      def staged_in(target)
        (target.lefts + [target.rest] + target.rights).flat_map do |t|
          case t
          when Hir::Send then [t]
          when Hir::ConstWrite then t.scope.nil? || t.scope == :top ? [] : [t]
          when Hir::MultiTarget then staged_in(t)
          else []
          end #: Array[Hir::Send | Hir::ConstWrite]
        end
      end

      # The slots for destructuring into `target`: one Array per level.
      #: (Hir::MultiTarget target) -> Integer
      def targets(target)
        nested = (target.lefts + [target.rest] + target.rights).filter_map { |t| targets(t) if t.is_a?(Hir::MultiTarget) }.max || 0
        1 + nested
      end

      # `parts` evaluated one after another into consecutive slots.
      #: (Array[untyped] parts, Integer base) -> Integer
      def row(parts, base)
        top = base + parts.size
        [top, *parts.map { |p| staging(p, top) }].max #: Integer
      end

      # `parts` pushed one after another into one collection in a slot,
      # as for a splat.
      #: (Array[untyped] parts, Integer base) -> Integer
      def gathered(parts, base)
        [base + 1, *parts.map { |p| staging(p, base + 1) }].max #: Integer
      end

      # A hash literal with a `**`: the hash in one slot, each run of
      # plain pairs staged in the slots above it, and each spread
      # evaluated there.
      #: (Array[untyped] pairs, Integer base) -> Integer
      def spread_pairs(pairs, base)
        runs = pairs.each_slice(2).slice_when { |(a, _), (b, _)| a.is_a?(Hir::HashSplat) || b.is_a?(Hir::HashSplat) }
        tops = runs.map do |run|
          key = run.first.first
          key.is_a?(Hir::HashSplat) ? staging(key.value, base + 1) : row(run.flatten(1), base + 1)
        end
        [base + 1, *tops].max #: Integer
      end

      #: (Array[Hir::node?] parts) -> bool
      def spread?(parts)
        parts.any? { |p| p.is_a?(Hir::Splat) || p.is_a?(Hir::HashSplat) }
      end

      # Whether a call's keywords are `k: v` pairs with distinct Symbol
      # keys and no `**`. These go as trailing values with a static table
      # of the keys (lib/zr/runtime/kernel/send.rb, `zr_kw_pass`). All other
      # keywords go as one Hash.
      #: (Hir::HashLit kwargs) -> bool
      def literal_keywords?(kwargs)
        names = kwargs.pairs.each_slice(2).map { |key, _| key.value if key.is_a?(Hir::Literal) }
        names.all?(Symbol) && names.uniq.size == names.size
      end

      # The record slots for a call's keywords, in addition to its arguments.
      #: (Hir::HashLit? kwargs) -> Integer
      def keyword_slots(kwargs)
        return 0 unless kwargs

        literal_keywords?(kwargs) ? kwargs.pairs.size / 2 : 1
      end
    end
  end
end
