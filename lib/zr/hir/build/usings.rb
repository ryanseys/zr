# frozen_string_literal: true

# `Hir::Build`'s `using` entries: the activation that each `using` makes,
# and the entry that each send, def and block keeps.

module Zr
  module Hir
    class Build
      # `out`, a statement that made `using` entries below its top level
      # (which a condition can skip), after their defaults: each entry has
      # the contents of its `from` until its `using` runs. A statement
      # that is itself a `using`, or that holds none, stays as it is.
      #: (node out, Integer line) -> node
      def with_using_defaults(out, line)
        return out if out.is_a?(Using)

        nested = usings_in(out, Hash.new.compare_by_identity).sort_by(&:id)
        return out if nested.empty?

        Seq.new([UsingDefaults.new(nested.map { |u| [u.id, u.from] }, line), out], line)
      end

      # The `using` entries in a statement, below its top level, which a
      # condition can skip.
      # `seen` holds each node that the walk visited, by identity.
      #: (untyped node, Hash[untyped, bool] seen, ?Array[Using] out) -> Array[Using]
      def usings_in(node, seen, out = [])
        return out if seen.key?(node)

        if node.is_a?(Node)
          seen[node] = true
          out << node if node.is_a?(Using)
        end
        Hir.each_child(node) { |child| usings_in(child, seen, out) }
        out
      end

      # `using mod` where ruby permits it: at toplevel or in a class or
      # module body, never in a method, and never as a send whose value
      # is used.
      #: (Prism::node node) -> Using?
      def using_activation(node)
        return nil if @in_method_body
        return nil unless node.is_a?(Prism::CallNode) && node.name == :using && node.block.nil?
        return nil unless node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

        args = node.arguments&.arguments
        return nil unless args && args.size == 1 && !args[0].is_a?(Prism::SplatNode)

        value = expr(args[0])
        from = @using.is_a?(Integer) ? @using : -1
        @using = @loader ? @loader.next_activation : (@activations += 1)
        @usings += 1
        Using.new(@using, from, value, node.location.start_line)
      end

      # `x = using mod` and `X = using mod`: the activation, whose value
      # (self) the local or the constant gets.
      #: (Prism::node node) -> (Assign | ConstWrite)?
      def assigned_using(node)
        return nil unless node.is_a?(Prism::LocalVariableWriteNode) || node.is_a?(Prism::ConstantWriteNode)

        activation = using_activation(node.value) or return nil
        line = node.location.start_line
        return ConstWrite.new(nil, node.name, activation, line) if node.is_a?(Prism::ConstantWriteNode)

        Assign.new(node.name, node.depth, activation, line)
      end

      # The activation entry in force here, for a def or block that keeps it
      # (Def#using, Block#using). A `refine` block's list is its owner's,
      # which the runtime finds from the method's owner.
      #: () -> Integer?
      def entry_using = (using = @using).is_a?(Integer) ? using : nil

      # Gives each send, super, operator write and `case` in `node` that
      # has no activation the one in force (`@using`).
      # `seen` holds each node that the walk visited, by identity.
      #: (untyped node, Hash[untyped, bool] seen) -> void
      def mark_using(node, seen)
        return if seen.key?(node)

        if node.is_a?(Node)
          seen[node] = true
          case node
          when Send, Super, AttrOpAssign, IndexOpAssign, Case then node.using ||= @using
          end
        end
        Hir.each_child(node) { |child| mark_using(child, seen) }
      end
    end
  end
end
