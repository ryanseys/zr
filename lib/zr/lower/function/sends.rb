# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Method calls: the receiver and arguments staged in the record, the
      # dispatch, the block-passing form, and the inline fixnum operators.
      module Sends
        # @type instance: Function
        # The ivars that every file of Sends reads:
        # @rbs @blk: String
        # @rbs @cref: String
        # @rbs @env: String
        # @rbs @f: IR::Function
        # @rbs @funcalls: Hash[Hir::Send, bool]?
        # @rbs @keywords: Hash[Hir::HashLit, Symbol]?
        # @rbs @kind: Function::kind
        # @rbs @l: Lower
        # @rbs @locals: Array[Symbol]
        # @rbs @name: String
        # @rbs @native_each: bool?
        # @rbs @native_operators: bool?
        # @rbs @sends_all: bool?
        # @rbs @proc_layout: Machine::Layout
        # @rbs @qnil: String
        # @rbs @rec: String
        # @rbs @self: String
        # @rbs @sites: Integer
        # @rbs @sp: Integer
        # @rbs @task: Machine::Layout
        # @rbs @task_addr: String

        # The operators with an inline fixnum fast path, and their gates.
        OPS = {
          :+ => "GATE_PLUS", :- => "GATE_MINUS", :* => "GATE_MUL", :/ => "GATE_DIV", :% => "GATE_MOD",
          :< => "GATE_LT", :<= => "GATE_LE", :> => "GATE_GT", :>= => "GATE_GE", :== => "GATE_EQ", :!= => "GATE_NE",
          :& => "GATE_AND", :| => "GATE_OR", :^ => "GATE_XOR", :>> => "GATE_SHR"
        }.freeze #: Hash[Symbol, String]
        # The comparison operators among them, as the IR's signed
        # conditions on the tagged words.
        RELATIONS = { :< => "slt", :<= => "sle", :> => "sgt", :>= => "sge", :== => "eq", :!= => "ne" }.freeze #: Hash[Symbol, String]

        # What a site can do in place of a call, by the kernel's name for the
        # cell's shape (lib/zr/runtime/kernel/cache.rb): an accessor's body, or one of
        # the core's type checks. The two accessors read and write a cell's
        # table, so their receiver must be a cell. The type checks accept any
        # receiver.
        SHAPES = {
          reader: "SHAPE_READER", writer: "SHAPE_WRITER", is_a: "SHAPE_IS_A", instance_of: "SHAPE_INSTANCE_OF",
          nil_p: "SHAPE_NIL_P", frozen_p: "SHAPE_FROZEN_P", ary_length: "SHAPE_ARY_LENGTH", mod_eqq: "SHAPE_MOD_EQQ",
          eq: "SHAPE_EQ", ne: "SHAPE_NE", eqq: "SHAPE_EQQ"
        }.freeze #: Hash[Symbol, String]
        ACCESSOR_SHAPES = %i[reader writer].freeze #: Array[Symbol]
        # The zero-argument checks that a site handles by name. `nil?` and
        # `frozen?` cannot be attribute names, so the site does not test for
        # a reader.
        QUESTIONS = { nil?: [:nil_p], frozen?: [:frozen_p], size: %i[ary_length reader], length: %i[ary_length reader] }.freeze
        # The one-argument checks. `case` sends `===` for each `when`, and
        # Module#=== does the class tests of a `case` on objects. `==`,
        # `equal?` and `!=` are identity tests if the cell has BasicObject's.
        ARGUED = {
          is_a?: [:is_a], kind_of?: [:is_a], instance_of?: [:instance_of], "===": %i[mod_eqq eqq],
          "==": [:eq], equal?: [:eq], "!=": [:ne]
        }.freeze #: Hash[Symbol, Array[Symbol]]
        # The type checks that a site handles before its cell, while no
        # class has defined the name (lib/zr/runtime/kernel/integer.rb).
        QUESTION_GATES = { is_a?: "GATE_IS_A", kind_of?: "GATE_IS_A", instance_of?: "GATE_INSTANCE_OF" }.freeze #: Hash[Symbol, String]

        # The kernel entry of each operator and named call with a core
        # fast path, and the classes that it handles. The named calls are
        # in `Hir::Build::OPT_CALLS`, which marks the call.
        OPT_ENTRIES = {
          :[] => ["zr_opt_aref", %w[G_ARRAY G_HASH]], :[]= => ["zr_opt_aset", %w[G_ARRAY G_HASH]], :<< => ["zr_opt_ltlt", %w[G_ARRAY G_STRING]],
          getbyte: ["zr_opt_getbyte", %w[G_STRING]], setbyte: ["zr_opt_setbyte", %w[G_STRING]],
          push: ["zr_opt_push", %w[G_ARRAY]], pop: ["zr_opt_pop", %w[G_ARRAY]], shift: ["zr_opt_shift", %w[G_ARRAY]],
          empty?: ["zr_opt_empty_p", %w[G_ARRAY]]
        }.freeze #: Hash[Symbol, [String, Array[String]]]
        # `Math.f(x)` that a site calls directly while GATE_MATH is clear:
        # the number of each function in zr_math_call (sqrt has its own).
        MATH_CALLS = { sqrt: 0, cbrt: 1, sin: 2, cos: 3, tan: 4, atan: 5, exp: 6 }.freeze #: Hash[Symbol, Integer]
        # The unary Integer calls with an inline fixnum fast path, and
        # their gates.
        UNARY = { succ: "GATE_SUCC", :-@ => "GATE_UMINUS" }.freeze #: Hash[Symbol, String]
        # A call with more arguments than this checks that ruby's VM stack
        # would hold them (zr_vm_stack_args). The least VM stack that ruby
        # takes holds 2,048 words.
        MANY_ARGS = 1_024
        # The unary calls with a flonum path as well, and Float's gates.
        FLOAT_UNARY = { :-@ => "GATE_FLO_UMINUS" }.freeze #: Hash[Symbol, String]
        # The operators with a flonum path: the f64 instruction or the
        # fcmp condition, and the gate of Float's method.
        FLOAT_OPS = {
          :+ => [:fadd, "GATE_FLO_PLUS"], :- => [:fsub, "GATE_FLO_MINUS"], :* => [:fmul, "GATE_FLO_MUL"], :/ => [:fdiv, "GATE_FLO_DIV"],
          :< => ["lt", "GATE_FLO_LT"], :<= => ["le", "GATE_FLO_LE"], :> => ["gt", "GATE_FLO_GT"], :>= => ["ge", "GATE_FLO_GE"],
          :== => ["eq", "GATE_FLO_EQ"]
        }.freeze #: Hash[Symbol, [IR::op | String, String]]
        # The bits of +0.0 as a flonum, and of the double that the rotation
        # cannot represent (lib/zr/runtime/kernel/float.rb).
        FLONUM_ZERO = 9223372036854775810 - (1 << 64) #: Integer
        FLONUM_HOLE = 3458764513820540928

        # The names that CRuby's C sends by name, even to instances of its
        # own classes, so a method that a program defines is called: the
        # conversions, equality, hashing and ordering, iteration, the object
        # protocol and its hooks, and error reporting. Any other send by the
        # core library to an instance of a runtime class goes to the core
        # library's own method, as a C call goes to a C function
        # (lib/zr/runtime/kernel/send.rb, SEND_CORE).
        PROTOCOL = %i[
          initialize initialize_copy initialize_dup initialize_clone
          to_s inspect to_str to_sym to_proc to_ary to_a to_hash to_h to_int to_i to_f to_r to_c to_path to_io to_regexp
          == != eql? hash <=> === =~ ! coerce
          call write warn default
          respond_to? respond_to_missing? method_missing
          method_added singleton_method_added method_removed singleton_method_removed method_undefined
          singleton_method_undefined inherited included extended prepended const_added const_missing
          marshal_dump marshal_load _dump _load pp
          exception message backtrace full_message detailed_message
        ].to_set.freeze #: Set[Symbol]
        # The flag bit of a send in the core library (SEND_CORE).
        SEND_CORE = 8
        # The flag bit of a send under `using` (SEND_USING). Its cells
        # contain the result of the lookup with the site's refinements.
        SEND_USING = 16
        # The flag bit of any send from the core library's stand-ins for C
        # (SEND_INTERNAL).
        SEND_INTERNAL = 64
        # The number of cells of a send site (lib/zr/runtime/kernel/cache.rb, CALL_WAYS).
        CALL_WAYS = 4
        # The names that numeric code sends to a Float. Their sites find a
        # flonum's class inline. All other sites let the kernel read a
        # flonum's class, to keep the code small.
        FLONUM_NAMES = (OPS.keys + %i[
          ** -@ +@ <=> to_i to_f to_s to_r round floor ceil truncate abs divmod fdiv quo
          nan? finite? infinite? zero? positive? negative? coerce
        ]).to_set.freeze #: Set[Symbol]

        private

        # The receiver and arguments go into record slots (a splat collects
        # them into one Array there), then keywords as a Hash that the task
        # flags, then the send.
        #: (Hir::Send node) -> String
        def call(node)
          return safe_call(node) if node.safe
          return interp_to_s(node) if node.interp
          if (name = kernel_send(node))
            return call(funcall(node, name))
          end
          return primitive(node) if primitive?(node)
          return identity(node) if identity?(node)

          recv_node = node.recv || Hir::SelfRef.new(node.line)
          return direct_operator(node, recv_node) if direct_operands?(node, recv_node)

          args = node.args + keyword_args(node)
          if args.any?(Hir::Splat)
            staged([recv_node], 2) do |slots, base|
              # The arguments go in an Array of the spread stack, which
              # the call gives back when it returns (zr_spread_take).
              @f.store(kernel("zr_spread_mark"), @rec, value_offset(base + 2))
              ary = gather(args, base + 1, spread: true)
              # A write returns the value that it wrote (the last collected
              # element), not the writer's return value.
              r = if node.write
                    last = kernel("zr_ary_at", ary, @f.isub(array_len(ary), imm(1))) #: String
                    send_staged(node, @f.fetch("i64", slots), array_ptr(ary), array_len(ary))
                    last
                  else
                    send_staged(node, @f.fetch("i64", slots), array_ptr(ary), array_len(ary))
                  end
              kernel("zr_spread_give", @f.fetch("i64", @rec, value_offset(base + 2))) unless @f.terminated?
              r
            end
          else
            staged([recv_node, *args]) do |slots|
              checked(kernel("zr_vm_stack_args", imm(args.size + 1))) if args.size > MANY_ARGS
              r = send_staged(node, @f.fetch("i64", slots), @f.iadd(slots, imm(8)), imm(args.size))
              node.write ? @f.fetch("i64", slots, 8 * node.args.size) : r
            end
          end
        end

        # `a.equal?(b)` in the core's stand-ins for C is CRuby's `a == b` on
        # two VALUEs: no send, whatever either object defines or undefines.
        # So is `a == b` and `a != b` where one side is nil, true, false or
        # a Symbol literal, as C compares a VALUE with Qnil or a sym_ name.
        # An implicit receiver is self.
        #: (Hir::Send node) -> bool
        def identity?(node)
          return false unless node.args.size == 1 && !node.args[0].is_a?(Hir::Splat)
          return false if node.block || node.kwargs || node.safe || node.write || !c_stand_in?

          node.name == :equal? || (node.recv && %i[== !=].include?(node.name) && [node.recv, node.args[0]].any? { immediate_literal?(it) })
        end

        #: (Hir::node node) -> bool
        def immediate_literal?(node)
          node.is_a?(Hir::Literal) && (node.value.nil? || node.value == true || node.value == false || node.value.is_a?(Symbol))
        end

        #: (Hir::Send node) -> String
        def identity(node)
          staged([node.recv || Hir::SelfRef.new(node.line), node.args[0]]) do |_, base|
            same = @f.icmp(node.name == :!= ? "ne" : "eq", @f.fetch("i64", @rec, value_offset(base)), @f.fetch("i64", @rec, value_offset(base + 1)))
            @f.csel(same, imm(@l.const("QTRUE")), imm(@l.const("QFALSE")))
          end
        end

        # An operator site tests its operands directly when no collection
        # can occur while it holds the receiver's value only in a register:
        # the argument is a plain read (a local, self, an immediate literal:
        # nothing that calls or allocates), or the receiver is self or an
        # immediate literal, which need no root. An argument of operators
        # and simple calls (`operator_tree?`) can also be direct: then the
        # receiver waits in its record slot while the argument runs
        # (`site_operands`). Thus `(a * b) * c`, `1.0 / (a * b)` and
        # `v - dx * b.mass` keep the intermediate values out of the record. The site stages the
        # operands in the record only on the send branch, so the fast
        # branch stores and releases nothing. A unary operator has one
        # operand, and nothing runs between its read and the test, so any
        # receiver is permitted. A safe call (`a&.== b`) tests its receiver
        # for nil first, so it has no fast path here.
        #: (Hir::Send node, Hir::node recv_node) -> bool
        def direct_operands?(node, recv_node)
          return false if node.block || node.kwargs || node.write || node.vcall || node.safe || owner_using?(node) || traced?

          if node.args.size == 1 && OPS.key?(node.name)
            arg = node.args.first
            !arg.is_a?(Hir::Splat) && (plain_read?(arg) || rootless?(recv_node) || operator_tree?(arg))
          else
            node.args.empty? && UNARY.key?(node.name) && explicit?(node)
          end
        end

        # Self, or an immediate literal: a value that needs no root.
        #: (Hir::node node) -> bool
        def rootless?(node) = node.is_a?(Hir::SelfRef) || (node.is_a?(Hir::Literal) && plain_read?(node))

        # The two operands of a direct operator site, in order. While an
        # argument that is not a plain read runs, the receiver waits in the
        # slot that the send has for it (Scope counts it), so a collection
        # sees it.
        #: (Hir::Send node, Hir::node recv_node) -> [Operand, Operand]
        def site_operands(node, recv_node)
          arg = node.args.first
          a = operand_of(node, recv_node)
          return [a, operand_of(node, arg)] if plain_read?(arg) || rootless?(recv_node)

          base = reserve(1)
          @f.store(a.value, @rec, value_offset(base))
          b = operand_of(node, arg)
          held = @f.fetch("i64", @rec, value_offset(base))
          release(base)
          [Operand.new(held, a.bits), b]
        end

        # Whether `node` is only operators over plain reads and simple
        # calls, such as `a * (b + 1.0)` or `dx * b.mass`.
        #: (Hir::node? node) -> boolish
        def operator_tree?(node)
          return true if plain_read?(node) || simple_call?(node)

          node.is_a?(Hir::Send) && node.args.size == 1 && OPS.key?(node.name) && node.recv && !node.block &&
            !node.kwargs && !node.write && !node.safe && operator_tree?(node.recv) && operator_tree?(node.args.first)
        end

        # A call of a plain read or a constant with plain reads as its
        # arguments, such as `b.mass`, `a[i]` or `Math.sqrt(x)`.
        #: (Hir::node? node) -> bool
        def simple_call?(node)
          node.is_a?(Hir::Send) && !OPS.key?(node.name) && !node.block && !node.kwargs && !node.write &&
            (plain_read?(node.recv) || node.recv.is_a?(Hir::ConstRead)) && node.args.all? { |a| plain_read?(a) }
        end

        #: (Hir::node? node) -> bool
        def plain_read?(node)
          case node
          when Hir::Local, Hir::SelfRef then true
          when Hir::Literal
            value = node.value
            value.nil? || value == true || value == false || value.is_a?(Symbol) ||
              (value.is_a?(Integer) && value >= -(2**62) && value < 2**62) || (value.is_a?(Float) && flonum_word(value))
          else false
          end
        end

        #: (Hir::Send node, Hir::node recv_node) -> String
        def direct_operator(node, recv_node)
          if node.args.empty?
            recv = expr(recv_node)
            args = [] #: Array[String]
          else
            a, b = site_operands(node, recv_node)
            return fused_operator(node, a, b, unboxed: false).tap { deactivate(node) } if a.bits || b.bits

            recv = a.value
            args = [b.value]
          end
          slow = -> { sent_directly(node, recv, args) }
          (args.empty? ? unary(node, recv, nil, &slow) : operator(node, recv, nil, args.first, &slow)).tap { deactivate(node) }
        end

        # The send of an operator whose operands were read as values. They
        # are staged in the record only here, on the send branch.
        #: (Hir::Send node, String recv, Array[String] args) -> String
        def sent_directly(node, recv, args)
          staged([recv, *args], evaluate: ->(value) { value }) do |slots|
            dispatch(node, recv, @f.iadd(slots, imm(8)), imm(args.size))
          end
        end

        # Whether a test of `node` branches on the comparison itself: a
        # comparison of plain reads (`direct_operands?`), unless it is an
        # identity test (`identity?`).
        #: (Hir::Send node) -> bool
        def relation_test?(node)
          RELATIONS.key?(node.name) && direct_operands?(node, node.recv || Hir::SelfRef.new(node.line)) && !identity?(node)
        end

        # `a < b` and the other comparisons as a test (`Control#jump_if`).
        # The fixnum and flonum paths branch on the comparison, so no true
        # or false is made only to be tested again (for example, fib's
        # `n < 2` or a loop's `i < n`). The call's result is tested as a
        # value.
        #: (Hir::Send node, String yes, String no) -> void
        def relation_jump(node, yes, no)
          a, b = site_operands(node, node.recv || Hir::SelfRef.new(node.line))
          return fused_relation_jump(node, a, b, yes, no) if a.bits || b.bits

          recv = a.value
          arg = b.value
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label if float_path?(node)
          @f.brif(@f.band(fixnums?(recv, arg), gate_clear(OPS.fetch(node.name))), fast, floating || slow)
          switch(fast)
          @f.brif(@f.icmp(RELATIONS.fetch(node.name), recv, arg), yes, no)
          if floating
            switch(floating)
            x, y = doubles(node.name, recv, arg, slow)
            # A relation's float operation is a compare's condition.
            cond = FLOAT_OPS.fetch(node.name).first #: String
            @f.brif(@f.fcmp(cond, x, y), yes, no)
          end
          switch(slow)
          native_equality(node, recv, arg) { |equal| @f.brif(equal, yes, no) }
          v = sent_directly(node, recv, [arg])
          deactivate(node)
          @f.brif(truthy(v), yes, no) unless @f.terminated?
        end

        # `relation_jump` with an inner float operator's result as one
        # operand.
        #: (Hir::Send node, Operand a, Operand b, String yes, String no) -> void
        def fused_relation_jump(node, a, b, yes, no)
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label
          @f.brif(@f.band(fixnums?(a.value, b.value), gate_clear(OPS.fetch(node.name))), fast, floating)
          switch(fast)
          @f.brif(@f.icmp(RELATIONS.fetch(node.name), a.value, b.value), yes, no)
          switch(floating)
          x, y = doubles(node.name, a, b, slow)
          cond = FLOAT_OPS.fetch(node.name).first #: String
          @f.brif(@f.fcmp(cond, x, y), yes, no)
          switch(slow)
          v = sent_fused(node, a, b)
          deactivate(node)
          @f.brif(truthy(v), yes, no) unless @f.terminated?
        end

        # In the runtime's own Ruby, `recv.send(:name, ...)` is rb_funcall
        # in CRuby's C: a direct call of `name`, private permitted, and
        # never a class's own `send` (BasicSocket has one). The call uses
        # its own cell, with no send frame and no lookup by name. For all
        # names except PROTOCOL, the core's own method entry is used, as
        # for every other call that the core makes.
        # This gives the name that the kernel send calls, or nil.
        #: (Hir::Send node) -> Symbol?
        def kernel_send(node)
          return unless @l.internal? && %i[send __send__].include?(node.name)

          first = node.args.first
          name = first.value if first.is_a?(Hir::Literal)
          name if name.is_a?(Symbol) && !%i[send __send__ public_send].include?(name)
        end

        # The call of `name` that a kernel send gives, marked so it can
        # call a private method with any receiver (`send_mode`).
        #: (Hir::Send node, Symbol name) -> Hir::Send
        def funcall(node, name)
          named = node.dup.tap do |n|
            n.name = name
            n.args = node.args.drop(1)
          end
          unless (funcalls = @funcalls)
            funcalls = {} #: Hash[Hir::Send, bool]
            @funcalls = funcalls.compare_by_identity
          end
          funcalls[named] = true
          named
        end

        # `recv&.name(args)`: nil if the receiver is nil, with the arguments
        # not evaluated; else the send.
        #: (Hir::Send node) -> String
        def safe_call(node)
          # `self&.x` is `self.x`: self is never nil, and the receiver stays
          # a literal self for the visibility rule. Coverage counts the
          # call, and never counts the nil branch.
          covers = node.covers
          if node.recv.is_a?(Hir::SelfRef)
            cover(covers.first.id) if covers
            return call(@l.noted(node.dup.tap { |n| n.safe = false }, node))
          end

          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = @l.noted(Hir::Send.of(Hir::Slot.new(slot, node.line), node.name, node.args, node.line,
                                        opt: node.opt, block: node.block, kwargs: node.kwargs, write: node.write, using: node.using), node)
          is_nil = @f.label
          go = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("eq", @f.fetch("i64", @rec, value_offset(slot)), @qnil), is_nil, go)
          switch(is_nil)
          cover(covers.last.id) if covers
          @f.jump(merge, [@qnil])
          switch(go)
          cover(covers.first.id) if covers
          v = call(plain)
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          @sp = base
          result
        end

        # The `to_s` of an interpolated part under refinements: a String or a
        # Symbol is the part as it is, and any other value gets the send.
        #: (Hir::Send node) -> String
        def interp_to_s(node)
          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = @f.label
          go = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          v = @f.fetch("i64", @rec, value_offset(slot))
          @f.brif(kernel("zr_interp_plain_p", v), plain, go)
          switch(plain)
          @f.jump(merge, [v])
          switch(go)
          plain_send = node.dup.tap do |n|
            n.recv = Hir::Slot.new(slot, node.line)
            n.interp = false
          end
          sent = call(plain_send)
          @f.jump(merge, [sent]) unless @f.terminated?
          switch(merge)
          @sp = base
          result
        end

        # In the core library, `Primitive.zr_name(args)` calls the kernel
        # def directly with Values. A block literal is its last Value, a
        # Proc, and its `break` comes here as for a send.
        #: (Hir::Send node) -> bool
        def primitive?(node)
          recv = node.recv
          return false unless @l.internal? && recv.is_a?(Hir::ConstRead)

          recv.name == :Primitive && recv.scope.nil?
        end

        #: (Hir::Send node) -> String
        def primitive(node)
          return @qnil if node.name == :attr!
          return parameter_named(node) if node.name == :arg!

          d = @l.kernel_def(node.name.to_s)
          given = node.args.size + (node.block ? 1 : 0)
          @l.refuse(node, "Primitive.#{node.name} takes #{d.params.size} arguments, not #{given}") if d.params.size != given
          @l.refuse(node, "Primitive.#{node.name} takes keywords") if node.kwargs
          @l.refuse(node, "Primitive.#{node.name} takes a block literal, not a block pass") if node.block.is_a?(Hir::BlockPass)
          d.params.each { |name, type| @l.refuse(node, "Primitive.#{node.name}'s #{name} is a #{type}, not a Value") unless type == "Value" }
          @l.refuse(node, "Primitive.#{node.name} answers a #{d.ret}, not a Value") unless d.ret == "Value"
          at_node(node)
          staged(node.args) do |_, base|
            args = node.args.each_index.map { |i| @f.fetch("i64", @rec, value_offset(base + i)) }
            if node.block
              site, block = make_block(node.block)
              catching_break(site) { kernel(node.name.to_s, *args, block) }
            else
              checked(kernel(node.name.to_s, *args))
            end
          end
        end

        # `Primitive.arg!(:in)`: the parameter with that name. Ruby cannot
        # write it as a variable when the name is a keyword. CRuby's builtin
        # methods read it the same way.
        #: (Hir::Send node) -> String
        def parameter_named(node)
          arg = node.args.first
          name = arg.value if arg.is_a?(Hir::Literal)
          i = @locals.index(name) if name.is_a?(Symbol)
          return read_local(i, 0, name) if i && name.is_a?(Symbol)

          @l.refuse(node, "Primitive.arg! names #{name}, which is no parameter here")
        end

        #: (Hir::Send node) -> bool
        def explicit?(node)
          !(node.recv.nil? || node.recv.is_a?(Hir::SelfRef))
        end

        # A traced program sends every operator, so a :c_call sees it.
        #: (Hir::Send node, String recv, String argv, String argc) -> String
        def send_staged(node, recv, argv, argc)
          note_eval_using(node) if eval_using?(node)
          if node.block && iterator_template?(node)
            iterate(node, recv, argv, argc)
          elsif node.block
            call_with_block(node, recv, argv, argc)
          # An operator takes one operand only when no splat spreads its arguments.
          elsif node.args.size == 1 && fixed_args?(node) && OPS.key?(node.name) && !node.vcall && !owner_using?(node) && !traced?
            operator(node, recv, argv)
          elsif node.args.empty? && node.kwargs.nil? && UNARY.key?(node.name) && explicit?(node) && !owner_using?(node) && !traced?
            unary(node, recv, argv)
          elsif node.name == :<=> && node.args.size == 1 && fixed_args?(node) && !node.vcall && native_operators? && !traced?
            native_compare(node, recv, argv)
          elsif node.name == :between? && node.args.size == 2 && fixed_args?(node) && explicit?(node) && native_operators? && !traced?
            # The core library's range checks of its own integers, which C
            # writes as two comparisons.
            checked(kernel("zr_native_between", recv, argv))
          else
            dispatch(node, recv, argv, argc)
          end.tap { deactivate(node) }
        end

        # Whether the call passes exactly its written arguments: no keywords,
        # and no splat that spreads an Array into them.
        #: (Hir::Send node) -> bool
        def fixed_args?(node) = node.kwargs.nil? && !Scope.spread?(node.args)

        # The calls whose string runs under the refinements of the call
        # site, or whose Binding keeps them for an eval.
        EVAL_USING = %i[eval instance_eval class_eval module_eval binding].freeze
        SENDS = %i[send __send__ public_send].freeze

        # A call of one of EVAL_USING, by its name or through a `send`
        # whose name is not a literal of another method.
        #: (Hir::Send node) -> bool
        def eval_using?(node)
          return true if EVAL_USING.include?(node.name)
          return false unless SENDS.include?(node.name) && !node.args.empty?

          name = node.args.first
          !name.is_a?(Hir::Literal) || EVAL_USING.include?(name.value)
        end

        # Tells the eval or binding call the `using` entry in force here
        # (the entry plus one; 0 for none). Every such call writes it, so
        # no call reads one that an earlier site left.
        #: (Hir::Send node) -> void
        def note_eval_using(node)
          using = node.using
          @f.store(imm(using.is_a?(Integer) ? using + 1 : 0), @task_addr, off(@task, "eval_using"), region: :task)
        end

        # Pushes `parts` one at a time into an Array in the record slot
        # `slot`. A Splat spreads its value. Returns the Array. The frame
        # stands at `at` (an Array literal), or else at the splat, while a
        # splat converts its value, as splatarray's node is.
        # With `spread`, the Array is the spread stack's (a call's).
        #: (Array[Hir::node?] parts, Integer slot, ?Hir::node? at, ?spread: bool) -> String
        def gather(parts, slot, at = nil, spread: false)
          @f.store(spread ? kernel("zr_spread_take") : kernel("zr_ary_new", imm(parts.size)), @rec, value_offset(slot))
          parts.each do |part|
            if part.is_a?(Hir::Splat)
              value = expr(part.value)
              site = at && @l.node_id(at) != 0 ? at : part
              at_node(site) if at && @l.node_id(site) != 0
              checked(kernel("zr_ary_splat", @f.fetch("i64", @rec, value_offset(slot)), value))
            else
              kernel("zr_ary_push", @f.fetch("i64", @rec, value_offset(slot)), expr(part))
            end
          end
          @f.fetch("i64", @rec, value_offset(slot))
        end

        #: (String ary) -> String
        def array_ptr(ary)
          @f.fetch("i64", ary, off(@l.layout("RArray"), "ptr"))
        end

        #: (String ary) -> String
        def array_len(ary)
          @f.fetch("i64", ary, off(@l.layout("RArray"), "len"))
        end

        # A call's keywords as arguments. `k: v` pairs with plain Symbol
        # keys go as trailing values, with a static table of the keys that
        # the task gets just before the send. All other keywords go as one
        # Hash that the task flags (lib/zr/runtime/kernel/send.rb).
        #: (Hir::Send | Hir::Super node) -> Array[Hir::node?]
        def keyword_args(node)
          kwargs = node.kwargs
          return [] unless kwargs
          unless Scope.literal_keywords?(kwargs)
            # The literal is a call's keywords: a lone `**h` is lent to the
            # callee, or copied for a Proc's call or yield, which pass it on
            # to a block (`hash_literal`, `keyword_argc`).
            (@keywords ||= {}.compare_by_identity)[kwargs] = lent_keywords?(node) ? :lent : :copied
            return [kwargs]
          end

          kwargs.pairs.each_slice(2).map(&:last)
        end

        # Whether the call's keywords are a lone `**h` that it lends.
        #: (Hir::Send | Hir::Super node) -> bool
        def lent_keywords?(node)
          kwargs = node.kwargs
          return false unless kwargs && kwargs.pairs.size == 2 && kwargs.pairs.first.is_a?(Hir::HashSplat)

          !(node.is_a?(Hir::Send) && %i[call yield].include?(node.name))
        end

        # The count that the callee sees: a keywords Hash goes last and
        # flags the task. A splat's last element can be a ruby2_keywords
        # Hash.
        #: (Hir::Send | Hir::Super node, String argc, String argv) -> String
        def keyword_argc(node, argc, argv)
          kwargs = node.kwargs
          if kwargs && Scope.literal_keywords?(kwargs)
            # `literal_keywords?` found a Symbol literal in each key.
            keys = kwargs.pairs.each_slice(2).map do |key, _|
              literal = key #: Hir::Literal
              literal.value #: Symbol
            end
            @f.store(@f.symbol_value(@f.symbol(@l.keyword_table([keys.size, *keys]))), @task_addr, off(@task, "kw"), region: :task)
            return argc
          end
          # Proc#call and Proc#yield pass a `**h` on to the block as a yield
          # does, also an empty one (vm_call_opt_call).
          return kernel("zr_kw_argc_lent", argc, argv) if lent_keywords?(node)
          return kernel(node.is_a?(Hir::Send) && %i[call yield].include?(node.name) ? "zr_kw_argc_yield" : "zr_kw_argc", argc, argv) if node.kwargs
          if node.args.any?(Hir::Splat)
            return kernel(node.is_a?(Hir::Send) && %i[call yield].include?(node.name) ? "zr_kw_ruby2_out_yield" : "zr_kw_ruby2_out", argc, argv)
          end

          argc
        end

        # The mode for `zr_dispatch`: 0 for an implicit or `self` receiver,
        # 1 for a bare identifier, 2 for an explicit receiver (visibility
        # applies).
        #: (Hir::Send node) -> Integer
        def send_mode(node)
          mode = if node.vcall then 1
                 elsif explicit?(node) && !@funcalls&.key?(node) then 2
                 else 0
                 end
          # A literal `send` in the core is rb_funcall: the program's own
          # method answers it, as any send from CRuby's C does.
          mode |= SEND_CORE if core_send?(node.name) && !@funcalls&.key?(node)
          mode |= SEND_INTERNAL if (@l.support? || @l.internal?) && !sends_all?
          node.using ? mode | SEND_USING : mode
        end

        # Whether a send of `name` finds the core's own method: in eval's
        # compiler for every name, as ruby's compiler is C that sends
        # nothing by name; in the core library for any name but PROTOCOL,
        # for `each` as CRuby's C sends it (`native_each?`), and for an
        # operator as CRuby's C sends it (`native_operators?`); never in a
        # def that CRuby writes in Ruby alone (`sends_all?`).
        #: (Symbol name) -> bool
        def core_send?(name)
          return true if @l.support?
          return false unless @l.internal?
          return false if sends_all?
          return native_operators? if Hir::CoreDef::SENT_OPS.include?(name)

          name == :each ? native_each? : !PROTOCOL.include?(name)
        end

        #: (Hir::Send node, String recv, String argv, String argc) -> String
        def dispatch(node, recv, argv, argc)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          if node.opt && !owner_using?(node) && !traced?
            checked(opt_send(node, recv, argc, argv))
          elsif node.name == :call && node.block.nil? && !owner_using?(node) && raw_block_recv?(node.recv)
            checked(kernel("zr_opt_block_call", recv, sym_word(:call), argc, argv, imm(send_mode(node))))
          elsif math_call?(node)
            checked(math_send(node, recv, argc, argv))
          elsif node.name == :new && !@l.plain_new?
            checked(new_send(node, recv, argc, argv, @qnil))
          else
            checked(cached_send(node, recv, argc, argv, @qnil))
          end
        end

        # Whether `node` is `Math.f(x)` (MATH_CALLS) with one plain argument.
        #: (Hir::Send node) -> bool
        def math_call?(node)
          recv = node.recv
          MATH_CALLS.key?(node.name) && recv.is_a?(Hir::ConstRead) && recv.name == :Math && [nil, :top].include?(recv.scope) &&
            node.args.size == 1 && !Scope.spread?(node.args) && node.block.nil? && node.kwargs.nil? && !owner_using?(node) && !traced?
        end

        # `Math.f(x)`: when the constant is Math (its class is Math's
        # singleton class) and its functions are the core's, the kernel's
        # fast path for a Float or an Integer, which Math's own method calls
        # first. Any other value, a value out of the domain, and any other
        # receiver make the send, which converts or raises.
        #: (Hir::Send node, String recv, String argc, String argv) -> String
        def math_send(node, recv, argc, argv)
          fast = @f.label
          heap = @f.label
          slow = @f.cold(@f.label)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          pointer = @f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil))
          @f.brif(pointer, heap, slow)
          switch(heap)
          klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
          @f.brif(@f.band(@f.icmp("eq", klass, global("G_MATH_META")), gates_clear("GATE_MATH")), fast, slow)
          switch(fast)
          x = @f.fetch("i64", argv)
          which = MATH_CALLS.fetch(node.name)
          r = which.zero? ? kernel("zr_math_sqrt_fast", x) : kernel("zr_math_call_fast", imm((which * 2) + 1), x)
          done = @f.label
          @f.brif(@f.icmp("eq", r, @qnil), slow, done)
          switch(done)
          @f.jump(merge, [r])
          switch(slow)
          @f.jump(merge, [cached_send(node, recv, argc, argv, @qnil)])
          switch(merge)
          result
        end

        # Whether `recv` reads a `&b` parameter bound to the block as given
        # (`Params#raw_block?`), in this scope or an enclosing scope.
        #: (Hir::node? recv) -> bool
        def raw_block_recv?(recv)
          recv.is_a?(Hir::Local) && scope_at(recv.depth).raw_block == recv.name
        end

        # `recv[i]`, `recv[i] = v` and `recv << v`. A receiver of a core
        # class with a fast path goes to the kernel's entry, which tests the
        # method's gate and calls it. All other receivers use the site's
        # cell.
        #: (Hir::Send node, String recv, String argc, String argv) -> String
        def opt_send(node, recv, argc, argv)
          entry, classes = OPT_ENTRIES.fetch(node.name)
          heap = @f.label
          core = @f.label
          other = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          pointer = @f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil))
          @f.brif(pointer, heap, other)
          switch(heap)
          klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
          if (owner = in_place_class(node))
            here = @f.label
            rest = @f.label
            @f.brif(@f.icmp("eq", klass, global(owner)), here, rest)
            switch(here)
            site = CallSite.new(node: node, recv: recv, argv: argv, merge: merge)
            owner == "G_ARRAY" ? array_element(site, core) : string_byte(node, recv, argv, merge, core)
            switch(rest)
            classes -= [owner]
          end
          if classes.empty?
            @f.jump(other)
          else
            @f.brif(classes.map { |g| @f.icmp("eq", klass, global(g)) }.reduce { |a, b| @f.bor(a, b) }, core, other)
          end
          switch(core)
          @f.jump(merge, [kernel(entry, recv, sym_word(node.name), argc, argv, imm(send_mode(node)))])
          switch(other)
          @f.jump(merge, [cached_send(node, recv, argc, argv, @qnil)])
          switch(merge)
          result
        end

        # The core class whose elements the site reads or writes inline, or
        # nil: an Array's by `[]` and `[]=`, a String's bytes by `getbyte`
        # and `setbyte`.
        #: (Hir::Send node) -> String?
        def in_place_class(node)
          if array_element?(node) then "G_ARRAY"
          elsif %i[getbyte setbyte].include?(node.name) then "G_STRING"
          end
        end

        # `recv[i]` and `recv[i] = v` with one plain index: for an Array
        # receiver, read or write the element inline.
        #: (Hir::Send node) -> bool
        def array_element?(node)
          return false unless %i[[] []=].include?(node.name)

          plain = node.kwargs.nil? && node.block.nil? && node.args.none?(Hir::Splat)
          plain && node.args.size == (node.name == :[] ? 1 : 2)
        end

        # The element of an Array `recv` at a fixnum index in range, while
        # Array's `[]` or `[]=` is not redefined (the gate) and, for a
        # write, the Array is not frozen. The value goes to `merge`. A
        # negative index, one past the end, and all other cases go to
        # `slow`, the kernel's entry.
        #: (CallSite site, String slow) -> void
        def array_element(site, slow)
          fast = @f.label
          index = @f.fetch("i64", site.argv)
          i = @f.sshr(index, imm(1))
          len = @f.fetch("i64", site.recv, off(@l.layout("RArray"), "len"))
          ok = @f.band(@f.icmp("ne", @f.band(index, imm(1)), imm(0)), @f.icmp("ult", i, len))
          ok = @f.band(ok, gate_clear(site.node.name == :[] ? "GATE_AREF" : "GATE_ASET"))
          if site.node.name == :[]=
            flags = @f.fetch("i64", site.recv, off(@l.layout("RBasic"), "flags"))
            ok = @f.band(ok, @f.icmp("eq", @f.band(flags, imm(@l.const("FL_FREEZE"))), imm(0)))
          end
          @f.brif(ok, fast, slow)
          switch(fast)
          at = @f.iadd(@f.fetch("i64", site.recv, off(@l.layout("RArray"), "ptr")), @f.ishl(i, imm(3)))
          if site.node.name == :[]
            @f.jump(site.merge, [@f.fetch("i64", at)])
          else
            value = @f.fetch("i64", site.argv, 8)
            @f.store(value, at, region: :malloc)
            cell_barrier(site.recv, value)
            @f.jump(site.merge, [value])
          end
        end

        # `s.getbyte(i)` and `s.setbyte(i, b)` on a String at a fixnum
        # index in range, with a fixnum byte, while String's method is not
        # redefined (the gate). Reads or writes the byte inline, as
        # zr_str_byte_at and zr_str_setbyte do. A write also needs a String
        # that is not frozen or chilled, and clears the cached scan data of
        # its bytes (zr_str_modified). A negative index, one past the end,
        # and all other cases go to `slow`, the kernel's entry, which raises
        # or returns nil as the method does. Without this, `bm_ruby_xor`
        # spends three fifths of its time in the entries.
        #: (Hir::Send node, String recv, String argv, String merge, String slow) -> void
        def string_byte(node, recv, argv, merge, slow)
          string = @l.layout("RString")
          fast = @f.label
          index = @f.fetch("i64", argv)
          i = @f.sshr(index, imm(1))
          ok = @f.band(@f.icmp("ne", @f.band(index, imm(1)), imm(0)), @f.icmp("ult", i, @f.fetch("i64", recv, off(string, "len"))))
          if node.name == :getbyte
            @f.brif(@f.band(ok, gate_clear("GATE_GETBYTE")), fast, slow)
            switch(fast)
            byte = @f.uextend("i64", @f.fetch("i8", @f.iadd(@f.fetch("i64", recv, off(string, "ptr")), i)))
            @f.jump(merge, [@f.bor(@f.ishl(byte, imm(1)), imm(1))])
          else
            byte = @f.fetch("i64", argv, 8)
            flags = @f.fetch("i64", recv, off(@l.layout("RBasic"), "flags"))
            sealed = @l.const("FL_FREEZE") | @l.const("FL_CHILLED")
            ok = @f.band(ok, @f.icmp("ne", @f.band(byte, imm(1)), imm(0)))
            ok = @f.band(ok, @f.icmp("eq", @f.band(flags, imm(sealed)), imm(0)))
            @f.brif(@f.band(ok, gate_clear("GATE_SETBYTE")), fast, slow)
            switch(fast)
            at = @f.iadd(@f.fetch("i64", recv, off(string, "ptr")), i)
            @f.store(@f.ireduce("i8", @f.sshr(byte, imm(1))), at, region: :malloc)
            @f.store(@f.band(flags, imm(@l.const("FL_SCANS_CLEAR"))), recv, off(@l.layout("RBasic"), "flags"))
            @f.jump(merge, [byte])
          end
        end

        # A send through the site's own cell (lib/zr/runtime/kernel/cache.rb). The
        # cell keeps the method of the last receiver class at this site.
        # The site tests the cell inline: a fixnum's class is Integer, a
        # flonum's is Float, and a heap object's class is in its header.
        # If that class is the cell's and the cell's stamp is the site
        # stamp, the site calls the cell's function with the method
        # signature. All other cases (a different special constant, a stale
        # cell, cells turned off) go to the kernel's send, which tests the
        # site's other cells and fills one. A site under `using` tests its
        # cell in the same way (the cell has the result of the lookup with
        # its refinements, and the task has the refinements for the
        # callee). A site in a `refine` block always calls the kernel.
        #: (Hir::Send node, String recv, String argc, String argv, String blk, ?mode: Integer, ?cc: String) -> String
        def cached_send(node, recv, argc, argv, blk, mode: send_mode(node), cc: site_cache(node, "ic", "CallCache", CALL_WAYS))
          slow = -> { kernel("zr_send_cached", cc, recv, sym_word(node.name), argc, argv, blk, imm(mode)) }
          return slow.call if owner_using?(node)

          cell = @l.layout("CallCache")
          shapes = site_shapes(node)
          # The labels are made in this order, before any code, so that a
          # build numbers them as it always has.
          fixnum = @f.label
          other = @f.label
          heap = @f.label
          # A site that can have an accessor shape gets a second word at the
          # join: whether the receiver is a cell. A fixnum and a flonum also
          # get here, and an accessor of Integer or Float would read through
          # a receiver that is not an address.
          own = shapes.intersect?(ACCESSOR_SHAPES)
          # `cellular` is nil unless `own`, and only then read.
          have, (klass, cellular) = @f.block(own ? %w[i64 i64] : %w[i64]) #: [String, [String, String]]
          reach = ->(k, cell_p) { @f.jump(have, own ? [k, imm(cell_p)] : [k]) }
          direct = @f.label
          miss = @f.cold(@f.label)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          nil_p = node.name == :nil? && node.args.empty? && node.block.nil? && node.kwargs.nil? && !traced?
          nil_before_class(recv, merge) if nil_p
          receiver_class(node, recv, reach, fixnum, other, heap)
          switch(have)
          nil_after_class(klass, merge) if nil_p
          question_gate(node, klass, argv, merge)
          same = @f.band(@f.icmp("eq", klass, @f.fetch("i64", cc, off(cell, "klass"))),
                         @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("site_stamp"))))
          @f.brif(same, direct, miss)
          switch(direct)
          entry = @f.fetch("i64", cc, off(cell, "entry"))
          site = CallSite.new(node: node, cc: cc, recv: recv, entry: entry, argv: argv, merge: merge)
          shape_hits(shapes, site, klass, cellular, miss) unless shapes.empty?
          found = @f.fetch("i64", cc, off(cell, "found"))
          direct_entry(site, blk, found) if direct_site?(node)
          fn = @f.fetch("i64", cc, off(cell, "fn"))
          args = [recv, argc, argv, entry, blk, found]
          @f.jump(merge, [@f.call_indirect_val(@f.sig(ABI.fetch(:def), "i64"), fn, args)])
          switch(miss)
          @f.jump(merge, [slow.call])
          switch(merge)
          result
        end

        # `x.nil?` while no class has defined the name (GATE_NIL_P): true
        # for nil here, before any class is read. False at `have` for a
        # receiver whose class is ranked (under Object, where Kernel's
        # `nil?` applies; `nil_after_class`). The cell for all others.
        #: (String recv, String merge) -> void
        def nil_before_class(recv, merge)
          is_nil = @f.label
          not_nil = @f.label
          @f.brif(@f.band(gate_clear("GATE_NIL_P"), @f.icmp("eq", recv, @qnil)), is_nil, not_nil)
          switch(is_nil)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(not_nil)
        end

        #: (String klass, String merge) -> void
        def nil_after_class(klass, merge)
          not_nil = @f.label
          cell_path = @f.label
          @f.brif(@f.band(gate_clear("GATE_NIL_P"), ranked?(klass)), not_nil, cell_path)
          switch(not_nil)
          @f.jump(merge, [imm(@l.const("QFALSE"))])
          switch(cell_path)
        end

        # Reaches the join with the receiver's class, and whether the
        # receiver is a cell. The compiler knows the class of a literal
        # symbol, nil, true or false receiver. For example, a `case` branch
        # on a symbol sends `:sym === x` to the literal.
        #: (Hir::Send node, String recv, ^(String, Integer) -> void reach, String fixnum, String other, String heap) -> void
        def receiver_class(node, recv, reach, fixnum, other, heap)
          known = literal_class(node.recv)
          return reach.call(global(known), 0) if known

          @f.brif(@f.icmp("ne", @f.band(recv, imm(1)), imm(0)), fixnum, other)
          switch(fixnum)
          reach.call(global("G_INTEGER"), 0)
          switch(other)
          if FLONUM_NAMES.include?(node.name)
            flonum = @f.label
            rest = @f.label
            @f.brif(@f.icmp("eq", @f.band(recv, imm(3)), imm(2)), flonum, rest)
            switch(flonum)
            reach.call(global("G_FLOAT"), 0)
            switch(rest)
          end
          special = @f.cold(@f.label)
          pointer = @f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil))
          @f.brif(pointer, heap, special)
          switch(heap)
          reach.call(@f.fetch("i64", recv, off(@l.layout("RBasic"), "klass")), 1)
          # nil, true, false, a symbol and a flonum each have a class, as a
          # fixnum does. A site that sends to one (`x.nil?` on nil, a
          # symbol's `to_proc`, `respond_to?` on a flag) hits its cell as
          # for a fixnum. The kernel reads the class with one call on this
          # slow path. Inline tests at every site would add a tenth to the
          # runtime's code.
          switch(special)
          reach.call(kernel("zr_class_of", recv), 0)
        end

        # `recv.is_a?(K)` uses only the receiver's class while no class
        # has defined the name (GATE_IS_A). It uses no cell, because a
        # site with receivers of many classes would thrash the cells.
        #: (Hir::Send node, String klass, String argv, String merge) -> void
        def question_gate(node, klass, argv, merge)
          gate = QUESTION_GATES[node.name]
          return unless gate && node.args.size == 1 && node.block.nil? && node.kwargs.nil? && !node.args[0].is_a?(Hir::Splat) && !traced?

          gated = @f.label
          cell_path = @f.label
          @f.brif(gate_clear(gate), gated, cell_path)
          switch(gated)
          if node.name == :instance_of?
            answered(kernel("zr_instance_of_fast", klass, @f.fetch("i64", argv, 0)), merge, cell_path)
          else
            is_a_in_place(klass, @f.fetch("i64", argv, 0), merge, cell_path)
          end
          switch(cell_path)
        end

        # A hit whose cell holds one of the site's shapes (an accessor, a
        # struct member, ...) runs the shape in place.
        #: (Array[Symbol] shapes, CallSite site, String klass, String cellular, String miss) -> void
        def shape_hits(shapes, site, klass, cellular, miss)
          call = @f.label
          held = @f.fetch("i64", site.cc, off(@l.layout("CallCache"), "shape"))
          shapes.each_with_index do |shape, i|
            onward = i == shapes.size - 1 ? call : @f.label
            wanted = @f.icmp("eq", held, imm(@l.const(SHAPES.fetch(shape))))
            if ACCESSOR_SHAPES.include?(shape)
              accessor_hits(shape, site, cellular, wanted, held, miss, onward)
            else
              here = @f.label
              @f.brif(wanted, here, onward)
              switch(here)
              in_place(shape, site, klass, call)
            end
            switch(onward)
          end
        end

        # An accessor's two shapes, each with its own body at the site: an
        # attr_reader's or attr_writer's first, then a struct member's. A
        # failed guard in either goes to `miss`, the kernel's send, which
        # sets the guess.
        #: (Symbol shape, CallSite site, String cellular, String wanted, String held, String miss, String onward) -> void
        def accessor_hits(shape, site, cellular, wanted, held, miss, onward)
          plain = @f.label
          member = @f.label
          struct = @f.label
          @f.brif(@f.band(cellular, wanted), plain, member)
          switch(plain)
          accessor_in_place(shape, site, miss)
          switch(member)
          @f.brif(@f.band(cellular, struct_member?(shape, held)), struct, onward)
          switch(struct)
          accessor_in_place(shape, site, miss, true)
        end

        # The def's direct entry, if the cell has one for this site's
        # count. The staged arguments go in registers, with no count and
        # no keyword word for the def to check.
        #: (CallSite site, String blk, String found) -> void
        def direct_entry(site, blk, found)
          fast = @f.label
          generic = @f.label
          direct = @f.fetch("i64", site.cc, off(@l.layout("CallCache"), "direct"))
          @f.brif(@f.icmp("ne", direct, imm(0)), fast, generic)
          switch(fast)
          n = site.node.args.size
          given = Array.new(n) { |i| @f.fetch("i64", site.argv, 8 * i) }
          # The unit's def with this name, if the direct entry is its body:
          # an inline copy of the body, which bails to the call (`Inline`).
          if (d = inline_candidate(site.node))
            copy = @f.label
            plain = @f.label
            @f.brif(@f.icmp("eq", direct, @f.func_addr(@f.callee(@l.def_name(d), ABI.fetch(Function.direct_abi(n)), "i64"))), copy, plain)
            switch(copy)
            @f.jump(site.merge, [inline_body(d, site.recv, given, plain)])
            switch(plain)
          end
          sig = @f.sig(ABI.fetch(Function.direct_abi(n)), "i64")
          @f.jump(site.merge, [@f.call_indirect_val(sig, direct, [site.recv, site.entry, blk, found, *given])])
          switch(generic)
        end

        # The send with a block: a descriptor for a block literal (the
        # site catches its own `break` on return), or the `&value`.
        #: (Hir::Send node, String recv, String argv, String argc) -> String
        def call_with_block(node, recv, argv, argc)
          if node.block.is_a?(Hir::BlockPass)
            # The site's refinements are active when `&value` becomes a
            # Proc, so `&:name` and a refined `to_proc` use them.
            value = expr(node.block.value)
            at_node(node)
            argc = keyword_argc(node, argc, argv)
            activate(node)
            proc = checked(kernel("zr_block_pass", value))
            # A program's `new(&blk)` is a send of Class#new with a frame,
            # also for `&nil`, as ruby compiles any block argument. The
            # core's `new` has no frame, as in C.
            return checked(node.name == :new && @l.internal? ? new_send(node, recv, argc, argv, proc) : cached_send(node, recv, argc, argv, proc))
          end

          # Not a `&value`, so a block literal.
          literal = node.block #: Hir::Block
          site, block = make_block(literal, method: node.name == :define_method)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          # ruby's opt_new takes no block: a traced program sends `new` with
          # one, so a :c_call sees Class#new.
          inline_new = node.name == :new && !traced? && !@l.plain_new?
          catching_break(site) { inline_new ? new_send(node, recv, argc, argv, block) : cached_send(node, recv, argc, argv, block) }
        end

        # `recv.new(...)`, with its block if it has one: the kernel's
        # opt_new, with a cell for `new` and one for `initialize`.
        #
        # A program's `Klass.new(...)` with no block does opt_new's work
        # inline while the cell has Class#new (SHAPE_NEW). It gets the
        # object from the class's allocator, then sends `initialize` as a
        # normal call, through the site's own cell. So a def's direct entry
        # gets the arguments in place. Class#new has no frame on this path,
        # as in the kernel. Any other receiver or `new`, or a stale cell,
        # uses the kernel's path, which fills the cell.
        #: (Hir::Send node, String recv, String argc, String argv, String blk) -> String
        def new_send(node, recv, argc, argv, blk)
          cc = cache("ic", "CallCache", 2 * CALL_WAYS)
          slow = -> { kernel("zr_new_cached", cc, recv, argc, argv, blk, imm(send_mode(node))) }
          return slow.call unless new_in_place?(node)

          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          miss = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil)), heap, miss)
          switch(heap)
          klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
          same = @f.band(@f.icmp("eq", klass, @f.fetch("i64", cc, off(cell, "klass"))),
                         @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("site_stamp"))))
          @f.brif(@f.band(same, @f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const("SHAPE_NEW")))), hit, miss)
          switch(hit)
          made = staged([checked(kernel("zr_class_new_object", recv))], evaluate: ->(value) { value }) do |slot|
            checked(cached_send(initializer(node), @f.fetch("i64", slot), argc, argv, @qnil,
                                cc: site_cache(node, "init", "CallCache", CALL_WAYS)))
            @f.fetch("i64", slot)
          end
          @f.jump(merge, [made])
          switch(miss)
          @f.jump(merge, [slow.call])
          switch(merge)
          result
        end

        # Whether a `new` site uses the inline path: in a program (not the
        # core), with an explicit receiver (so the cell has only a public
        # `new`), with no block (a `new` with a block calls Class#new with
        # a frame), not traced, and not in a `refine` block.
        #: (Hir::Send node) -> bool
        def new_in_place?(node)
          explicit?(node) && node.block.nil? && !@l.internal? && !traced? && !owner_using?(node)
        end

        # The `initialize` that a `new` site sends to its object: an
        # implicit call, private permitted, with the site's arguments.
        #: (Hir::Send node) -> Hir::Send
        def initializer(node)
          node.dup.tap do |n|
            n.recv = nil
            n.name = :initialize
            n.opt = false
          end
        end

        # The block literal's descriptor and its site number. The
        # descriptor is a Proc image in a slot of this record, written
        # only by stores. It is not a cell unless a kernel def keeps the
        # block (`zr_block_proc`, lib/zr/runtime/kernel/proc.rb). Its flags mark
        # it as on the stack and already marked, so the collector reads
        # nothing through it. This frame roots all that it refers to.
        #: (Hir::Block block, ?method: bool) -> [Integer, String]
        def make_block(block, method: false)
          fn = @l.block(block, self, method: method)
          site = (@sites += 1)
          # The target of a `return` in the block. A block in a method
          # refers to that method's frame. A block in another block refers
          # to the outer block's target, unless the outer block is a lambda.
          # A lambda is the innermost frame that a return can leave, so the
          # target is known only when the proc is called.
          serial = frame_serial
          ret_home, ret_serial = if @kind == :block
                                   [@f.csel(lambda?, @rec, proc_field("ret_home")), @f.csel(lambda?, serial, proc_field("ret_serial"))]
                                 else
                                   [@rec, serial]
                                 end
          fields = {
            "fn" => @f.func_addr(@f.callee(fn, ABI.fetch(:block), "i64")),
            "meta" => @f.symbol_value(@f.symbol("zr_meta_#{fn}")),
            "env" => @env, "self" => @self, "cref" => @cref, "blk" => @blk,
            "home" => @rec, "serial" => serial, "site" => imm(site),
            "ret_home" => ret_home, "ret_serial" => ret_serial,
            "spread" => imm(block.params.spread? ? 1 : 0), "lambda" => imm(0), "passed" => imm(0)
          }
          desc = @f.stack_addr(@f.slot(@proc_layout.size))
          basic = @l.layout("RBasic")
          @f.store(imm(%w[T_PROC FL_ALLOCATED FL_STACK].sum { |c| @l.const(c) }), desc, off(basic, "flags"))
          @f.store(global("G_PROC"), desc, off(basic, "klass"))
          fields.each { |name, v| @f.store(v, desc, off(@proc_layout, name)) }
          [site, desc]
        end

        # The result of the block's call. A `break` from the block literal
        # at `site` gives the result. Any other unwind goes to the landing
        # block.
        #: (Integer site) { () -> String } -> String
        def catching_break(site)
          r = yield
          fine = @f.label
          signal = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("eq", r, qundef), signal, fine)
          switch(fine)
          @f.jump(merge, [r])
          switch(signal)
          caught = kernel("zr_catch_break", @rec, imm(site))
          ours = @f.label
          @f.brif(@f.icmp("eq", caught, qundef), landing, ours)
          switch(ours)
          @f.jump(merge, [caught])
          switch(merge)
          result
        end

        # `super(args)`: the arguments are staged as for a send, then the
        # runtime finds the next method after this frame's owner. A bare
        # `super` in a block first checks whether `define_method` made the
        # block a method, because CRuby raises for that case.
        #: (Hir::Super node) -> String
        def super_call(node)
          if node.in_block
            at_node(node)
            checked(kernel("zr_zsuper_in_block", @rec))
          end
          args = node.args + keyword_args(node)
          if args.any?(Hir::Splat)
            staged([], 1) do |_, base|
              ary = gather(args, base)
              super_staged(node, array_ptr(ary), array_len(ary))
            end
          else
            staged(args) { |slots| super_staged(node, slots, imm(args.size)) }
          end
        end

        #: (Hir::Super node, String argv, String argc) -> String
        def super_staged(node, argv, argc)
          site = nil #: Integer?
          blk = case node.block
                when nil then @blk
                when Hir::BlockPass then checked(kernel("zr_block_pass", expr(node.block.value)))
                else
                  site, block = make_block(node.block)
                  block
                end
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          call = -> { kernel("zr_super", cache("sc", "SuperCache"), @rec, argc, argv, blk) }
          (site ? catching_break(site, &call) : checked(call.call)).tap { deactivate(node) }
        end

        # A bare `super` that the builder could not expand (no enclosing
        # def). The runtime raises for it.
        #: (Hir::ZSuper node) -> String
        def zsuper(node)
          at_node(node)
          checked(kernel("zr_zsuper_outside", @rec))
        end
      end
    end
  end
end
