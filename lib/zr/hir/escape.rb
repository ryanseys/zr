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
      # rest itself never escapes. `Primitive.x(*name)` passes the Array
      # itself, so it keeps the value, as every other use does.
      #: (untyped node, Symbol name) -> bool
      def self.spread_only?(node, name) = new(name).spread?(node, 0)

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

      # `Primitive.arg!(:name)` reads the parameter by its name.
      #: (Send node, Integer level) -> bool
      def primitive_spread?(node, level)
        return false if node.name == :arg! && node.args.any? { |arg| arg.is_a?(Literal) && arg.value == @name }

        Hir.all_children?(node) { |v| spread?(v, level) }
      end

      #: (Local | Assign local, Integer level) -> bool
      def mine?(local, level) = local.name == @name && local.depth == level

      #: (Send node, Integer level) -> bool
      def raw_send?(node, level)
        recv = node.recv
        own = if recv.is_a?(Local) && mine?(recv, level)
                node.name == :call && node.block.nil?
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
