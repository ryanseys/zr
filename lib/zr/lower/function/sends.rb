# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Method calls: the receiver and arguments staged in the record, the
      # dispatch, the block-passing form, and the inline fixnum operators.
      module Sends
        # The operators with an inline fixnum fast path, and their gates.
        OPS = {
          :+ => "GATE_PLUS", :- => "GATE_MINUS", :* => "GATE_MUL", :/ => "GATE_DIV", :% => "GATE_MOD",
          :< => "GATE_LT", :<= => "GATE_LE", :> => "GATE_GT", :>= => "GATE_GE", :== => "GATE_EQ", :!= => "GATE_NE",
          :& => "GATE_AND", :| => "GATE_OR", :^ => "GATE_XOR", :>> => "GATE_SHR"
        }.freeze
        # The comparison operators among them, as the IR's signed
        # conditions on the tagged words.
        RELATIONS = { :< => "slt", :<= => "sle", :> => "sgt", :>= => "sge", :== => "eq", :!= => "ne" }.freeze

        # What a site can do in place of a call, by the kernel's name for the
        # cell's shape (lib/zr/runtime/kernel/cache.rb): an accessor's body, or one of
        # the core's type checks. The two accessors read and write a cell's
        # table, so their receiver must be a cell. The type checks accept any
        # receiver.
        SHAPES = {
          reader: "SHAPE_READER", writer: "SHAPE_WRITER", is_a: "SHAPE_IS_A", instance_of: "SHAPE_INSTANCE_OF",
          nil_p: "SHAPE_NIL_P", frozen_p: "SHAPE_FROZEN_P", ary_length: "SHAPE_ARY_LENGTH", mod_eqq: "SHAPE_MOD_EQQ",
          eq: "SHAPE_EQ", ne: "SHAPE_NE", eqq: "SHAPE_EQQ"
        }.freeze
        ACCESSOR_SHAPES = %i[reader writer].freeze
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
        }.freeze
        # The type checks that a site handles before its cell, while no
        # class has defined the name (lib/zr/runtime/kernel/integer.rb).
        QUESTION_GATES = { is_a?: "GATE_IS_A", kind_of?: "GATE_IS_A", instance_of?: "GATE_INSTANCE_OF" }.freeze

        # The kernel entry of each operator and named call with a core
        # fast path, and the classes that it handles. The named calls are
        # in `Hir::Build::OPT_CALLS`, which marks the call.
        OPT_ENTRIES = {
          :[] => ["zr_opt_aref", %w[G_ARRAY G_HASH]], :[]= => ["zr_opt_aset", %w[G_ARRAY G_HASH]], :<< => ["zr_opt_ltlt", %w[G_ARRAY G_STRING]],
          getbyte: ["zr_opt_getbyte", %w[G_STRING]], setbyte: ["zr_opt_setbyte", %w[G_STRING]],
          push: ["zr_opt_push", %w[G_ARRAY]], pop: ["zr_opt_pop", %w[G_ARRAY]], shift: ["zr_opt_shift", %w[G_ARRAY]],
          empty?: ["zr_opt_empty_p", %w[G_ARRAY]]
        }.freeze
        # The unary Integer calls with an inline fixnum fast path, and
        # their gates.
        UNARY = { succ: "GATE_SUCC", :-@ => "GATE_UMINUS" }.freeze
        # The unary calls with a flonum path as well, and Float's gates.
        FLOAT_UNARY = { :-@ => "GATE_FLO_UMINUS" }.freeze
        # The operators with a flonum path: the f64 instruction or the
        # fcmp condition, and the gate of Float's method.
        FLOAT_OPS = {
          :+ => [:fadd, "GATE_FLO_PLUS"], :- => [:fsub, "GATE_FLO_MINUS"], :* => [:fmul, "GATE_FLO_MUL"], :/ => [:fdiv, "GATE_FLO_DIV"],
          :< => ["lt", "GATE_FLO_LT"], :<= => ["le", "GATE_FLO_LE"], :> => ["gt", "GATE_FLO_GT"], :>= => ["ge", "GATE_FLO_GE"],
          :== => ["eq", "GATE_FLO_EQ"]
        }.freeze
        # The bits of +0.0 as a flonum, and of the double that the rotation
        # cannot represent (lib/zr/runtime/kernel/float.rb).
        FLONUM_ZERO = 9223372036854775810 - (1 << 64)
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
        ].to_set.freeze
        # The flag bit of a send in the core library (SEND_CORE).
        SEND_CORE = 8
        # The flag bit of a send under `using` (SEND_USING). Its cells
        # contain the result of the lookup with the site's refinements.
        SEND_USING = 16
        # The number of cells of a send site (lib/zr/runtime/kernel/cache.rb, CALL_WAYS).
        CALL_WAYS = 4
        # The names that numeric code sends to a Float. Their sites find a
        # flonum's class inline. All other sites let the kernel read a
        # flonum's class, to keep the code small.
        FLONUM_NAMES = (OPS.keys + %i[
          ** -@ +@ <=> to_i to_f to_s to_r round floor ceil truncate abs divmod fdiv quo
          nan? finite? infinite? zero? positive? negative? coerce
        ]).to_set.freeze

        private

        # The receiver and arguments go into record slots (a splat collects
        # them into one Array there), then keywords as a Hash that the task
        # flags, then the send.
        def call(node)
          return safe_call(node) if node.safe
          return interp_to_s(node) if node.interp
          return call(funcall(node)) if kernel_send?(node)
          return primitive(node) if primitive?(node)

          recv_node = node.recv || Hir::SelfRef.new(node.line)
          return direct_operator(node, recv_node) if direct_operands?(node, recv_node)

          args = node.args + keyword_args(node)
          if args.any?(Hir::Splat)
            staged([recv_node], 1) do |slots, base|
              ary = gather(args, base + 1)
              # A write returns the value that it wrote (the last collected
              # element), not the writer's return value.
              last = node.write ? kernel("zr_ary_at", ary, @f.isub(array_len(ary), imm(1))) : nil
              r = send_staged(node, @f.fetch("i64", slots), array_ptr(ary), array_len(ary))
              node.write ? last : r
            end
          else
            staged([recv_node, *args]) do |slots|
              r = send_staged(node, @f.fetch("i64", slots), @f.iadd(slots, imm(8)), imm(args.size))
              node.write ? @f.fetch("i64", slots, 8 * node.args.size) : r
            end
          end
        end

        # An operator site whose operands are plain reads (a local, self, an
        # immediate literal: nothing that calls or allocates) tests them
        # directly. It stages them in the record only on the send branch, so
        # the fast branch stores and releases nothing. A unary operator has
        # one operand, and nothing runs between its read and the test, so
        # any receiver is permitted.
        def direct_operands?(node, recv_node)
          return false if node.block || node.kwargs || node.write || node.vcall || owner_using?(node) || traced?

          if node.args.size == 1 && OPS.key?(node.name)
            plain_read?(recv_node) && plain_read?(node.args.first)
          else
            node.args.empty? && UNARY.key?(node.name) && explicit?(node)
          end
        end

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

        def direct_operator(node, recv_node)
          recv = expr(recv_node)
          args = node.args.map { |a| expr(a) }
          slow = -> { sent_directly(node, recv, args) }
          (args.empty? ? unary(node, recv, nil, &slow) : operator(node, recv, nil, args.first, &slow)).tap { deactivate(node) }
        end

        # The send of an operator whose operands were read as values. They
        # are staged in the record only here, on the send branch.
        def sent_directly(node, recv, args)
          staged([recv, *args], evaluate: ->(value) { value }) do |slots|
            dispatch(node, recv, @f.iadd(slots, imm(8)), imm(args.size))
          end
        end

        # Whether a test of `node` branches on the comparison itself: a
        # comparison of plain reads (`direct_operands?`).
        def relation_test?(node)
          node.is_a?(Hir::Send) && RELATIONS.key?(node.name) && direct_operands?(node, node.recv || Hir::SelfRef.new(node.line))
        end

        # `a < b` and the other comparisons as a test (`Control#jump_if`).
        # The fixnum and flonum paths branch on the comparison, so no true
        # or false is made only to be tested again (for example, fib's
        # `n < 2` or a loop's `i < n`). The call's result is tested as a
        # value.
        def relation_jump(node, yes, no)
          recv = expr(node.recv || Hir::SelfRef.new(node.line))
          arg = expr(node.args.first)
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label if float_path?(node)
          @f.brif(@f.band(fixnums?(recv, arg), gate_clear(OPS.fetch(node.name))), fast, floating || slow)
          switch(fast)
          @f.brif(@f.icmp(RELATIONS.fetch(node.name), recv, arg), yes, no)
          if floating
            switch(floating)
            x, y = doubles(node.name, recv, arg, slow)
            @f.brif(@f.fcmp(FLOAT_OPS.fetch(node.name).first, x, y), yes, no)
          end
          switch(slow)
          native_equality(node, recv, arg) { |equal| @f.brif(equal, yes, no) }
          v = sent_directly(node, recv, [arg])
          deactivate(node)
          @f.brif(truthy(v), yes, no) unless @f.terminated?
        end

        # In the runtime's own Ruby, `recv.send(:name, ...)` is rb_funcall
        # in CRuby's C: a direct call of `name`, private permitted, and
        # never a class's own `send` (BasicSocket has one). The call uses
        # its own cell, with no send frame and no lookup by name. For all
        # names except PROTOCOL, the core's own method entry is used, as
        # for every other call that the core makes.
        def kernel_send?(node)
          @l.internal? && %i[send __send__].include?(node.name) && node.args.first.is_a?(Hir::Literal) &&
            node.args.first.value.is_a?(Symbol) && !%i[send __send__ public_send].include?(node.args.first.value)
        end

        # The call that a kernel send gives, marked so it can call a
        # private method with any receiver (`send_mode`).
        def funcall(node)
          named = node.dup.tap do |n|
            n.name = node.args.first.value
            n.args = node.args.drop(1)
          end
          (@funcalls ||= {}.compare_by_identity)[named] = true
          named
        end

        # `recv&.name(args)`: nil if the receiver is nil, with the arguments
        # not evaluated; else the send.
        def safe_call(node)
          # `self&.x` is `self.x`: self is never nil, and the receiver stays
          # a literal self for the visibility rule. Coverage counts the
          # call, and never counts the nil branch.
          if node.recv.is_a?(Hir::SelfRef)
            cover(node.covers.first.id) if node.covers
            return call(node.dup.tap { |n| n.safe = false })
          end

          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = Hir::Send.of(Hir::Slot.new(slot, node.line), node.name, node.args, node.line,
                                opt: node.opt, block: node.block, kwargs: node.kwargs, write: node.write, using: node.using)
          is_nil = @f.label
          go = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", @f.fetch("i64", @rec, value_offset(slot)), @qnil), is_nil, go)
          switch(is_nil)
          cover(node.covers.last.id) if node.covers
          @f.jump(merge, [@qnil])
          switch(go)
          cover(node.covers.first.id) if node.covers
          v = call(plain)
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          @sp = base
          result
        end

        # The `to_s` of an interpolated part under refinements: a String or a
        # Symbol is the part as it is, and any other value gets the send.
        def interp_to_s(node)
          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = @f.label
          go = @f.label
          merge, (result,) = @f.block(["i64"])
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
        def primitive?(node)
          @l.internal? && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive && node.recv.scope.nil?
        end

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
        def parameter_named(node)
          name = node.args.first.value
          i = @locals.index(name) or @l.refuse(node, "Primitive.arg! names #{name}, which is no parameter here")
          read_local(i, 0, name)
        end

        def explicit?(node)
          !(node.recv.nil? || node.recv.is_a?(Hir::SelfRef))
        end

        # A traced program sends every operator, so a :c_call sees it.
        def send_staged(node, recv, argv, argc)
          if node.block && iterator_template?(node)
            iterate(node, recv, argv, argc)
          elsif node.block
            call_with_block(node, recv, argv, argc)
          elsif node.args.size == 1 && node.kwargs.nil? && OPS.key?(node.name) && !node.vcall && !owner_using?(node) && !traced?
            operator(node, recv, argv)
          elsif node.args.empty? && node.kwargs.nil? && UNARY.key?(node.name) && explicit?(node) && !owner_using?(node) && !traced?
            unary(node, recv, argv)
          elsif node.name == :<=> && node.args.size == 1 && node.kwargs.nil? && !node.vcall && native_operators? && !traced?
            native_compare(node, recv, argv)
          elsif node.name == :between? && node.args.size == 2 && node.kwargs.nil? && explicit?(node) && native_operators? && !traced?
            # The core library's range checks of its own integers, which C
            # writes as two comparisons.
            checked(kernel("zr_native_between", recv, argv))
          else
            dispatch(node, recv, argv, argc)
          end.tap { deactivate(node) }
        end

        # Pushes `parts` one at a time into an Array in the record slot
        # `slot`. A Splat spreads its value. Returns the Array.
        def gather(parts, slot)
          @f.store(kernel("zr_ary_new", imm(parts.size)), @rec, value_offset(slot))
          parts.each do |part|
            if part.is_a?(Hir::Splat)
              checked(kernel("zr_ary_splat", @f.fetch("i64", @rec, value_offset(slot)), expr(part.value)))
            else
              kernel("zr_ary_push", @f.fetch("i64", @rec, value_offset(slot)), expr(part))
            end
          end
          @f.fetch("i64", @rec, value_offset(slot))
        end

        def array_ptr(ary)
          @f.fetch("i64", ary, off(@l.layout("RArray"), "ptr"))
        end

        def array_len(ary)
          @f.fetch("i64", ary, off(@l.layout("RArray"), "len"))
        end

        # A call's keywords as arguments. `k: v` pairs with plain Symbol
        # keys go as trailing values, with a static table of the keys that
        # the task gets just before the send. All other keywords go as one
        # Hash that the task flags (lib/zr/runtime/kernel/send.rb).
        def keyword_args(node)
          return [] unless node.kwargs
          return [node.kwargs] unless Scope.literal_keywords?(node.kwargs)

          node.kwargs.pairs.each_slice(2).map(&:last)
        end

        # The count that the callee sees: a keywords Hash goes last and
        # flags the task. A splat's last element can be a ruby2_keywords
        # Hash.
        def keyword_argc(node, argc, argv)
          if node.kwargs && Scope.literal_keywords?(node.kwargs)
            keys = node.kwargs.pairs.each_slice(2).map { |key, _| key.value }
            @f.store(@f.symbol_value(@f.symbol(@l.keyword_table([keys.size, *keys]))), @task_addr, off(@task, "kw"), region: :task)
            return argc
          end
          return kernel("zr_kw_argc", argc, argv) if node.kwargs
          return kernel("zr_kw_ruby2_out", argc, argv) if node.args.any?(Hir::Splat)

          argc
        end

        # The mode for `zr_dispatch`: 0 for an implicit or `self` receiver,
        # 1 for a bare identifier, 2 for an explicit receiver (visibility
        # applies).
        def send_mode(node)
          mode = if node.vcall then 1
                 elsif explicit?(node) && !@funcalls&.key?(node) then 2
                 else 0
                 end
          mode |= SEND_CORE if core_send?(node.name)
          node.using ? mode | SEND_USING : mode
        end

        # Whether a send of `name` finds the core's own method: in the
        # core library and eval's compiler, for any name but PROTOCOL, and
        # for `each` as CRuby's C sends it (`native_each?`).
        def core_send?(name)
          return false unless @l.internal? || @l.support?

          name == :each ? native_each? : !PROTOCOL.include?(name)
        end

        def dispatch(node, recv, argv, argc)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          if node.opt && !owner_using?(node) && !traced?
            checked(opt_send(node, recv, argc, argv))
          elsif node.name == :call && node.block.nil? && !owner_using?(node) && raw_block_recv?(node.recv)
            checked(kernel("zr_opt_block_call", recv, sym_word(:call), argc, argv, imm(send_mode(node))))
          elsif node.name == :new
            checked(new_send(node, recv, argc, argv, @qnil))
          else
            checked(cached_send(node, recv, argc, argv, @qnil))
          end
        end

        # Whether `recv` reads a `&b` parameter bound to the block as given
        # (`Params#raw_block?`), in this scope or an enclosing scope.
        def raw_block_recv?(recv)
          recv.is_a?(Hir::Local) && scope_at(recv.depth).raw_block == recv.name
        end

        # `recv[i]`, `recv[i] = v` and `recv << v`. A receiver of a core
        # class with a fast path goes to the kernel's entry, which tests the
        # method's gate and calls it. All other receivers use the site's
        # cell.
        def opt_send(node, recv, argc, argv)
          entry, classes = OPT_ENTRIES.fetch(node.name)
          heap = @f.label
          core = @f.label
          other = @f.label
          merge, (result,) = @f.block(["i64"])
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
        def in_place_class(node)
          if array_element?(node) then "G_ARRAY"
          elsif %i[getbyte setbyte].include?(node.name) then "G_STRING"
          end
        end

        # `recv[i]` and `recv[i] = v` with one plain index: for an Array
        # receiver, read or write the element inline.
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
            sealed = @l.const("FL_FREEZE") | @l.const("FL_CHILLED") | @l.const("FL_CHILLED_SYMBOL")
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
          have, (klass, cellular) = @f.block(own ? %w[i64 i64] : %w[i64])
          reach = ->(k, cell_p) { @f.jump(have, own ? [k, imm(cell_p)] : [k]) }
          direct = @f.label
          miss = @f.cold(@f.label)
          merge, (result,) = @f.block(["i64"])
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
        def nil_before_class(recv, merge)
          is_nil = @f.label
          not_nil = @f.label
          @f.brif(@f.band(gate_clear("GATE_NIL_P"), @f.icmp("eq", recv, @qnil)), is_nil, not_nil)
          switch(is_nil)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(not_nil)
        end

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
        def shape_hits(shapes, site, klass, cellular, miss)
          call = @f.label
          held = @f.fetch("i64", site.cc, off(@l.layout("CallCache"), "shape"))
          shapes.each_with_index do |shape, i|
            here = @f.label
            onward = i == shapes.size - 1 ? call : @f.label
            wanted = @f.icmp("eq", held, imm(@l.const(SHAPES.fetch(shape))))
            wanted = @f.bor(wanted, struct_member?(shape, held)) if ACCESSOR_SHAPES.include?(shape)
            @f.brif(ACCESSOR_SHAPES.include?(shape) ? @f.band(cellular, wanted) : wanted, here, onward)
            switch(here)
            in_place(shape, site, klass, call, miss, held)
            switch(onward)
          end
        end

        # The def's direct entry, if the cell has one for this site's
        # count. The staged arguments go in registers, with no count and
        # no keyword word for the def to check.
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

          site, block = make_block(node.block)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          catching_break(site) { node.name == :new ? new_send(node, recv, argc, argv, block) : cached_send(node, recv, argc, argv, block) }
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
        def new_send(node, recv, argc, argv, blk)
          cc = cache("ic", "CallCache", 2 * CALL_WAYS)
          slow = -> { kernel("zr_new_cached", cc, recv, argc, argv, blk, imm(send_mode(node))) }
          return slow.call unless new_in_place?(node)

          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          miss = @f.label
          merge, (result,) = @f.block(["i64"])
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
        def new_in_place?(node)
          explicit?(node) && node.block.nil? && !@l.internal? && !traced? && !owner_using?(node)
        end

        # The `initialize` that a `new` site sends to its object: an
        # implicit call, private permitted, with the site's arguments.
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
        def make_block(block)
          fn = @l.block(block, self)
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
        def catching_break(site)
          r = yield
          fine = @f.label
          signal = @f.label
          merge, (result,) = @f.block(["i64"])
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

        def super_staged(node, argv, argc)
          site = nil
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
        def zsuper(node)
          at_node(node)
          checked(kernel("zr_zsuper_outside", @rec))
        end
      end
    end
  end
end
