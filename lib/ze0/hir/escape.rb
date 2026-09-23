# frozen_string_literal: true

module Ze0
  module Hir
    # Whether every use a scope makes of a name is one a block still on
    # its maker's stack can serve, so a `&b` parameter need make no Proc
    # cell when it is bound (`Zr::Function::Params#raw_block?`).
    #
    # The uses a stack block serves: the receiver of a plain `call`
    # (`b.call(x)`, `b&.call(x)`, with no block of its own), the block
    # of a send or a super (`f(&b)`, `super(&b)`), and a test of whether
    # it is there (`if b`, `b && x`, `!b`, `while b`, and `b || x` where
    # only the test is taken). Anything else keeps the value -- stored,
    # returned, an argument, the receiver of any other method, a `case`
    # subject, the left of a `||` whose value is taken, written over,
    # asked `defined?`, interpolated -- and the parameter is a Proc from
    # its binding on. A read from a block nested in the scope counts
    # the same: a scope that escapes to a cell takes its stack blocks
    # with it (`zr_env_escape`). A def, class or module body inside the
    # scope cannot reach the name.
    class Escape
      def self.raw_block?(node, name) = new(name).raw?(node, 0)

      def initialize(name)
        @name = name
      end

      # Whether `node`, `level` block scopes inside the parameter's, uses
      # the name only as a stack block may be used, its value never taken.
      def raw?(node, level)
        case node
        when Local then !mine?(node, level)
        when Assign then !mine?(node, level) && raw?(node.value, level)
        when Send then raw_send?(node, level)
        when Super then raw_block?(node.block, level) && raw?(node.args, level) && raw?(node.kwargs, level)
        when ZSuper then raw_block?(node.block, level)
        when If then tested?(node.cond, level) && raw?(node.yes, level) && raw?(node.no, level)
        when While then tested?(node.cond, level) && raw?(node.body, level)
        # `b && x` answers b only where b is nil.
        when And then tested?(node.left, level) && raw?(node.right, level)
        when Not then tested?(node.value, level)
        when Block then node.to_a.all? { |v| raw?(v, level + 1) }
        when Lambda then raw?(node.block, level)
        when Def then raw?(node.receiver, level)
        when ClassDef then raw?(node.scope, level) && raw?(node.superclass, level)
        when ModuleDef then raw?(node.scope, level)
        when SingletonClassDef then raw?(node.target, level)
        when Record then node.to_a.all? { |v| raw?(v, level) }
        when Array then node.all? { |v| raw?(v, level) }
        else true
        end
      end

      private

      def mine?(local, level) = local.name == @name && local.depth == level

      def raw_send?(node, level)
        recv = node.recv
        own = if recv.is_a?(Local) && mine?(recv, level)
                node.name == :call && node.block.nil?
              else
                raw?(recv, level)
              end
        own && raw_block?(node.block, level) && raw?(node.args, level) && raw?(node.kwargs, level)
      end

      # A send's block: passed on as `&b`, or anything else the scope
      # wrote there.
      def raw_block?(block, level)
        return true if block.is_a?(BlockPass) && block.value.is_a?(Local) && mine?(block.value, level)

        raw?(block, level)
      end

      # `node` where only its truth is taken: the name may stand bare,
      # alone or under `&&`, `||` and `!`.
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
