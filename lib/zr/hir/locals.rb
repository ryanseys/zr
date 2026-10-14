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
      #: (untyped node) -> bool
      def holds_block?(node)
        case node
        when Send, Super
          node.block.is_a?(Block) || holds_block?(node.kwargs) || holds_block?(node.block) || node.args.any? { |a| holds_block?(a) } ||
            (node.is_a?(Send) && holds_block?(node.recv))
        when Lambda then true
        when Def then holds_block?(node.receiver)
        when ClassDef, ModuleDef, nil then false
        when SingletonClassDef then holds_block?(node.target)
        when Node, Array then Hir.any_child?(node) { |v| holds_block?(v) }
        else false
        end
      end

      # Whether a class or module body of this scope holds a block. A
      # `return` in that block leaves this scope (the body is no method),
      # so this scope's frame catches it.
      #: (untyped node) -> bool
      def body_holds_block?(node)
        case node
        when ClassDef, ModuleDef then holds_block?(node.body) || body_holds_block?(node.body)
        when Def, Lambda, Block, nil then false
        when Node, Array then Hir.any_child?(node) { |v| body_holds_block?(v) }
        else false
        end
      end

      # The sends that make a scope keep its locals in an Env: an eval
      # reads and writes them there, a Binding keeps them after the frame
      # is gone, and `local_variables` lists them.
      OPEN_FORMS = %i[eval binding local_variables].freeze

      # The sends that take a method name as their first argument, so
      # `send(:binding)` and `instance_method(:local_variables).bind_call`
      # open the scope as `binding` does.
      BY_NAME = %i[send __send__ public_send method public_method instance_method public_instance_method].freeze

      # Whether this scope's own body `node` calls one of those. The
      # receiver is ignored: `Kernel.binding` and `self.binding` open this
      # scope as the bare form does. A scope that contains a block already
      # has an Env, so this does not walk a block body; the block is
      # checked separately.
      #
      # With `computed`, a BY_NAME send whose name is not a literal opens
      # the scope too, since the name can be `binding`. The core passes
      # false: a core frame is a C frame to ruby, so `binding` raises
      # there and `local_variables` skips it (kernel/binding.rb).
      #: (untyped node, ?computed: bool) -> bool
      def opens_locals?(node, computed: true)
        case node
        when Send
          OPEN_FORMS.include?(node.name) || (STRING_EVALS.include?(node.name) && !node.args.empty?) ||
            named_open_form?(node, computed) || node.to_a.any? { |v| opens_locals?(v, computed:) }
        when Block, Lambda, ClassDef, ModuleDef, nil then false
        when Def then opens_locals?(node.receiver, computed:)
        when SingletonClassDef then opens_locals?(node.target, computed:)
        when Node, Array then Hir.any_child?(node) { |v| opens_locals?(v, computed:) }
        else false
        end
      end

      # The count of assignments that the body `node` makes to each local
      # of its scope, as a Hash with default zero. A block sees the scope's
      # locals one level further out. A def, class or module body is a
      # different scope, so only its expressions in this scope (a singleton
      # def's receiver, a superclass) are read.
      #: (untyped node, ?Integer level, ?Hash[Symbol, Integer] counts) -> Hash[Symbol, Integer]
      def assignments(node, level = 0, counts = Hash.new(0))
        case node
        when Assign
          counts[node.name] += 1 if node.depth == level
          assignments(node.value, level, counts)
        when Block then assignments([node.params, node.body], level + 1, counts)
        when Def then assignments(node.receiver, level, counts)
        when ClassDef then assignments([node.scope, node.superclass], level, counts)
        when ModuleDef then assignments(node.scope, level, counts)
        when SingletonClassDef then assignments(node.target, level, counts)
        when Node, Array then Hir.each_child(node) { |child| assignments(child, level, counts) }
        end
        counts
      end

      # Each outer local that the block `node`, or a block in it, reads or
      # writes: its name, its depth from the block, and whether it is
      # written, in the order of first use (`Lower::Function#capture`).
      #: (Block node) -> Array[[Symbol, Integer, bool]]
      def captures(node)
        found = {} #: Hash[Symbol, [Symbol, Integer, bool]]
        # @type var scan: ^(untyped, Integer) -> void
        scan = lambda do |n, nest|
          case n
          when Local, Assign
            depth = n.depth - nest
            if depth.positive?
              row = (found[n.name] ||= [n.name, depth, false])
              row[2] ||= n.is_a?(Assign)
            end
            scan.call(n.value, nest) if n.is_a?(Assign)
          when Block then scan.call([n.params, n.body], nest + 1)
          when Def then scan.call(n.receiver, nest)
          when ClassDef then scan.call([n.scope, n.superclass], nest)
          when ModuleDef then scan.call(n.scope, nest)
          when SingletonClassDef then scan.call(n.target, nest)
          when Node, Array then Hir.each_child(n) { |child| scan.call(child, nest) }
          end
        end
        scan.call([node.params, node.body], 0)
        found.values
      end

      # Whether the block `node`, or a block in it, uses `yield`. Ruby
      # counts the method's block as an outer variable of each block
      # between the `yield` and the method (access_outer_variables), so a
      # Ractor refuses to isolate any of them.
      #: (Block node) -> bool
      def yields?(node)
        # @type var scan: ^(untyped) -> bool
        scan = lambda do |n|
          case n
          when Yield then true
          when Def then scan.call(n.receiver)
          when ClassDef then scan.call([n.scope, n.superclass])
          when ModuleDef then scan.call(n.scope)
          when SingletonClassDef then scan.call(n.target)
          when Node, Array then Hir.any_child?(n) { |child| scan.call(child) }
          else false
          end
        end
        scan.call([node.params, node.body])
      end

      # `send(:binding)`, `send("binding")` and the rest of BY_NAME. A name
      # that is not a literal counts when `computed` is set.
      #: (Send node, bool computed) -> bool
      def named_open_form?(node, computed)
        return false unless BY_NAME.include?(node.name)

        first = node.args.first
        return computed && !first.nil? unless first.is_a?(Literal)

        name = first.value
        (name.is_a?(Symbol) || name.is_a?(String)) && OPEN_FORMS.include?(name.to_sym)
      end
    end
  end
end
