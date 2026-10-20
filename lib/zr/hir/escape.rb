# frozen_string_literal: true

module Zr
  module Hir
    # Whether a block that is still on its creator's stack can serve every
    # use of a name in a scope. If so, a `&b` parameter makes no Proc cell
    # when it is bound (`Zr::Lower::Function::Params#raw_block?`).
    #
    # A stack block can serve these uses: the receiver of a plain `call`
    # (`b.call(x)`, `b&.call(x)`, with no block), the block of a send or a
    # super (`f(&b)`, `super(&b)`), and a presence test (`if b`, `b && x`,
    # `!b`, `while b`, and `b || x` if only the test is used). All other
    # uses keep the value (stored, returned, an argument, the receiver of
    # another method, a `case` subject, the left side of a `||` whose
    # value is used, overwritten, tested with `defined?`, interpolated),
    # so the parameter is a Proc from its binding. A read from a nested
    # block counts the same: a scope that escapes to a cell takes its
    # stack blocks with it (`zr_env_escape`). A def, class or module body
    # in the scope cannot see the name.
    #
    # Also whether a def only spreads its `*rest` or `**rest`: then an
    # empty one can be the one shared frozen Array or Hash
    # (`Zr::Lower::Function::Params#shared_rest?`).
    class Escape
      # @rbs @name: Symbol

      #: (untyped node, Symbol name) -> bool
      def self.raw_block?(node, name) = new(name).raw?(node, 0)

      # Whether `node` reads the rest parameter `name` only as `*name` or
      # `**name` among the arguments of a send, a super or a yield, or in
      # an Array or Hash literal. Each of these copies the elements into a
      # new Array or Hash (`Function#gather`, `zr_hash_coerce`), so the
      # rest itself never escapes. Nor does a primitive that reads only its
      # length (`LENGTHS`) keep it. `Primitive.x(*name)` passes the Array
      # itself, so it keeps the value, as every other use does.
      #: (untyped node, Symbol name) -> bool
      def self.spread_only?(node, name) = new(name).spread?(node, 0)

      # The calls of a Proc that run its block: a stack block serves each
      # (`Function#dispatch`, zr_opt_block_call).
      BLOCK_CALLS = %i[call [] yield ===].freeze

      # The anonymous `*`, `**` and `&` that `...` binds.
      FORWARDED = %i[* ** &].freeze

      # Whether `node` reads the anonymous `*`, `**` and `&` only in calls
      # that forward all three in place (`f(x, ...)`) in the def's own
      # scope, not in a block: then the def keeps its arguments where its
      # caller put them, and each such call passes them on from there
      # (`Zr::Lower::Function::Params#forwards?`).
      #: (untyped node) -> bool
      def self.forward_only?(node)
        case node
        when Local, Assign then !FORWARDED.include?(node.name) && (!node.is_a?(Assign) || forward_only?(node.value))
        when Send
          parts = forward_call?(node) ? [node.recv, *node.args[0...-1]] : node.to_a
          parts.all? { forward_only?(it) }
        when Def then forward_only?(node.receiver)
        when ClassDef then forward_only?(node.scope) && forward_only?(node.superclass)
        when ModuleDef then forward_only?(node.scope)
        when SingletonClassDef then forward_only?(node.target)
        when Node, Array then Hir.all_children?(node) { forward_only?(it) }
        else true
        end
      end

      # A call that forwards the anonymous `*`, `**` and `&` of its own
      # def's scope as its last arguments, its keywords and its block.
      #: (Send node) -> bool
      def self.forward_call?(node)
        rest = node.args.last
        kwargs = node.kwargs
        block = node.block
        return false if node.safe || !rest.is_a?(Splat) || !kwargs.is_a?(HashLit) || !block.is_a?(BlockPass)
        splat = kwargs.pairs.first
        return false unless kwargs.pairs.size == 2 && splat.is_a?(HashSplat)

        [[rest.value, :*], [splat.value, :**], [block.value, :&]].all? do |value, name|
          value.is_a?(Local) && value.name == name && value.depth.zero?
        end
      end

      #: (Symbol name) -> void
      def initialize(name)
        @name = name
      end

      # Whether `node` (`level` block scopes inside the parameter's scope)
      # uses the name only as a stack block, and never keeps its value.
      #: (untyped node, Integer level) -> bool
      def raw?(node, level)
        case node
        when Local then !mine?(node, level)
        when Assign then !mine?(node, level) && raw?(node.value, level)
        when Send then raw_send?(node, level)
        when Super then raw_block?(node.block, level) && raw?(node.args, level) && raw?(node.kwargs, level)
        when ZSuper then raw_block?(node.block, level)
        when If then tested?(node.cond, level) && raw?(node.yes, level) && raw?(node.no, level)
        when While then tested?(node.cond, level) && raw?(node.body, level)
        # `b && x` returns b only if b is nil.
        when And then tested?(node.left, level) && raw?(node.right, level)
        when Not then tested?(node.value, level)
        when Block then node.to_a.all? { |v| raw?(v, level + 1) }
        when Lambda then raw?(node.block, level)
        when Def then raw?(node.receiver, level)
        when ClassDef then raw?(node.scope, level) && raw?(node.superclass, level)
        when ModuleDef then raw?(node.scope, level)
        when SingletonClassDef then raw?(node.target, level)
        when Node, Array then Hir.all_children?(node) { |v| raw?(v, level) }
        else true
        end
      end

      # Whether `node` (`level` block scopes inside the parameter's scope)
      # reads the name only to spread it into a new collection.
      #: (untyped node, Integer level) -> bool
      def spread?(node, level)
        case node
        when Local then !mine?(node, level)
        when Assign then !mine?(node, level) && spread?(node.value, level)
        when Send then primitive?(node) ? primitive_spread?(node, level) : spread_send?(node, level)
        when Super then spread_parts?(node.args, level) && spread?(node.kwargs, level) && spread?(node.block, level)
        when Yield then spread_parts?(node.args, level) && spread?(node.kwargs, level)
        when ArrayLit then spread_parts?(node.elements, level)
        when HashLit then spread_parts?(node.pairs, level)
        when Block then node.to_a.all? { |v| spread?(v, level + 1) }
        when Lambda then spread?(node.block, level)
        when Def then spread?(node.receiver, level)
        when ClassDef then spread?(node.scope, level) && spread?(node.superclass, level)
        when ModuleDef then spread?(node.scope, level)
        when SingletonClassDef then spread?(node.target, level)
        when Node, Array then Hir.all_children?(node) { |v| spread?(v, level) }
        else true
        end
      end

      private

      # The arguments or elements `parts`, where `*name` and `**name` are
      # spreads.
      #: (Array[untyped] parts, Integer level) -> bool
      def spread_parts?(parts, level)
        parts.all? do |part|
          case part
          when Splat, HashSplat
            value = part.value
            (value.is_a?(Local) && mine?(value, level)) || spread?(value, level)
          else spread?(part, level)
          end
        end
      end

      #: (Send node, Integer level) -> bool
      def spread_send?(node, level)
        spread?(node.recv, level) && spread_parts?(node.args, level) && spread?(node.kwargs, level) && spread?(node.block, level)
      end

      # `Primitive.x(...)` in the core calls the kernel with the Values as
      # they are, so a splat there passes the rest itself.
      #: (Send node) -> bool
      def primitive?(node)
        recv = node.recv
        recv.is_a?(ConstRead) && recv.name == :Primitive && recv.scope.nil?
      end

      # The primitives that read only a collection's length, which an empty
      # shared one answers as a new one would.
      LENGTHS = %i[zr_ary_len_m zr_hash_len_m].freeze

      # `Primitive.arg!(:name)` reads the parameter by its name.
      #: (Send node, Integer level) -> bool
      def primitive_spread?(node, level)
        return false if node.name == :arg! && node.args.any? { |arg| arg.is_a?(Literal) && arg.value == @name }
        return true if LENGTHS.include?(node.name) && node.args.all? { |arg| arg.is_a?(Local) && mine?(arg, level) }

        Hir.all_children?(node) { |v| spread?(v, level) }
      end

      #: (Local | Assign local, Integer level) -> bool
      def mine?(local, level) = local.name == @name && local.depth == level

      #: (Send node, Integer level) -> bool
      def raw_send?(node, level)
        recv = node.recv
        own = if recv.is_a?(Local) && mine?(recv, level)
                BLOCK_CALLS.include?(node.name) && node.block.nil?
              else
                raw?(recv, level)
              end
        own && raw_block?(node.block, level) && raw?(node.args, level) && raw?(node.kwargs, level)
      end

      # A send's block: `&b` passed on, or any other expression in that
      # position.
      #: (block? block, Integer level) -> bool
      def raw_block?(block, level)
        return true if block.is_a?(BlockPass) && block.value.is_a?(Local) && mine?(block.value, level)

        raw?(block, level)
      end

      # `node` where only its truth value is used: the name can be bare,
      # alone or in `&&`, `||` and `!`.
      #: (untyped node, Integer level) -> bool
      def tested?(node, level)
        case node
        when Local then true
        when And, Or then tested?(node.left, level) && tested?(node.right, level)
        when Not then tested?(node.value, level)
        else raw?(node, level)
        end
      end
    end
  end
end
