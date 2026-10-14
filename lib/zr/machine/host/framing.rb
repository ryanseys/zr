# frozen_string_literal: true

# `Host`'s frames: which kernel defs need one, and the method that wraps each.

module Zr
  module Machine
    class Host
      private

      # Wraps the defs that need a frame: a def that takes a slot gives its
      # slots back when it returns, and a def that can run the collector
      # drops the pins of its body when it returns (and pins its Value
      # result for its caller). The collector runs with no pinning, and
      # marks the pins as kernel roots.
      #: (Array[Prism::ProgramNode] trees) -> void
      def frames(trees)
        all = trees.flat_map { |tree| statements(tree) }
        nodes = all.grep(Prism::DefNode) #: Array[Prism::DefNode]
        defs = nodes.to_h { |node| [node.name.to_s, node] }
        slots = defs.select { |_, node| node.slice.include?("Machine.slot(") }.keys.to_set
        collects = collecting_defs(defs)
        # In the methods below, self is the kernel, so they read `host`.
        host = self #: Host
        frames = Module.new
        (slots | collects).each do |name|
          rooted = collects.include?(name) && loops?(defs.fetch(name))
          sig = @sigs[name]
          none = [] #: Array[Integer]
          params = collects.include?(name) && !rooted && sig ? sig.first.each_index.select { |i| sig.first.fetch(i).name == "Value" } : none
          frame = Framing.new(slots.include?(name), collects.include?(name), sig&.last&.name == "Value", rooted, params)
          # The Proc takes the def's arguments; RBS types it as one with none.
          frames.define_method(name, framed_def(@kern.instance_method(name).arity, frame)) # steep:ignore ArgumentTypeMismatch
          @rooted[name] = value_locals(defs.fetch(name)).freeze if rooted
        end
        @kern.prepend(frames)
        collector = Module.new
        # `super` is the kernel's own def, which Steep cannot see.
        if defs.key?("zr_collect_kind")
          collector.define_method(:zr_collect_kind) do |*args|
            host.collecting { super(*args) } # steep:ignore UnexpectedSuper
          end
        end
        if defs.key?("zr_mark_kernel_roots")
          collector.define_method(:zr_mark_kernel_roots) do
            super() # steep:ignore UnexpectedSuper
            host.mark_pins
          end
        end
        @kern.prepend(collector)
      end

      # What a def's frame does (`frames`): it gives back the slots of its
      # body (`restores`), and drops the pins of its body (`drops`), then
      # pins a Value result (`value`) for its caller.
      #
      # A def that can collect and loops is `rooted`: a pin of each pass
      # would stay until it returns, so its locals are its roots instead,
      # as the lowering's root frame holds a def's Value locals. The
      # collector reads those locals (`value_locals`) from the def's frame
      # on the Ruby stack (`live_roots`).
      #
      # A rooted caller pins nothing, so a def that can collect and is not
      # rooted pins its Value arguments (`params`, their indices), as the
      # lowering's root frame holds a def's parameters.
      # @rbs skip
      Framing = Data.define(:restores, :drops, :value, :roots, :params)

      # The locals of the def `node` that hold Values, as the typed lowering
      # gives them root slots: each Value parameter, and each local that an
      # assignment gives a Value. A local is a Value when one of its
      # assignments is one, or is of a type this cannot tell, so no Value
      # goes unmarked. A Ptr or a Word is never marked: it can point into a
      # payload, or at a cell that is not yet an object.
      #: (Prism::DefNode node) -> Array[Symbol]
      def value_locals(node)
        d = @unit.declared_defs[node.name.to_s]
        types = {} #: Hash[Symbol, String?]
        (node.parameters&.requireds || []).each_with_index do |param, i|
          raise ArgumentError, "a machine def takes required parameters only" unless param.is_a?(Prism::RequiredParameterNode)

          types[param.name] = d ? d.params.fetch(i).last : "Value"
        end
        assigns = {} #: Hash[Symbol, Array[Prism::node]]
        queue = [node.body].compact #: Array[Prism::node]
        while (n = queue.shift)
          (assigns[n.name] ||= []) << n.value if n.is_a?(Prism::LocalVariableWriteNode)
          queue.concat(n.compact_child_nodes)
        end
        assigns.each_key { |name| types[name] ||= "Word" }
        loop do
          grown = assigns.select do |name, values|
            types[name] != "Value" && values.any? { |value| type_of(value, types).then { |type| type.nil? || type == "Value" } }
          end
          break if grown.empty?

          grown.each_key { |name| types[name] = "Value" }
        end
        types.filter_map { |name, type| name if type == "Value" }
      end

      # The type name of the kernel expression `node`, or nil when this
      # cannot tell (`value_locals`).
      #: (Prism::node? node, Hash[Symbol, String?] types) -> String?
      def type_of(node, types)
        case node
        when Prism::LocalVariableReadNode then types[node.name]
        when Prism::IntegerNode, Prism::TrueNode, Prism::FalseNode, Prism::NilNode, Prism::ConstantReadNode then "Word"
        when Prism::ParenthesesNode, Prism::StatementsNode then type_of(last_of(node), types)
        when Prism::IfNode, Prism::UnlessNode, Prism::AndNode, Prism::OrNode
          kinds = branches(node).map { |branch| branch ? type_of(branch, types) : "Word" }
          if kinds.include?("Value") then "Value"
          elsif kinds.include?(nil) then nil
          else "Word"
          end
        when Prism::CallNode then call_type(node, types)
        end
      end

      #: (Prism::node? node) -> Prism::node?
      def last_of(node)
        case node
        when Prism::ParenthesesNode then last_of(node.body)
        when Prism::StatementsNode then node.body.last
        else node
        end
      end

      # The values that a conditional answers; nil for a missing branch.
      #: (Prism::IfNode | Prism::UnlessNode | Prism::AndNode | Prism::OrNode node) -> Array[Prism::node?]
      def branches(node)
        case node
        when Prism::AndNode, Prism::OrNode then [node.left, node.right]
        when Prism::IfNode
          other = node.subsequent
          [node.statements, other.is_a?(Prism::ElseNode) ? other.statements : other]
        else [node.statements, node.else_clause&.statements]
        end
      end

      # The type of a call: a def's type, `Machine.value`, a field of a
      # view, a view (`Name[p]`), or a signature's `call`. An operator on words
      # is a word.
      #: (Prism::CallNode node, Hash[Symbol, String?] types) -> String?
      def call_type(node, types)
        recv = node.receiver
        return @unit.declared_defs[node.name.to_s]&.ret if recv.nil?
        if (layout = view_of(recv, types))
          type = layout.fields[node.name.to_s]&.last
          return type == "Value" || @unit.struct_for(type.to_s) ? type : "Word"
        end
        return recv.name.to_s if node.name == :[] && recv.is_a?(Prism::ConstantReadNode) && @unit.struct_for(recv.name.to_s)
        return "Word" unless recv.is_a?(Prism::ConstantReadNode)
        return node.name == :value ? "Value" : "Word" if recv.name == :Machine
        return "Word" if recv.name == :Libc

        @unit.declared_sigs[recv.name.to_s]&.ret
      end

      # The layout of the view that `node` is: `Name[p]`, a local that
      # holds a view, or a field of a layout type of a view. Nil for
      # anything else.
      #: (Prism::node? node, Hash[Symbol, String?] types) -> Machine::Layout?
      def view_of(node, types)
        name = case node
               when Prism::LocalVariableReadNode then types[node.name]
               when Prism::CallNode
                 if node.name == :[] && (receiver = node.receiver).is_a?(Prism::ConstantReadNode)
                   receiver.name.to_s
                 elsif (outer = view_of(node.receiver, types))
                   outer.fields[node.name.to_s]&.last
                 end
               end
        @unit.struct_for(name) if name && !TYPES.key?(name)
      end

      # Whether the def `node` has a loop.
      #: (Prism::DefNode node) -> bool
      def loops?(node)
        queue = [node.body].compact #: Array[Prism::node]
        while (n = queue.shift)
          return true if n.is_a?(Prism::WhileNode) || n.is_a?(Prism::UntilNode)

          queue.concat(n.compact_child_nodes)
        end
        false
      end

      # The method body that wraps a def of `arity` in its `frame`. Each
      # arity has its own block, which passes the def's arguments on to
      # `super` as they are: a block that takes `*args` makes an Array at
      # each call. In the frame, it pins the arguments that `frame.params`
      # names (`p0`..`p5`, each true or false).
      #
      # Each `super` is the kernel's own def, which Steep cannot see.
      #: (Integer arity, Framing frame) -> Proc
      def framed_def(arity, frame)
        host = self #: Host
        p0, p1, p2, p3, p4, p5 = Array.new(6) { |i| frame.params.include?(i) }
        case arity
        when 0 then proc { host.framed(frame) { super() } } # steep:ignore UnexpectedSuper
        when 1
          proc do |a|
            host.framed(frame) do
              host.pin(a) if p0
              super(a) # steep:ignore UnexpectedSuper
            end
          end
        when 2
          proc do |a, b|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              super(a, b) # steep:ignore UnexpectedSuper
            end
          end
        when 3
          proc do |a, b, c|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              super(a, b, c) # steep:ignore UnexpectedSuper
            end
          end
        when 4
          proc do |a, b, c, d|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              super(a, b, c, d) # steep:ignore UnexpectedSuper
            end
          end
        when 5
          proc do |a, b, c, d, e|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              host.pin(e) if p4
              super(a, b, c, d, e) # steep:ignore UnexpectedSuper
            end
          end
        when 6
          proc do |a, b, c, d, e, g|
            host.framed(frame) do
              host.pin(a) if p0
              host.pin(b) if p1
              host.pin(c) if p2
              host.pin(d) if p3
              host.pin(e) if p4
              host.pin(g) if p5
              super(a, b, c, d, e, g) # steep:ignore UnexpectedSuper
            end
          end
        else
          proc do |*args|
            host.framed(frame) do
              frame.params.each { |i| host.pin(args[i]) }
              super(*args) # steep:ignore UnexpectedSuper
            end
          end
        end
      end

      # The defs that can run the collector, as the lowering finds them
      # (`Lower#collecting_defs`): those that `collects` names, a call
      # through a pointer, and each def that calls one of those.
      #: (Hash[String, Prism::DefNode] defs) -> Set[String]
      def collecting_defs(defs)
        signatures = @unit.declared_sigs.each_key.to_set(&:to_sym)
        calls = defs.transform_values { |node| calls_in(node.body, defs, signatures) }
        set = Set.new(@collectors) #: Set[String | Symbol]
        set << :indirect
        loop do
          grown = defs.each_key.select { |name| !set.include?(name) && calls.fetch(name).any? { |c| set.include?(c) } }
          break if grown.empty?

          set.merge(grown)
        end
        # A collector that is not a def here (a raw function, which the
        # arch layer gives) makes its callers collect, but has no frame.
        set.select { |name| defs.key?(name) }.to_set #: Set[String]
      end

      #: (Prism::node? node, Hash[String, Prism::DefNode] defs, Set[Symbol] signatures) -> Array[String | Symbol]
      def calls_in(node, defs, signatures)
        found = [] #: Array[String | Symbol]
        queue = [node].compact #: Array[Prism::node]
        while (n = queue.shift)
          if n.is_a?(Prism::CallNode)
            found << n.name.to_s if n.receiver.nil? && (defs.key?(n.name.to_s) || @collectors.include?(n.name.to_s))
            receiver = n.receiver
            found << :indirect if n.name == :call && receiver.is_a?(Prism::ConstantReadNode) && signatures.include?(receiver.name)
          end
          queue.concat(n.compact_child_nodes)
        end
        found
      end
    end
  end
end
