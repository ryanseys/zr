# frozen_string_literal: true

require_relative "../prism"
require_relative "../ir"
require_relative "../refused"
require_relative "../paths"
require_relative "description"

module Zr
  module Machine
    # Lowers one machine def to one IR function. A def that can run the
    # collector keeps a root frame in its frame: `prev, n, values...`.
    # The root frame links from the static head of the unit and contains
    # each Value of the def (a parameter, a local, or the result of a call
    # that goes to another call). Thus a collection in any call sees them all.
    #
    # An expression lowers to `[value, type]`: an IR value name and a
    # Machine type name. The value is nil when the type is "Void". The
    # lowering tests the type, not the value, so a value is untyped here.
    class Function
      # @rbs @unit: Lower
      # @rbs @d: Def
      # @rbs @f: IR::Function
      # @rbs @locals: Hash[String, { type: String, addr: String }]
      # @rbs @loops: Array[String]
      # @rbs @roots: Roots?
      # @rbs @head: String
      # @rbs @inlining: Array[String]
      # @rbs @exit: Exit?
      # @rbs @stack_images: Hash[Def, Set[Symbol]]?

      # The root frame of a def: its stack `slot` and the `addr` of it, the
      # number `n` of Value slots made so far, a zero constant `zero`, the
      # constant instruction `count` that holds the slot count, and the
      # index `fill_at` in the entry block where the zero fill goes.
      # @rbs skip -- typed in sig/zr/machine/function.rbs
      Roots = Struct.new(:slot, :addr, :n, :zero, :count, :fill_at, keyword_init: true)

      # The exit of an inlined body: the `type` of its def, the `block`
      # after the body (nil until the first `return`), and the `value`, the
      # parameter of that block.
      # @rbs skip -- typed in sig/zr/machine/function.rbs
      Exit = Struct.new(:type, :block, :value, keyword_init: true)

      #: (Lower unit, Def d) -> void
      def initialize(unit, d)
        @unit = unit
        @d = d
        @f = IR::Function.new(d.name, d.params.map { |_, t| ir_type(t) }, ir_type(d.ret))
        @locals = {}
        @loops = []
        @roots = nil
        @inlining = [d.name]
        # The target of a `return` in an inlined body: the block after
        # the body, made by the first `return`. Nil in the def's own body.
        @exit = nil
      end

      #: () -> IR::Function
      def lower
        enter_roots if @unit.collects?(@d.name)
        @d.params.each_with_index do |(name, type), i|
          local = declare_local(@d.node, name, type)
          @f.store(@f.args[i], local[:addr])
        end
        body = def_body(@d)
        value, type = body ? statements(body, @d.ret) : [nil, "Void"]
        unless @f.terminated?
          refuse(@d.node, "the body ends in #{type}, and the def's type says #{@d.ret}") unless @d.ret == "Void" || fits?(@d.ret, type)
          ret(@d.ret == "Void" ? nil : value)
        end
        leave_roots if @roots
        IR::Mem2Reg.run(@f)
      end

      # Links in the root frame before the body. `leave_roots` sets the
      # slot count and the zero fill after the body has made all slots.
      #: () -> void
      def enter_roots
        # @type ivar @roots: Roots
        slot = @f.slot(16)
        @roots = Roots.new(slot: slot, addr: @f.stack_addr(slot), n: 0, zero: @f.iconst("i64", 0))
        @head = @f.symbol_value(@f.symbol("zr_static_#{Lower::ROOTS}"))
        @f.store(@f.fetch("i64", @head), @roots.addr, 0)
        count, @roots.count = @f.iconst_later("i64")
        @f.store(count, @roots.addr, 8)
        @f.store(@roots.addr, @head, 0)
        @roots.fill_at = @f.entry_block.insts.size
      end

      #: () -> void
      def leave_roots
        # @type ivar @roots: Roots
        n = @roots.n
        @roots.count.args[0] = n
        @f.slots[@roots.slot.delete_prefix("ss").to_i].bytes = 16 + (8 * n)
        fill = (0...n).map { |i| IR::Inst.new(:store, args: [@roots.zero, @roots.addr], offset: 16 + (8 * i), flags: "notrap aligned") }
        @f.entry_block.insts.insert(@roots.fill_at, *fill)
      end

      # The offset of a new root slot.
      #: () -> Integer
      def root_slot
        # @type ivar @roots: Roots
        at = 16 + (8 * @roots.n)
        @roots.n += 1
        at
      end

      # `return`: first unlinks the root frame. In an inlined body, a
      # return is a jump with the value to the block after the body,
      # because a `ret` there would return from the caller.
      #: (untyped value) -> void
      def ret(value)
        # @type ivar @roots: Roots
        return @f.jump(inline_exit, [value].compact) if @exit

        @f.store(@f.fetch("i64", @roots.addr), @head, 0) if @roots
        @f.ret(value)
      end

      # The block that all returns of an inlined body jump to. Its
      # parameter is the returned value.
      #: () -> String
      def inline_exit
        # @type ivar @exit: Exit
        @exit.block ||= begin
          block, params = @exit.type == "Void" ? @f.block : @f.block([ir_type(@exit.type)])
          @exit.value = params.first
          block
        end
      end

      private

      #: (Prism::node? node, String message) -> bot
      def refuse(node, message)
        raise Refused.new(node, message, @unit.unit? ? @d.file : nil)
      end

      # The statements of a def. A body with `rescue` or `ensure` is a
      # BeginNode, and the kernel subset does not have them.
      #: (Def d) -> Prism::StatementsNode?
      def def_body(d)
        body = d.node.body
        refuse(body, "rescue and ensure are not in the kernel subset") if body.is_a?(Prism::BeginNode)
        body
      end

      # A local is in a slot of its own. A Value in a rooted function is
      # in the root frame.
      #: (Prism::node node, String name, String type) -> { type: String, addr: String }
      def declare_local(node, name, type)
        refuse(node, "#{name} is already a #{@locals[name][:type]}") if @locals.key?(name) && !fits?(@locals[name][:type], type)
        @locals[name] ||= { type: type, addr: local_addr(type) }
      end

      #: (String type) -> String
      def local_addr(type)
        # @type ivar @roots: Roots
        return @f.stack_addr(@f.slot(8)) unless @roots && type == "Value"

        at = root_slot
        off = @f.iconst("i64", at)
        @f.hoisted(:root_slot, at) { IR::Inst.new(:iadd, type: "i64", args: [@roots.addr, off]) }
      end

      # The IR type of a Machine type, or nil for Void. The type says
      # String: a caller refuses Void first, or gives the nil to an IR
      # call that reads it as "no type". A view of a layout (`IvTab`) is
      # an address.
      #: (String type) -> String
      def ir_type(type)
        return TYPES.fetch(type) if TYPES.key?(type) # steep:ignore ReturnTypeMismatch
        return "i64" if @unit.struct_for(type)

        refuse(@d.node, "#{type} is not a kernel type or a layout")
      end

      # The layout of a view type (`RArray[p]` is an `RArray`), or nil.
      #: (String type) -> Layout?
      def view(type) = TYPES.key?(type) ? nil : @unit.struct_for(type)

      # The value and type of a statement list: those of the last
      # statement. `want` applies only to the last statement.
      #: (Prism::StatementsNode node, ?String? want) -> [untyped, String]
      def statements(node, want = nil)
        last = [nil, "Void"] #: [untyped, String]
        node.body.each_with_index do |s, i|
          last = expr(s, i == node.body.size - 1 ? want : nil)
          break if @f.terminated?
        end
        last
      end

      # Returns `[value, type]`. `want` gives the type of a literal here.
      #: (Prism::node? node, ?String? want) -> [untyped, String]
      def expr(node, want = nil)
        case node
        when Prism::StatementsNode then statements(node, want)
        when Prism::ParenthesesNode then node.body ? expr(node.body, want) : [nil, "Void"]
        when Prism::IntegerNode
          # A Word is signed (A6), so on CRuby a bare literal at or above
          # 2**63 is not the word it is here.
          if node.value >= 1 << 63 && want != "Ptr"
            refuse(node, "a literal at or above 2**63 is a word only as Machine.word(literal)")
          end
          literal(node, node.value, want)
        when Prism::ConstantReadNode
          value = @unit.const_for(node.name.to_s) or refuse(node, "#{node.name} is not a constant here")
          literal(node, value, want)
        when Prism::AndNode then logical(node, :and)
        when Prism::OrNode then logical(node, :or)
        when Prism::TrueNode then [@f.iconst("i8", 1), "Bool"]
        when Prism::FalseNode then [@f.iconst("i8", 0), "Bool"]
        when Prism::NilNode then [nil, "Void"]
        when Prism::LocalVariableReadNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          [@f.fetch(ir_type(local[:type]), local[:addr]), local[:type]]
        when Prism::LocalVariableWriteNode
          value, type = expr(node.value, @locals.dig(node.name.to_s, :type))
          refuse(node, "#{node.name} is assigned nothing") if type == "Void"
          local = declare_local(node, node.name.to_s, type)
          @f.store(value, local[:addr])
          [value, type]
        when Prism::LocalVariableOperatorWriteNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          current = @f.fetch(ir_type(local[:type]), local[:addr])
          rhs, = expr(node.value, local[:type])
          value, type = binary(node, node.binary_operator, current, local[:type], rhs, local[:type])
          @f.store(value, local[:addr])
          [value, type]
        when Prism::CallNode then call(node, want)
        when Prism::IfNode
          branch(node, want, node.statements, node.subsequent.is_a?(Prism::ElseNode) ? node.subsequent.statements : node.subsequent)
        when Prism::UnlessNode then branch(node, want, node.else_clause&.statements, node.statements)
        when Prism::WhileNode then loop_while(node)
        when Prism::BreakNode
          refuse(node, "a break outside a while") if @loops.empty?
          refuse(node, "a break with a value") if node.arguments
          @f.jump(@loops.last)
          [nil, "Void"]
        when Prism::ReturnNode
          value, type = node.arguments ? expr(node.arguments.arguments.first, @d.ret) : [nil, "Void"]
          refuse(node, "a return of #{type} from a def whose type says #{@d.ret}") unless fits?(@d.ret, type)
          ret(type == "Void" ? nil : value)
          [nil, "Void"]
        else
          refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not in the kernel subset")
        end
      end

      # A size or an offset: an integer, a constant, or an operator over
      # those, folded at compile time.
      #: (Prism::node? node) -> Integer
      def immediate(node)
        @unit.fold_in(@d.file, node)
      end

      # An integer literal or a constant gets the type in `want`.
      #: (Prism::node node, Integer n, String? want) -> [String, String]
      def literal(node, n, want)
        type = want || "Word"
        refuse(node, "an integer where a #{type} is wanted") if ir_type(type).nil? || ir_type(type) == "f64"
        [@f.iconst(ir_type(type), n), type]
      end

      #: (Prism::CallNode node, String? want) -> [untyped, String]
      def call(node, want)
        args = node.arguments&.arguments || []
        if node.receiver.nil?
          target(node, node.name.to_s, args, imports: false)
        elsif @unit.libc?(node.receiver)
          import = @unit.import_for(node.name.to_s)
          refuse(node, "#{node.name} is not a Libc.import here") unless import.is_a?(Import)
          target(node, node.name.to_s, args)
        elsif @unit.machine?(node.receiver)
          intrinsic(node, args, want)
        elsif node.name == :call && node.receiver.is_a?(Prism::ConstantReadNode) && !@unit.sig_read?(node.receiver)
          refuse(node, "#{node.receiver.name} is not a `fn` signature here")
        elsif (receiver = node.receiver).is_a?(Prism::ConstantReadNode) && @unit.sig_read?(receiver)
          refuse(node, "a signature takes `call`") unless node.name == :call
          indirect(node, @unit.sig_for(receiver.name.to_s), args[0], args.drop(1))
        elsif node.name == :! && args.empty?
          value, type = condition_value(node.receiver)
          [@f.icmp("eq", value, @f.iconst(ir_type(type), 0)), "Bool"]
        elsif node.name == :-@ && args.empty?
          value, type = expr(node.receiver, want)
          return [@f.funop(:fneg, value), type] if type == "F64"

          refuse(node, "a negation of a #{type}") unless ir_type(type)
          [@f.isub(@f.iconst(ir_type(type), 0), value), type]
        elsif node.name == :[] && node.receiver.is_a?(Prism::ConstantReadNode) && (layout = @unit.struct_for(node.receiver.name.to_s))
          refuse(node, "#{layout.name}[p] takes one pointer") unless args.one?
          ptr, pt = expr(args[0])
          refuse(args[0], "#{layout.name}[p] of a #{pt}") unless %w[Ptr Word Value].include?(pt) || view(pt)
          [ptr, layout.name]
        elsif node.receiver.is_a?(Prism::ConstantReadNode) && (layout = @unit.struct_for(node.receiver.name.to_s))
          field(node, layout, args, want)
        elsif (receiver = node.receiver) && !OPERATORS.key?(node.name) && args.size <= 1
          view_field(node, receiver, args)
        elsif args.size == 1 && OPERATORS.key?(node.name)
          lhs, lt = expr(node.receiver, want)
          rhs, rt = expr(args.first, lt)
          binary(node, node.name, lhs, lt, rhs, rt)
        else
          refuse(node, "a call with a receiver that is not Machine or a struct")
        end
      end

      # `Name.size`, `Name.field(p)` and `Name.set_field(p, v)`. For a
      # field of a struct type, `Name.field(p)` returns its address.
      #: (Prism::CallNode node, Layout layout, Array[Prism::node] args, String? want) -> [untyped, String]
      def field(node, layout, args, want)
        name = node.name.to_s
        return literal(node, layout.size, want) if name == "size" && args.empty?

        writer = name.start_with?("set_")
        fname = writer ? name.delete_prefix("set_") : name
        layout.fields.fetch(fname) { refuse(node, "#{layout.name} has no field #{fname}") }
        refuse(node, "#{layout.name}.#{name} takes #{writer ? "a pointer and a value" : "a pointer"}") if args.size != (writer ? 2 : 1)
        ptr, pt = expr(args[0])
        refuse(args[0], "#{layout.name}.#{name} of a #{pt}") unless %w[Ptr Word Value].include?(pt) || view(pt)
        access(node, layout, fname, ptr, args[0], writer ? args[1] : nil, view: false)
      end

      # `view.field` and `view.field = value`, where `view` is `Name[p]`
      # or a local, a parameter or a field that holds a view.
      #: (Prism::CallNode node, Prism::node receiver, Array[Prism::node] args) -> [untyped, String]
      def view_field(node, receiver, args)
        ptr, pt = expr(receiver)
        layout = view(pt) or refuse(node, "a call with a receiver that is not Machine or a struct")
        name = node.name.to_s
        writer = name.end_with?("=")
        refuse(node, "#{layout.name}##{name} takes #{writer ? "a value" : "nothing"}") if args.size != (writer ? 1 : 0)
        at = receiver.is_a?(Prism::CallNode) && receiver.name == :[] ? receiver.arguments&.arguments&.first : receiver
        access(node, layout, writer ? name.chomp("=") : name, ptr, at, args.first, view: true)
      end

      # A read or a write of the field `fname` of `layout` at `ptr`. A
      # field of a layout type is read as its address, which is a view of
      # that layout when `view` is set (`RObject[o].iv` is an IvTab).
      # `at` is the node of the address, for the write barrier.
      #: (Prism::CallNode node, Layout layout, String fname, String ptr, Prism::node? at, Prism::node? value_node, view: bool) -> [untyped, String]
      def access(node, layout, fname, ptr, at, value_node, view:)
        off, type = layout.fields.fetch(fname) { refuse(node, "#{layout.name} has no field #{fname}") }
        if @unit.struct_for(type)
          refuse(node, "#{fname} is a #{type}; set its fields instead") if value_node
          [off.zero? ? ptr : @f.iadd(ptr, @f.iconst("i64", off)), view ? type : "Ptr"]
        elsif value_node
          value, vt = expr(value_node, type)
          refuse(value_node, "#{layout.name}.#{fname} is a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          region = cell?(layout) ? :heap : :malloc
          @f.store(value, ptr, off, region: region)
          barrier(ptr, value) if type == "Value" && cell?(layout) && !stack_image?(at)
          [nil, "Void"]
        else
          [@f.fetch(ir_type(type), ptr, off, region: cell?(layout) ? :heap : :malloc), type]
        end
      end

      # Whether `node` reads a local that only ever holds the address of a
      # slot of this frame (`stack_images`). A cell image there, such as
      # the Proc that a define_method call builds, has FL_STACK, so it is
      # never old and the write barrier would do nothing.
      #: (Prism::node? node) -> bool
      def stack_image?(node)
        node.is_a?(Prism::LocalVariableReadNode) && stack_images(@d).include?(node.name)
      end

      # The locals of `d` whose every assignment is `Machine.slot(n)`, or
      # `Machine.value(x)` or `Machine.ptr(x)` of another such local. A
      # parameter, or a local with any other kind of write, is not one.
      #: (Def d) -> Set[Symbol]
      def stack_images(d)
        images = @stack_images ||= begin
          fresh = {} #: Hash[Def, Set[Symbol]]
          fresh.compare_by_identity
        end
        images[d] ||= begin
          writes = {} #: Hash[Symbol, Array[Prism::node]]
          other = Set.new(d.params.map { |name, _| name.to_sym })
          local_writes(d.node.body, writes, other) if d.node.body
          names = Set.new(writes.keys) - other
          while (kept = names.select { |name| writes.fetch(name).all? { |v| slot_address?(v, names) } }.to_set) != names
            names = kept
          end
          names
        end
      end

      # Adds each write of a local under `n` to `writes`, and the name of a
      # local with any other kind of write to `other`.
      #: (Prism::node n, Hash[Symbol, Array[Prism::node]] writes, Set[Symbol] other) -> void
      def local_writes(n, writes, other)
        case n
        when Prism::LocalVariableWriteNode then (writes[n.name] ||= []) << n.value
        when Prism::LocalVariableTargetNode, Prism::LocalVariableOperatorWriteNode,
             Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode then other << n.name
        end
        n.compact_child_nodes.each { |c| local_writes(c, writes, other) }
      end

      #: (Prism::node node, Set[Symbol] names) -> bool
      def slot_address?(node, names)
        return false unless node.is_a?(Prism::CallNode) && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Machine
        return true if node.name == :slot

        args = node.arguments&.arguments || []
        %i[value ptr].include?(node.name) && args.size == 1 && args[0].is_a?(Prism::LocalVariableReadNode) &&
          names.include?(args[0].name)
      end

      # Whether a store into a field of `layout` is a store into a cell.
      # Only a cell starts with an RBasic header, so the type of the
      # first field tells. RBasic is the header itself, and a write to its
      # `klass` is a write to the cell that contains it.
      #: (Layout layout) -> bool
      def cell?(layout)
        layout.name == "RBasic" || layout.fields.first&.last&.last == "RBasic"
      end

      # Emits the collector's write barrier after the kernel stores a
      # Value into a cell (Part 2.1 of the collector plan). CRuby writes
      # `RB_OBJ_WRITE` by hand at each such store in C, and has a second
      # collector to find the missing ones. Here the compiler emits the
      # store, so it also emits the barrier. `zr_write_barrier` is
      # `Machine.inline`, so the barrier is the four instructions of its
      # fast path and not a call.
      #: (String owner, String value) -> void
      def barrier(owner, value)
        callee = @unit.def_for("zr_write_barrier") or return
        return if @inlining.include?(callee.name) || immediate?(value)

        inline(callee, [owner, value])
      end

      # Whether the compiler knows that `value` is an immediate, so the
      # test in the barrier fails. The kernel stores QNIL into a Value
      # field more frequently than any other value.
      #: (String value) -> bool
      def immediate?(value)
        word = @f.iconst_of(value)
        !word.nil? && @unit.immediate?(word)
      end

      # `a && b` and `a || b` as a Bool value. The right side runs only
      # when the left side does not decide the result. As the test of an
      # `if` or a `while`, `jump_if` lowers it, and it makes no value.
      #
      # A right side that is `plain?` always runs, and the two bits join
      # with no branch. It cannot change memory or fault, so an extra read
      # is not visible. This is for `zr_special_p`: it is three such tests,
      # and the collector calls it for each reference. As a diamond of
      # blocks, each test cost a compare, two sets, three widenings and
      # a branch.
      #: (Prism::AndNode | Prism::OrNode node, :and | :or op) -> [String, String]
      def logical(node, op)
        bit = truth(*condition_value(node.left))
        if plain?(node.right)
          other = truth(*condition_value(node.right))
          return [@f.binop(op == :and ? :band : :bor, bit, other), "Bool"]
        end

        rest = @f.label
        skip = @f.label
        merge, params = @f.block(["i8"])
        op == :and ? @f.brif(bit, rest, skip) : @f.brif(bit, skip, rest)
        @f.switch(skip)
        @f.jump(merge, [bit])
        @f.switch(rest)
        @f.jump(merge, [truth(*condition_value(node.right))])
        @f.switch(merge)
        [params.first, "Bool"]
      end

      # `value` as a Bool. A Bool is already 0 or 1. Any other integer is
      # true when it is not zero.
      #: (String value, String type) -> String
      def truth(value, type)
        type == "Bool" ? value : @f.icmp("ne", value, @f.iconst(ir_type(type), 0))
      end

      # Operators that lower to one instruction with no effect, and that
      # cannot fault for any operands. Division is not in this list.
      PLAIN_OPERATORS = %i[+ - * & | ^ << >> < <= > >= == != !].freeze #: Array[Symbol]
      PLAIN_CASTS = %i[i32 i8 word sword ptr value u8 u32].freeze #: Array[Symbol]

      # The operators whose result wraps at the width of the type, by
      # name. A plain `+ - * <<` must not overflow, so that it means the
      # same on CRuby (A6); a sum that must wrap names it. CRuby cannot
      # tell a Word from a Ptr by its value, so the name also says which:
      # `add_wrap` wraps a Word into its signed range, `uadd_wrap` a Ptr
      # into [0, 2**64).
      WRAPS = { add_wrap: :+, sub_wrap: :-, mul_wrap: :*, shl_wrap: :<<,
                uadd_wrap: :+, usub_wrap: :-, umul_wrap: :*, ushl_wrap: :<< }.freeze #: Hash[Symbol, Symbol]

      # The instruction name of a `/`, `%` and `>>`, the width in bits of an
      # integer IR type, the IR width and the Machine type that each load
      # and store gives or takes, and the Machine type of each conversion.
      DIVISION_MNEMONICS = { :/ => "div", :% => "rem", :>> => "shr" }.freeze #: Hash[Symbol, String]
      IR_BITS = { "i8" => 8, "i32" => 32, "i64" => 64 }.freeze #: Hash[String, Integer]
      LOAD_WIDTHS = { load64: "i64", load32: "i32", load8: "i8" }.freeze #: Hash[Symbol, String]
      LOAD_TYPES = { load64: "Word", load32: "I32", load8: "I8" }.freeze #: Hash[Symbol, String]
      STORE_TYPES = { store64: "Word", store32: "I32", store8: "I8" }.freeze #: Hash[Symbol, String]
      CONVERT_TARGETS = { i32: "I32", i8: "I8", word: "Word", sword: "Word", ptr: "Ptr", value: "Value" }.freeze #: Hash[Symbol, String]

      # Whether `node` reads only literals, constants and locals, through
      # plain operators and casts. Such an expression makes only its value.
      # A local is in the frame, so a read of it is safe on any path. A
      # load through a pointer is not safe.
      #: (Prism::node? node) -> bool
      def plain?(node)
        # A checked operator branches to its check, so it is not plain.
        return false if @unit.checked?

        case node
        when Prism::IntegerNode, Prism::TrueNode, Prism::FalseNode, Prism::ConstantReadNode then true
        when Prism::LocalVariableReadNode then @locals.key?(node.name.to_s)
        when Prism::ParenthesesNode then node.body.is_a?(Prism::StatementsNode) && node.body.body.one? && plain?(node.body.body[0])
        when Prism::AndNode, Prism::OrNode then plain?(node.left) && plain?(node.right)
        when Prism::CallNode
          args = node.arguments&.arguments || []
          return false if node.block || node.receiver.nil?
          if @unit.machine?(node.receiver)
            return (PLAIN_CASTS.include?(node.name) && args.one? && plain?(args[0])) ||
                   (WRAPS.key?(node.name) && args.size == 2 && args.all? { |a| plain?(a) })
          end

          PLAIN_OPERATORS.include?(node.name) && args.size <= 1 && plain?(node.receiver) && args.all? { |a| plain?(a) }
        else false
        end
      end

      OPERATORS = {
        :+ => "iadd", :- => "isub", :* => "imul", :& => "band", :| => "bor", :^ => "bxor", :<< => "ishl",
        :< => "lt", :<= => "le", :> => "gt", :>= => "ge", :== => "eq", :!= => "ne",
        :/ => nil, :% => nil, :>> => nil
      }.freeze #: Hash[Symbol, String?]

      # Word and Ptr can mix: a Ptr plus or minus a Word is a Ptr, a Ptr
      # minus a Ptr is a Word, and a comparison with a Ptr on one side is
      # unsigned. Value does not mix with other types.
      #
      # `named` is true for `Machine.add_wrap`, `Machine.sdiv` and the
      # others, which the checked build does not check for a wrap or a
      # negative operand.
      #: (Prism::node node, Symbol op, String lhs, String lt, String rhs, String rt, ?named: bool) -> [String, String]
      def binary(node, op, lhs, lt, rhs, rt, named: false)
        lt = "Ptr" if view(lt)
        rt = "Ptr" if view(rt)
        refuse(node, "#{op} on #{lt} and #{rt}") unless ir_type(lt) && (lt == rt || (PLAIN.include?(lt) && PLAIN.include?(rt)))
        return float_binary(node, op, lhs, rhs) if lt == "F64"

        ptr = lt == "Ptr" || rt == "Ptr"
        result = if ptr && op == :- && lt == rt then "Word"
                 elsif ptr then "Ptr"
                 else lt
                 end
        case op
        when :+, :-, :*, :&, :|, :^, :<<
          mnemonic = OPERATORS[op] #: String
          value = @f.binop(mnemonic.to_sym, lhs, rhs)
          if @unit.checked? && !named
            if result == "Ptr"
              check_unsigned(node, op, lhs, lt, rhs, rt, value)
            elsif !ptr
              check_wrap(node, op, lhs, rhs, value, result)
            end
          end
          [value, result]
        when :/, :%, :>>
          check_operands(node, op, lhs, rhs, lt, ptr, named) if @unit.checked?
          mnemonic = DIVISION_MNEMONICS[op]
          [@f.binop(:"#{ptr ? "u" : "s"}#{mnemonic}", lhs, rhs), result]
        when :==, :!=
          cond = OPERATORS[op] #: String
          [@f.icmp(cond, lhs, rhs), "Bool"]
        when :<, :<=, :>, :>=
          cond = OPERATORS[op] #: String
          cond = (ptr ? "u" : "s") + cond
          [@f.icmp(cond, lhs, rhs), "Bool"]
        else
          refuse(node, "#{op} is not in the kernel subset")
        end
      end

      # The checked build (`ZR_KERNEL_CHECKED`) finds each operator whose
      # meaning in the lowering differs from its meaning in Ruby. A plain
      # `+ - * <<` on a signed type (Word, I32, I8, Value) must not wrap,
      # `/ %` must not see a negative operand or a zero divisor, and `>>`
      # must shift by less than the width. A failed check prints the
      # kernel file and line and aborts (`zr_bug`). A Ptr is unsigned, so
      # only a shift of one is checked.
      CHECKED = %w[Word I32 I8 Value].freeze #: Array[String]

      #: (Prism::node node, Symbol op, String lhs, String rhs, String value, String type) -> void
      def check_wrap(node, op, lhs, rhs, value, type)
        return unless CHECKED.include?(type)

        w = ir_type(type)
        zero = @f.iconst(w, 0)
        case op
        when :+
          trap_if(node, @f.icmp("slt", @f.band(@f.binop(:bxor, lhs, value), @f.binop(:bxor, rhs, value)), zero), "+ wraps")
        when :-
          trap_if(node, @f.icmp("slt", @f.band(@f.binop(:bxor, lhs, rhs), @f.binop(:bxor, lhs, value)), zero), "- wraps")
        when :*
          # A product wraps when a nonzero factor does not divide it back,
          # or when it is the lowest value times -1.
          divide = @f.label
          done = @f.label
          @f.brif(@f.icmp("ne", lhs, zero), divide, done)
          @f.switch(divide)
          lowest = @f.iconst(w, -(1 << (bits(w) - 1)))
          back = @f.icmp("ne", @f.binop(:sdiv, value, lhs), rhs)
          negated = @f.band(@f.icmp("eq", lhs, @f.iconst(w, -1)), @f.icmp("eq", rhs, lowest))
          trap_if(node, @f.bor(back, negated), "* wraps")
          @f.jump(done)
          @f.switch(done)
        when :<<
          width = @f.iconst(w, bits(w))
          out = @f.icmp("uge", rhs, width)
          lost = @f.icmp("ne", @f.binop(:sshr, value, @f.band(rhs, @f.iconst(w, bits(w) - 1))), lhs)
          trap_if(node, @f.bor(out, lost), "<< wraps")
        end
      end

      # A Ptr is in [0, 2**64) (A6). A sum, a difference, a product or a
      # shift whose result is a Ptr must stay in that range. A Word added
      # to a Ptr is signed, so its sign says which way the Ptr may move.
      #: (Prism::node node, Symbol op, String lhs, String lt, String rhs, String rt, String value) -> void
      def check_unsigned(node, op, lhs, lt, rhs, rt, value)
        zero = @f.iconst("i64", 0)
        case op
        when :+, :-
          return if op == :- && lt != "Ptr" # a Word minus a Ptr is not an address

          ptr, word = lt == "Ptr" ? [lhs, rhs] : [rhs, lhs]
          up = @f.icmp("ult", value, ptr)
          down = @f.icmp("ugt", value, ptr)
          up, down = down, up if op == :-
          if lt == rt
            bad = up
          else
            forward = @f.icmp("sge", word, zero)
            bad = @f.bor(@f.band(forward, up), @f.band(@f.binop(:bxor, forward, @f.iconst("i8", 1)), down))
          end
          trap_if(node, bad, "#{op} leaves the range of a Ptr")
        when :*
          divide = @f.label
          done = @f.label
          @f.brif(@f.icmp("ne", lhs, zero), divide, done)
          @f.switch(divide)
          trap_if(node, @f.icmp("ne", @f.binop(:udiv, value, lhs), rhs), "* leaves the range of a Ptr")
          @f.jump(done)
          @f.switch(done)
        when :<<
          out = @f.icmp("uge", rhs, @f.iconst("i64", 64))
          lost = @f.icmp("ne", @f.binop(:ushr, value, @f.band(rhs, @f.iconst("i64", 63))), lhs)
          trap_if(node, @f.bor(out, lost), "<< leaves the range of a Ptr")
        end
      end

      #: (Prism::node node, Symbol op, String lhs, String rhs, String type, bool ptr, bool named) -> void
      def check_operands(node, op, lhs, rhs, type, ptr, named)
        w = ir_type(type)
        zero = @f.iconst(w, 0)
        if op == :>>
          trap_if(node, @f.icmp("uge", rhs, @f.iconst(w, bits(w))), ">> by the width or more")
          return
        end

        bad = @f.icmp("eq", rhs, zero)
        bad = @f.bor(bad, @f.bor(@f.icmp("slt", lhs, zero), @f.icmp("slt", rhs, zero))) unless ptr || named
        trap_if(node, bad, "#{op} of a negative number or by zero")
      end

      #: (String w) -> Integer
      def bits(w) = IR_BITS.fetch(w)

      # Calls `zr_bug` with "file:line: what" when `bad` is true. A unit
      # without zr_bug (a test of the lowering) gets no check.
      #: (Prism::node node, String bad, String what) -> void
      def trap_if(node, bad, what)
        bug = @unit.def_for("zr_bug") or return
        fail = @f.label
        ok = @f.label
        @f.brif(bad, fail, ok)
        @f.switch(fail)
        text = "#{Paths.shown(@d.file)}:#{node.location.start_line}: #{what} (ZR_KERNEL_CHECKED)\n"
        fn = @f.callee(bug.name, %w[i64 i64], nil, colocated: true)
        @f.call(fn, [@f.symbol_value(@f.symbol(@unit.bytes(text))), @f.iconst("i64", text.bytesize)])
        @f.jump(ok)
        @f.switch(ok)
      end

      FLOAT_OPS = { :+ => :fadd, :- => :fsub, :* => :fmul, :/ => :fdiv }.freeze #: Hash[Symbol, Symbol]
      FLOAT_CONDS = { :== => "eq", :!= => "ne", :< => "lt", :<= => "le", :> => "gt", :>= => "ge" }.freeze #: Hash[Symbol, String]

      # F64 arithmetic and comparison. A comparison with NaN on one side
      # is false, except `!=`.
      #: (Prism::node node, Symbol op, String lhs, String rhs) -> [String, String]
      def float_binary(node, op, lhs, rhs)
        return [@f.fbinop(FLOAT_OPS[op], lhs, rhs), "F64"] if FLOAT_OPS.key?(op)
        return [@f.fcmp(FLOAT_CONDS[op], lhs, rhs), "Bool"] if FLOAT_CONDS.key?(op)

        refuse(node, "#{op} on an F64")
      end

      PLAIN = %w[Word Ptr].freeze #: Array[String]

      # A Word, a Ptr and a view are each an address or a number, and fit
      # one another here. Steep tells a view from a word.
      #: (String want, String got) -> bool
      def fits?(want, got)
        want == got || (address?(want) && address?(got))
      end

      #: (String type) -> bool
      def address?(type) = PLAIN.include?(type) || !view(type).nil?

      # A call to an import (`Libc.name`) or to a def of this unit. A bare
      # call goes only to a def or a raw function.
      #: (Prism::CallNode node, String name, Array[Prism::node] args, ?imports: bool) -> [untyped, String]
      def target(node, name, args, imports: true)
        callee = @unit.def_for(name) || @unit.import_for(name)
        callee = nil if !imports && callee.is_a?(Import)
        callee or refuse(node, imports ? "#{name} is not an import or a machine def here" : "#{name} is not a def here; an import is `Libc.#{name}`")
        refuse(node, "#{name} takes #{callee.params.size} arguments, not #{args.size}") if args.size != callee.params.size
        types = callee.is_a?(Def) ? callee.params.map(&:last) : callee.params
        values = args.zip(types).map do |arg, want|
          # The sizes match, so each argument has a type.
          type = want #: String
          value, got = expr(arg, type)
          refuse(arg, "#{name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          rooted(arg, value, got)
        end
        return inline(callee, values) if callee.is_a?(Def) && @unit.inline?(callee) && !@inlining.include?(callee.name)

        from = callee.from if callee.is_a?(Import)
        fn = @f.callee(name, types.map { |t| ir_type(t) }, ir_type(callee.ret), colocated: !callee.is_a?(Import), from: from)
        if callee.ret == "Void"
          @f.call(fn, values)
          [nil, "Void"]
        else
          [@f.call_val(fn, values), callee.ret]
        end
      end

      # Lowers the body of `d` in place of the call, with the argument
      # `values`. Its parameters and locals are in a scope of their own,
      # as in a call. A refusal in the body gives the file of the callee.
      #
      # The body cannot collect, so nothing in it goes in the root frame.
      # A Value is in a slot of its own, and `IR::Mem2Reg` can make it a
      # register.
      #
      # A `return` in the body (frequently a guard clause at the start of
      # a small def) jumps with its value to a block after the body. The
      # last value of the body also jumps there. The parameter of that
      # block is the result of the call.
      #: (Def d, Array[untyped] values) -> [untyped, String]
      def inline(d, values)
        # @type ivar @exit: Exit
        outer = [@locals, @d, @roots, @exit] #: [Hash[String, { type: String, addr: String }], Def, Roots?, Exit]
        begin
          @locals = {}
          @d = d
          @roots = nil
          @exit = Exit.new(type: d.ret)
          @inlining << d.name
          d.params.each_with_index do |(name, type), i|
            @f.store(values[i], declare_local(d.node, name, type)[:addr])
          end
          body = def_body(d)
          value, type = body ? statements(body, d.ret) : [nil, "Void"]
          # Only a `return` in the body makes the exit block.
          exit_block = @exit.block
          unless @f.terminated?
            refuse(d.node, "the body ends in #{type}, and the def's type says #{d.ret}") unless d.ret == "Void" || fits?(d.ret, type)
            ret(d.ret == "Void" ? nil : value) if exit_block
          end
          if exit_block
            @f.switch(exit_block, open: true)
            value = @exit.value
          end
          d.ret == "Void" ? [nil, "Void"] : [value, d.ret] #: [untyped, String]
        ensure
          @inlining.pop
          @locals, @d, @roots, @exit = outer
        end
      end

      # A Value that a call returns must stay alive across the next calls
      # in the same argument list, so it gets a root slot of its own. A
      # struct field read or a `Machine.value` is also a call here: Ruby
      # code in a later argument can free the object it refers to.
      #: (Prism::node? node, untyped value, String type) -> untyped
      def rooted(node, value, type)
        # @type ivar @roots: Roots
        return value unless @roots && type == "Value" && node.is_a?(Prism::CallNode)

        @f.store(value, @roots.addr, root_slot)
        value
      end

      # Each arm checks the class of the arguments that it reads.
      #: (Prism::CallNode node, Array[untyped] args, String? want) -> [untyped, String]
      def intrinsic(node, args, want)
        case node.name
        when :id
          name = args.first
          refuse(node, "Machine.id takes a symbol") unless name.is_a?(Prism::SymbolNode) && args.size == 1
          literal(node, @unit.symbols.id(name.unescaped), want)
        when :bytesize
          s = args.first
          refuse(node, "Machine.bytesize takes a string literal") unless s.is_a?(Prism::StringNode)
          literal(node, s.unescaped.bytesize, want)
        when :extern
          name = args.first
          refuse(node, "Machine.extern takes the symbol of a data object another unit defines") unless name.is_a?(Prism::SymbolNode)
          [@f.symbol_value(@f.symbol(name.unescaped, colocated: false)), "Ptr"]
        when :bytes
          s = args.first
          refuse(node, "Machine.bytes takes a string literal") unless s.is_a?(Prism::StringNode)
          [@f.symbol_value(@f.symbol(@unit.bytes(s.unescaped))), "Ptr"]
        when :load64, :load32, :load8
          width = LOAD_WIDTHS[node.name]
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr and an offset") unless fits?("Ptr", pt) && args.size == 2
          type = LOAD_TYPES[node.name]
          [@f.fetch(width, ptr, immediate(args[1])), type]
        when :store64, :store32, :store8
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr, an offset and a value") unless fits?("Ptr", pt) && args.size == 3
          type = STORE_TYPES[node.name]
          value, vt = expr(args[2], type)
          refuse(node, "#{node.name} stores a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          @f.store(value, ptr, immediate(args[1]))
          [nil, "Void"]
        when :slot
          refuse(node, "Machine.slot takes a size") unless args.size == 1
          [@f.stack_addr(@f.slot(immediate(args.first))), "Ptr"]
        when :static
          name, size = args
          refuse(node, "Machine.static takes a symbol and a size") unless name.is_a?(Prism::SymbolNode) && size
          [@f.symbol_value(@f.symbol(@unit.static(node, name.unescaped, immediate(size)))), "Ptr"]
        when :gates
          refuse(node, "Machine.gates takes nothing") unless args.empty?
          [@f.gates, "Word"]
        when :gates_set
          value, type = expr(args.first, "Word")
          refuse(node, "Machine.gates_set takes a Word") unless args.one? && ir_type(type) == "i64"
          @f.store(value, gates_addr(node), region: :gates)
          @f.gates_set(value)
          [nil, "Void"]
        when :gates_enter
          refuse(node, "Machine.gates_enter takes nothing") unless args.empty?
          @f.gates_enter(@f.fetch("i64", gates_addr(node), region: :gates))
          [nil, "Void"]
        when :i32, :i8, :word, :sword, :ptr, :value
          # `Machine.word(0x8080808080808080)`: the bits of a literal
          # that does not fit a signed Word.
          return literal(args.first, args.first.value, "Word") if node.name == :word && args.first.is_a?(Prism::IntegerNode)

          value, type = expr(args.first)
          # Ruby keeps the sign of an I8 or I32, so a widening says which
          # bits it means.
          if %i[word ptr value].include?(node.name) && %w[I8 I32].include?(type)
            refuse(node, "Machine.#{node.name} of an #{type} is Machine.#{type == "I8" ? "u8" : "u32"} (zero-extend) or Machine.sword (sign-extend)")
          end
          convert(node, node.name, value, type)
        when :u8, :u32
          value, type = expr(args.first)
          narrow = node.name == :u8 ? "i8" : "i32"
          refuse(node, "Machine.#{node.name} of a #{type}") unless args.one? && ir_type(type) == narrow
          convert(node, :word, value, type)
        when *WRAPS.keys
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of an F64") if lt == "F64" || rt == "F64"
          unsigned = node.name.start_with?("u")
          unless lt == (unsigned ? "Ptr" : "Word")
            refuse(node, "Machine.#{node.name} of a #{lt}; #{unsigned ? "it wraps a Ptr" : "a Ptr wraps by Machine.u#{node.name}"}")
          end
          binary(node, WRAPS.fetch(node.name), lhs, lt, rhs, rt, named: true)
        when :sdiv, :srem
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of a #{lt} and a #{rt}") unless %w[I8 I32 Word].include?(lt) && lt == rt
          binary(node, node.name == :sdiv ? :/ : :%, lhs, lt, rhs, rt, named: true)
        when :f64, :bits, :to_f64, :to_int
          value, type = expr(args.first)
          float_convert(node, node.name, value, type) #: [String, String]
        when :ctz, :clz, :popcnt, :bswap
          value, type = expr(args.first)
          # CRuby keeps no width, so these count the 64 bits of a word.
          if ir_type(type) == "i32"
            refuse(node, "Machine.#{node.name} of an I32 counts 64 bits on CRuby; widen it first (Machine.u32)")
          end
          refuse(node, "Machine.#{node.name} of a #{type}") unless ir_type(type) == "i64" && args.one?
          [@f.bitop(node.name, value), type]
        when :sqrt, :floor, :ceil, :trunc, :nearest, :fabs
          value, type = expr(args.first)
          refuse(node, "Machine.#{node.name} of a #{type}") unless type == "F64"
          [@f.funop(node.name, value), "F64"]
        when :addr
          name = args.first
          refuse(node, "Machine.addr takes the symbol of a machine def") unless name.is_a?(Prism::SymbolNode)
          d = @unit.def_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a machine def here")
          fn = @f.callee(d.name, d.params.map { |_, t| ir_type(t) }, ir_type(d.ret), colocated: true)
          [@f.func_addr(fn), "Ptr"]
        else
          refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      # A call through the pointer `at` with the signature `s`:
      # `Name.call(at, ...)`.
      # `rest` is empty when `at` is nil, and then the first line refuses.
      #: (Prism::CallNode node, Signature s, Prism::node? at, Array[Prism::node] rest) -> [untyped, String]
      def indirect(node, s, at, rest)
        ptr, pt = expr(at || refuse(node, "#{s.name}.call takes a pointer first"), "Ptr")
        refuse(at, "#{s.name}.call through a #{pt}") unless fits?("Ptr", pt)
        refuse(node, "#{s.name} takes #{s.params.size} arguments, not #{rest.size}") if rest.size != s.params.size
        values = rest.zip(s.params).map do |arg, want|
          # The sizes match, so each argument has a type.
          type = want #: String
          value, got = expr(arg, type)
          refuse(arg, "#{s.name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          rooted(arg, value, got)
        end
        sig = @f.sig(s.params.map { |t| ir_type(t) }, ir_type(s.ret))
        return [@f.call_indirect(sig, ptr, values), "Void"] if s.ret == "Void"

        [@f.call_indirect_val(sig, ptr, values), s.ret]
      end

      # The static of the gate word. `Machine.gates` reads the word from
      # its register. `Machine.gates_set(word)` stores the word and sets
      # the register. `Machine.gates_enter` is first in a def that foreign
      # code calls; it loads the register from the static, and the def
      # restores the register before it returns.
      #: (Prism::node node) -> String
      def gates_addr(node)
        @f.symbol_value(@f.symbol(@unit.static(node, "gates", 8)))
      end

      # A change of width or of type: `Machine.i32(x)` narrows, `u8` and
      # `u32` zero-extend, `sword` sign-extends. `ptr`, `value` and `word`
      # between 64-bit types change only the type, not the bits.
      #: (Prism::node node, Symbol to, String value, String type) -> [String, String]
      def convert(node, to, value, type)
        target = CONVERT_TARGETS[to]
        from, into = ir_type(type), ir_type(target)
        refuse(node, "Machine.#{to} of a #{type}") if from.nil? || from == "f64"
        return [value, target] if from == into
        return [@f.ireduce(into, value), target] if from == "i64" || (from == "i32" && into == "i8")

        [to == :sword ? @f.sextend(into, value) : @f.uextend(into, value), target]
      end

      # `Machine.f64(word)` and `Machine.bits(f)` read the same 64 bits
      # as the other type. `to_f64` and `to_int` convert the value;
      # `to_int` saturates.
      #: (Prism::node node, Symbol to, String value, String type) -> [String, String]?
      def float_convert(node, to, value, type)
        case to
        when :f64
          refuse(node, "Machine.f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.bitcast("f64", value), "F64"]
        when :bits
          refuse(node, "Machine.bits of a #{type}") unless type == "F64"
          [@f.bitcast("i64", value), "Word"]
        when :to_f64
          refuse(node, "Machine.to_f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.fcvt_from_sint(value), "F64"]
        when :to_int
          refuse(node, "Machine.to_int of a #{type}") unless type == "F64"
          [@f.fcvt_to_sint_sat(value), "Word"]
        end
      end

      # Lowers the test `node` as a branch: to `yes` when it is true, to
      # `no` when it is false. An `&&` or `||` branches on its left side
      # and tests its right side only when the left side does not decide.
      # A `!` swaps the targets. Other nodes are tested as values. Thus a
      # test makes no bit to test (no set, no widening, no join of a byte),
      # and each compare feeds its branch directly.
      #: (Prism::node? node, String yes, String no) -> void
      def jump_if(node, yes, no)
        case node
        when Prism::AndNode, Prism::OrNode
          rest = @f.label
          node.is_a?(Prism::AndNode) ? jump_if(node.left, rest, no) : jump_if(node.left, yes, rest)
          @f.switch(rest)
          jump_if(node.right, yes, no)
        when Prism::ParenthesesNode
          body = node.body
          return jump_if(body.body[0], yes, no) if body.is_a?(Prism::StatementsNode) && body.body.one?

          @f.brif(condition_value(node).first, yes, no)
        when Prism::CallNode
          return jump_if(node.receiver, no, yes) if node.name == :! && node.arguments.nil? && node.receiver

          @f.brif(condition_value(node).first, yes, no)
        else
          @f.brif(condition_value(node).first, yes, no)
        end
      end

      # `[value, type]` of an expression that a branch can test: a Bool.
      # CRuby takes every Integer as true, 0 too, so a test of an integer
      # would mean another thing on the host; it compares instead.
      #: (Prism::node? node) -> [untyped, String]
      def condition_value(node)
        value, type = expr(node)
        refuse(node, "a condition that is a #{type}; CRuby takes 0 as true, so compare it (`x != 0`)") unless type == "Bool"
        [value, type]
      end

      # `if` as a value when both arms have the same type, else Void. The
      # arms lower before the shape of the merge block is known, so their
      # jumps are written last. `then_stmts` is the then arm. `else_part`
      # is the statements of the else arm, an elsif, or nil.
      #: (Prism::IfNode | Prism::UnlessNode node, String? want, Prism::StatementsNode? then_stmts, Prism::node? else_part) -> [untyped, String]
      def branch(node, want, then_stmts, else_part)
        # @type var tv: untyped
        # @type var ev: untyped
        then_b = @f.label
        else_b = @f.label
        jump_if(node.predicate, then_b, else_b)
        @f.switch(then_b)
        tv, tt = then_stmts ? statements(then_stmts, want) : [nil, "Void"]
        then_open = !@f.terminated?
        then_end = @f.current.name
        @f.switch(else_b, open: true)
        ev, et = else_part ? expr(else_part, want) : [nil, "Void"]
        else_open = !@f.terminated?
        else_end = @f.current.name
        return [nil, "Void"] if !then_open && !else_open

        joined = then_open && else_open && tt == et && tt != "Void" ? tt : "Void"
        merge, params = joined == "Void" ? @f.block : @f.block([ir_type(joined)])
        carry = joined == "Void" ? [] : nil #: Array[String]?
        @f.finish(then_end, IR::Inst.new(:jump, targets: [[merge, carry || [tv]]])) if then_open
        @f.finish(else_end, IR::Inst.new(:jump, targets: [[merge, carry || [ev]]])) if else_open
        @f.switch(merge, open: true)
        [joined == "Void" ? nil : params.first, joined]
      end

      #: (Prism::WhileNode node) -> [nil, String]
      def loop_while(node)
        head = @f.label
        body = @f.label
        done = @f.label
        @f.jump(head)
        @f.switch(head)
        jump_if(node.predicate, body, done)
        @f.switch(body)
        @loops.push(done)
        statements(node.statements) if node.statements
        @loops.pop
        @f.jump(head) unless @f.terminated?
        @f.switch(done)
        [nil, "Void"]
      end
    end
  end
end
