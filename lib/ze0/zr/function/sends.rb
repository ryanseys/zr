# frozen_string_literal: true

module Ze0
  module Zr
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

        # What a site may do in place of a call, by the kernel's name for the
        # cell's shape (rt/kernel/cache.rb): an accessor's body, or one of the
        # core's type questions. The two accessors read and write a cell's
        # table, so their receiver must be a cell; the questions take any.
        SHAPES = {
          reader: "SHAPE_READER", writer: "SHAPE_WRITER", is_a: "SHAPE_IS_A", instance_of: "SHAPE_INSTANCE_OF",
          nil_p: "SHAPE_NIL_P", frozen_p: "SHAPE_FROZEN_P", ary_length: "SHAPE_ARY_LENGTH", mod_eqq: "SHAPE_MOD_EQQ",
          eq: "SHAPE_EQ", ne: "SHAPE_NE", eqq: "SHAPE_EQQ"
        }.freeze
        ACCESSOR_SHAPES = %i[reader writer].freeze
        # The questions of no argument, and of one, a site answers by name.
        # `nil?` and `frozen?` cannot name an attribute, so no reader is
        # tested for them.
        QUESTIONS = { nil?: [:nil_p], frozen?: [:frozen_p], size: %i[ary_length reader], length: %i[ary_length reader] }.freeze
        # `===` is what `case` asks of each `when`, and Module's answers the
        # class tests a `case` over objects is made of. `==`, `equal?` and
        # `!=` are identity where the cell holds BasicObject's.
        ARGUED = {
          is_a?: [:is_a], kind_of?: [:is_a], instance_of?: [:instance_of], "===": %i[mod_eqq eqq],
          "==": [:eq], equal?: [:eq], "!=": [:ne]
        }.freeze
        # The type questions a site answers before its cell, while no
        # class has defined the name (rt/kernel/integer.rb).
        QUESTION_GATES = { is_a?: "GATE_IS_A", kind_of?: "GATE_IS_A", instance_of?: "GATE_INSTANCE_OF" }.freeze

        # The kernel entry of each operator and named call with a core
        # fast path, and the classes it answers for. The named ones are
        # `Hir::Build::OPT_CALLS`, which marks the call.
        OPT_ENTRIES = {
          :[] => ["zr_opt_aref", %w[G_ARRAY G_HASH]], :[]= => ["zr_opt_aset", %w[G_ARRAY G_HASH]], :<< => ["zr_opt_ltlt", %w[G_ARRAY G_STRING]],
          getbyte: ["zr_opt_getbyte", %w[G_STRING]], setbyte: ["zr_opt_setbyte", %w[G_STRING]],
          push: ["zr_opt_push", %w[G_ARRAY]], pop: ["zr_opt_pop", %w[G_ARRAY]], shift: ["zr_opt_shift", %w[G_ARRAY]],
          empty?: ["zr_opt_empty_p", %w[G_ARRAY]]
        }.freeze
        # The unary Integer calls with an inline fixnum fast path, and
        # their gates.
        UNARY = { succ: "GATE_SUCC" }.freeze
        # The operators with a flonum path: the f64 instruction or the
        # fcmp condition, and the gate of Float's method.
        FLOAT_OPS = {
          :+ => [:fadd, "GATE_FLO_PLUS"], :- => [:fsub, "GATE_FLO_MINUS"], :* => [:fmul, "GATE_FLO_MUL"], :/ => [:fdiv, "GATE_FLO_DIV"],
          :< => ["lt", "GATE_FLO_LT"], :<= => ["le", "GATE_FLO_LE"], :> => ["gt", "GATE_FLO_GT"], :>= => ["ge", "GATE_FLO_GE"],
          :== => ["eq", "GATE_FLO_EQ"]
        }.freeze
        # The bits of +0.0 as a flonum, and of the double the rotation
        # cannot carry (rt/kernel/float.rb).
        FLONUM_ZERO = 9223372036854775810 - (1 << 64)
        FLONUM_HOLE = 3458764513820540928

        # The names CRuby's C sends by name even to its own classes'
        # instances, so the method a program defines answers them: the
        # conversions, equality, hashing and ordering, iteration, the
        # object protocol and its hooks, and what error reporting asks.
        # Any other send the core library makes to an instance of a class
        # the runtime made reaches the core library's own method, as a
        # call in C reaches a C function (rt/kernel/send.rb, SEND_CORE).
        PROTOCOL = %i[
          initialize initialize_copy initialize_dup initialize_clone
          to_s inspect to_str to_sym to_proc to_ary to_a to_hash to_h to_int to_i to_f to_r to_c to_path to_io to_regexp
          == != eql? hash <=> === =~ ! coerce
          each call write warn default
          respond_to? respond_to_missing? method_missing
          method_added singleton_method_added method_removed singleton_method_removed method_undefined
          singleton_method_undefined inherited included extended prepended const_added const_missing
          marshal_dump marshal_load _dump _load
          exception message backtrace full_message detailed_message
        ].to_set.freeze
        # The bit a send of the core library carries (SEND_CORE).
        SEND_CORE = 8
        # The bit a send under `using` carries (SEND_USING): its cells
        # hold what the lookup under the site's own refinements answered.
        SEND_USING = 16
        # The cells a send site owns (rt/kernel/cache.rb, CALL_WAYS).
        CALL_WAYS = 4
        # The names a Float is sent in numeric code, whose sites find a
        # flonum's class inline; any other site leaves a flonum to the
        # kernel, which reads its class as well, for the code's sake.
        FLONUM_NAMES = (OPS.keys + %i[
          ** -@ +@ <=> to_i to_f to_s to_r round floor ceil truncate abs divmod fdiv quo
          nan? finite? infinite? zero? positive? negative? coerce
        ]).to_set.freeze

        private

        # The receiver and arguments wait in record slots (a splat gathers
        # them into one Array there), keywords last as a Hash the task
        # flags, then the send.
        def call(node)
          return call(node.dup.tap { |n| n.name = :__send__ }) if kernel_send?(node)
          return safe_call(node) if node.safe
          return primitive(node) if primitive?(node)

          recv_node = node.recv || Hir::SelfRef.new(node.line)
          args = node.args + keyword_args(node)
          if args.any?(Hir::Splat)
            staged([recv_node], 1) do |slots, base|
              ary = gather(args, base + 1)
              # A write answers the value it wrote, which is the last thing
              # gathered, not whatever the writer returned.
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

        # In the runtime's own Ruby, `recv.send(:name, ...)` is Kernel#send,
        # as rb_funcall is in CRuby's C: a class with a `send` of its own,
        # BasicSocket's, does not take the call. It goes as `__send__`.
        def kernel_send?(node)
          @l.internal? && node.name == :send && node.args.first.is_a?(Hir::Literal) && node.args.first.value.is_a?(Symbol)
        end

        # `recv&.name(args)`: nil when the receiver is, with the arguments
        # left unevaluated; else the send.
        def safe_call(node)
          # `self&.x` is `self.x`: self is never nil, and the receiver
          # stays a literal self for the visibility rule. Coverage still
          # counts the call, and never counts the nil side.
          if node.recv.is_a?(Hir::SelfRef)
            cover(node.covers.first.id) if node.covers
            return call(node.dup.tap { |n| n.safe = false })
          end

          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = Hir::Send.new(Hir::Slot.new(slot, node.line), node.name, node.args, node.line, false, node.opt, node.block, node.kwargs, false, node.write, node.using)
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

        # In the core library, `Primitive.zr_name(args)` is the kernel def
        # itself, called directly with Values. A block literal is its last
        # Value, a Proc, whose `break` lands here as a send's would.
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

        # `Primitive.arg!(:in)`: the parameter of that name, which Ruby
        # cannot spell as a variable when the name is a keyword, as CRuby's
        # builtin methods read it.
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
          else
            dispatch(node, recv, argv, argc)
          end.tap { deactivate(node) }
        end

        # `parts` pushed one by one into an Array kept in the record slot
        # `slot`; a Splat spreads its value. Answers the Array.
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

        # The count the callee sees: a keywords Hash goes last and flags
        # the task; a splat's last element may be a ruby2_keywords Hash.
        # A call's keywords among its arguments: `k: v` pairs with plain
        # Symbol keys go as trailing values under a static table of the
        # keys, told to the task right before the send; any other
        # keywords as one Hash the task flags (rt/kernel/send.rb).
        def keyword_args(node)
          return [] unless node.kwargs
          return [node.kwargs] unless Scope.literal_keywords?(node.kwargs)

          node.kwargs.pairs.each_slice(2).map(&:last)
        end

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

        # `using mod` fills the row it names, so every send under it
        # reads what this module refines. It answers the self it ran on.
        def using_row(node)
          at_node(node)
          checked(kernel("zr_using_activate", imm(node.id), expr(node.value), imm(node.from)))
          @self
        end

        # The refinements in force where this call is written, told to
        # the task so the lookup sees them -- and so a callee that looks
        # up under them sees them too, as `send`, `respond_to?` and
        # `&:name` do in ruby, whichever road the site takes. A `using`
        # row is one element of the activation table, read here in
        # place: the kernel is asked only for a row not made yet or one
        # that forwards to the row before it (a `using` a condition
        # skipped), and inside a `refine` block, where the list is the
        # owner's and no row numbers it.
        def activate(node)
          return if node.using.nil?
          return kernel("zr_activate_owner", @rec) if owner_using?(node)

          rows = global("G_ACTIVATIONS")
          ask = @f.label
          read = @f.label
          have = @f.label
          merge = @f.label
          array = @l.layout("RArray")
          @f.brif(@f.band(@f.icmp("eq", @f.band(rows, imm(7)), imm(0)), @f.icmp("ugt", rows, @qnil)), read, ask)
          switch(read)
          made = @f.icmp("slt", imm(node.using), @f.fetch("i64", rows, off(array, "len")))
          @f.brif(made, have, ask)
          switch(have)
          row = @f.fetch("i64", @f.fetch("i64", rows, off(array, "ptr")), 8 * node.using)
          plain = @f.label
          @f.brif(@f.icmp("eq", @f.band(row, imm(1)), imm(0)), plain, ask)
          switch(plain)
          @f.store(row, @task_addr, off(@task, "refine"), region: :task)
          @f.jump(merge, [])
          switch(ask)
          kernel("zr_activate", imm(node.using))
          @f.jump(merge, [])
          switch(merge)
        end

        # The refinements told for this send alone, taken back after it:
        # a callee of the kernel's leaves the word as it found it, and
        # the next plain site must not read it as its own.
        def deactivate(node)
          return if node.using.nil?

          @f.store(@qnil, @task_addr, off(@task, "refine"), region: :task)
        end

        # Whether the site stands inside a `refine` block: its list is
        # its owner's, which the kernel reads at every send it makes.
        def owner_using?(node)
          node.using == :owner
        end

        # The mode `zr_dispatch` takes: 0 for an implicit or `self`
        # receiver, 1 for a bare identifier, 2 for an explicit receiver,
        # which visibility applies to.
        def send_mode(node)
          mode = node.vcall ? 1 : (explicit?(node) ? 2 : 0)
          mode |= SEND_CORE if @l.internal? && !PROTOCOL.include?(node.name)
          node.using ? mode | SEND_USING : mode
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

        # Whether `recv` reads a `&b` parameter bound as the block it was
        # given (`Params#raw_block?`), here or in a scope around this one.
        def raw_block_recv?(recv)
          recv.is_a?(Hir::Local) && scope_at(recv.depth).raw_block == recv.name
        end

        # `recv[i]`, `recv[i] = v` and `recv << v`: a receiver of a core
        # class with a fast path takes the kernel's entry, which tests the
        # method's gate and calls it; any other receiver takes the site's
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
          if array_element?(node)
            array = @f.label
            rest = @f.label
            @f.brif(@f.icmp("eq", klass, global("G_ARRAY")), array, rest)
            switch(array)
            array_element(node, recv, argv, merge, core)
            switch(rest)
            classes -= ["G_ARRAY"]
          end
          builtin = classes.map { |g| @f.icmp("eq", klass, global(g)) }.reduce { |a, b| @f.bor(a, b) }
          @f.brif(builtin, core, other)
          switch(core)
          @f.jump(merge, [kernel(entry, recv, sym_word(node.name), argc, argv, imm(send_mode(node)))])
          switch(other)
          @f.jump(merge, [cached_send(node, recv, argc, argv, @qnil)])
          switch(merge)
          result
        end

        # `recv[i]` and `recv[i] = v` with one plain index: an Array
        # receiver reads or writes the element in place.
        def array_element?(node)
          return false unless %i[[] []=].include?(node.name)

          plain = node.kwargs.nil? && node.block.nil? && node.args.none? { |a| a.is_a?(Hir::Splat) }
          plain && node.args.size == (node.name == :[] ? 1 : 2)
        end

        # The element of an Array `recv` at a fixnum index in range, while
        # Array's `[]` or `[]=` is its own (the gate) and, for a write,
        # the Array is not frozen: the value goes to `merge`. A negative
        # index, one past the end and every other case take `slow`, the
        # kernel's entry, as before.
        def array_element(node, recv, argv, merge, slow)
          fast = @f.label
          index = @f.fetch("i64", argv)
          i = @f.sshr(index, imm(1))
          len = @f.fetch("i64", recv, off(@l.layout("RArray"), "len"))
          ok = @f.band(@f.icmp("ne", @f.band(index, imm(1)), imm(0)), @f.icmp("ult", i, len))
          ok = @f.band(ok, gate_clear(node.name == :[] ? "GATE_AREF" : "GATE_ASET"))
          if node.name == :[]=
            flags = @f.fetch("i64", recv, off(@l.layout("RBasic"), "flags"))
            ok = @f.band(ok, @f.icmp("eq", @f.band(flags, imm(@l.const("FL_FREEZE"))), imm(0)))
          end
          @f.brif(ok, fast, slow)
          switch(fast)
          at = @f.iadd(@f.fetch("i64", recv, off(@l.layout("RArray"), "ptr")), @f.ishl(i, imm(3)))
          if node.name == :[]
            @f.jump(merge, [@f.fetch("i64", at)])
          else
            value = @f.fetch("i64", argv, 8)
            @f.store(value, at, region: :malloc)
            cell_barrier(recv, value)
            @f.jump(merge, [value])
          end
        end

        # A send through the site's own cell (rt/kernel/cache.rb), which
        # keeps the method the receiver's class answered there last. The
        # site tests the cell itself: a fixnum's class is Integer, a
        # flonum's Float, a heap object's is in its header, and when
        # that class is the cell's and the cell's stamp is the site
        # stamp, the cell's function is called with the method
        # signature. Anything else -- another special constant, a stale
        # cell, the cells off -- is the kernel's send, which tests the
        # site's other cells and fills one. A site under `using` tests
        # its cell as any does (the cell holds what the lookup under its
        # refinements answered, and the task holds the refinements for
        # the callee); one inside a `refine` block asks the kernel every
        # time.
        def cached_send(node, recv, argc, argv, blk, mode: send_mode(node))
          cc = site_cache(node, "ic", "CallCache", CALL_WAYS)
          slow = -> { kernel("zr_send_cached", cc, recv, sym_word(node.name), argc, argv, blk, imm(mode)) }
          return slow.call if owner_using?(node)

          cell = @l.layout("CallCache")
          shapes = site_shapes(node)
          fixnum = @f.label
          other = @f.label
          heap = @f.label
          # A site that may carry an accessor takes a second word at the
          # join: whether the receiver is a cell. A fixnum and a flonum
          # reach here too, and an accessor of Integer's or Float's would
          # be read through a receiver that is no address at all.
          own = shapes.intersect?(ACCESSOR_SHAPES)
          have, (klass, cellular) = @f.block(own ? %w[i64 i64] : %w[i64])
          reach = ->(k, cell_p) { @f.jump(have, own ? [k, imm(cell_p)] : [k]) }
          direct = @f.label
          miss = @f.label
          merge, (result,) = @f.block(["i64"])
          # `x.nil?` while no class has defined the name (GATE_NIL_P):
          # true for nil here, before any class is read; false at `have`
          # for a receiver whose class is ranked (Object's family, which
          # is where Kernel's answer holds); the cell for the rest.
          nil_p = node.name == :nil? && node.args.empty? && node.block.nil? && node.kwargs.nil? && !traced?
          if nil_p
            is_nil = @f.label
            not_nil = @f.label
            @f.brif(@f.band(gate_clear("GATE_NIL_P"), @f.icmp("eq", recv, @qnil)), is_nil, not_nil)
            switch(is_nil)
            @f.jump(merge, [imm(@l.const("QTRUE"))])
            switch(not_nil)
          end
          # A receiver written as a symbol, nil, true or false has the
          # class the compiler knows: a `case` arm over a symbol asks
          # `:sym === x` of the literal.
          if (known = literal_class(node.recv))
            reach.call(global(known), 0)
          else
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
            special = @f.label
            pointer = @f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil))
            @f.brif(pointer, heap, special)
            switch(heap)
            reach.call(@f.fetch("i64", recv, off(@l.layout("RBasic"), "klass")), 1)
            # nil, true, false, a symbol and a flonum have a class as a
            # fixnum has, and a site that sends to one -- `x.nil?` on a
            # nil, a symbol's `to_proc`, `respond_to?` on a flag -- hits
            # its cell as a fixnum does. The kernel reads the class: one
            # call on this side road, where the tests written out at every
            # site cost the runtime a tenth of its code.
            switch(special)
            reach.call(kernel("zr_class_of", recv), 0)
          end
          switch(have)
          if nil_p
            not_nil = @f.label
            cell_road = @f.label
            @f.brif(@f.band(gate_clear("GATE_NIL_P"), ranked?(klass)), not_nil, cell_road)
            switch(not_nil)
            @f.jump(merge, [imm(@l.const("QFALSE"))])
            switch(cell_road)
          end
          # `recv.is_a?(K)` answers by the receiver's class alone while
          # no class has defined the name (GATE_IS_A): no cell to hit,
          # which a site whose receivers are of a dozen classes thrashed.
          if (gate = QUESTION_GATES[node.name]) && node.args.size == 1 && node.block.nil? && node.kwargs.nil? && !node.args[0].is_a?(Hir::Splat) && !traced?
            gated = @f.label
            cell_road = @f.label
            @f.brif(gate_clear(gate), gated, cell_road)
            switch(gated)
            if node.name == :instance_of?
              answered(kernel("zr_instance_of_fast", klass, @f.fetch("i64", argv, 0)), merge, cell_road)
            else
              is_a_in_place(klass, @f.fetch("i64", argv, 0), merge, cell_road)
            end
            switch(cell_road)
          end
          same = @f.band(@f.icmp("eq", klass, @f.fetch("i64", cc, off(cell, "klass"))),
                         @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("site_stamp"))))
          @f.brif(same, direct, miss)
          switch(direct)
          entry = @f.fetch("i64", cc, off(cell, "entry"))
          unless shapes.empty?
            call = @f.label
            held = @f.fetch("i64", cc, off(cell, "shape"))
            shapes.each_with_index do |shape, i|
              here = @f.label
              onward = i == shapes.size - 1 ? call : @f.label
              wanted = @f.icmp("eq", held, imm(@l.const(SHAPES.fetch(shape))))
              @f.brif(ACCESSOR_SHAPES.include?(shape) ? @f.band(cellular, wanted) : wanted, here, onward)
              switch(here)
              in_place(shape, recv, klass, entry, argv, merge, call, miss)
              switch(onward)
            end
          end
          found = @f.fetch("i64", cc, off(cell, "found"))
          if direct_site?(node)
            # The def's direct entry, where the cell holds one for this
            # site's count: the staged arguments go in registers, with
            # no count and no keyword word for the def to check.
            fast = @f.label
            generic = @f.label
            direct = @f.fetch("i64", cc, off(cell, "direct"))
            @f.brif(@f.icmp("ne", direct, imm(0)), fast, generic)
            switch(fast)
            n = node.args.size
            given = n.times.map { |i| @f.fetch("i64", argv, 8 * i) }
            # The def of the unit the name guesses at, where the direct
            # entry is its body: the body's copy here, bailing to the
            # call (`Inline`).
            if (d = inline_candidate(node))
              copy = @f.label
              plain = @f.label
              @f.brif(@f.icmp("eq", direct, @f.func_addr(@f.callee(@l.def_name(d), ABI.fetch(Function.direct_abi(n)), "i64"))), copy, plain)
              switch(copy)
              @f.jump(merge, [inline_body(d, recv, given, plain)])
              switch(plain)
            end
            @f.jump(merge, [@f.call_indirect_val(@f.sig(ABI.fetch(Function.direct_abi(n)), "i64"), direct, [recv, entry, blk, found, *given])])
            switch(generic)
          end
          fn = @f.fetch("i64", cc, off(cell, "fn"))
          args = [recv, argc, argv, entry, blk, found]
          @f.jump(merge, [@f.call_indirect_val(@f.sig(ABI.fetch(:def), "i64"), fn, args)])
          switch(miss)
          @f.jump(merge, [slow.call])
          switch(merge)
          result
        end

        # The global of the class a literal receiver is an instance of, or
        # nil: a Symbol has no singleton class, nor have nil, true and
        # false.
        def literal_class(recv)
          return nil unless recv.is_a?(Hir::Literal)

          case recv.value
          when Symbol then "G_SYMBOL"
          when nil then "G_NIL"
          when true then "G_TRUE"
          when false then "G_FALSE"
          end
        end

        # Whether a site may take a def's direct entry: positional
        # arguments alone, four at most, so its count is its own to
        # prove.
        def direct_site?(node)
          node.args.size <= DIRECT_ARGS && node.kwargs.nil? && node.args.none?(Hir::Splat)
        end

        # The shapes a site may carry, in the order it tests them: what its
        # own form allows, before the cell says at run time whether the
        # entry it holds is one (rt/kernel/cache.rb, `zr_entry_shape`).
        # Every one wants a call with no block, no keywords and no splat,
        # and exactly the arguments the body takes -- none for a reader or
        # a question, one for a writer, `is_a?` or `instance_of?` -- since
        # any other count raises, and only the call raises it. A type
        # question is picked by name, so only a site that spells it pays
        # for its test; `size` and `length` may be Array's or a reader's,
        # and test both. A traced program keeps the call, as `opt_send`
        # does.
        def site_shapes(node)
          return [] if node.block || node.kwargs || node.args.any?(Hir::Splat) || traced?

          case node.args.size
          when 0 then QUESTIONS.fetch(node.name) { [:reader] }
          when 1 then ARGUED.fetch(node.name) { node.name.end_with?("=") ? [:writer] : [] }
          else []
          end
        end

        # What a site does where the cell's shape is `shape`. An accessor's
        # guard that fails goes to `miss`, the kernel's send (which sets the
        # guess); a question the fast answer leaves open goes to `call`, the
        # cell's own function, which the cell has already found to stand.
        def in_place(shape, recv, klass, entry, argv, merge, call, miss)
          case shape
          when :reader, :writer then accessor_in_place(shape, recv, entry, argv, merge, miss)
          when :nil_p then @f.jump(merge, [ruby_bool(@f.icmp("eq", recv, @qnil))])
          when :frozen_p then frozen_in_place(recv, merge)
          when :ary_length then @f.jump(merge, [@f.bor(@f.ishl(array_len(recv), imm(1)), imm(1))])
          when :is_a then answered(kernel("zr_is_a_fast", klass, @f.fetch("i64", argv, 0)), merge, call)
          when :instance_of then answered(kernel("zr_instance_of_fast", klass, @f.fetch("i64", argv, 0)), merge, call)
          when :mod_eqq then mod_eqq_in_place(recv, @f.fetch("i64", argv, 0), merge, call)
          when :eq, :eqq then @f.jump(merge, [ruby_bool(@f.icmp("eq", recv, @f.fetch("i64", argv, 0)))])
          when :ne then @f.jump(merge, [ruby_bool(@f.icmp("ne", recv, @f.fetch("i64", argv, 0)))])
          end
        end

        # `Mod === obj` where the cell holds Module#===: a ranked class
        # receiver answers from the classes in place; a module, or a
        # class not ranked yet, asks the kernel, and what it leaves open
        # goes to `call`.
        def mod_eqq_in_place(recv, obj, merge, call)
          classed = @f.label
          asked = @f.label
          @f.brif(ranked?(recv), classed, asked)
          switch(classed)
          is_a_in_place(class_of(obj), recv, merge, call)
          switch(asked)
          answered(kernel("zr_mod_eqq_fast", recv, obj), merge, call)
        end

        # Whether `klass`, a class, is ranked (FL_RANKED): in Object's
        # family with its rank table built, and in no box.
        def ranked?(klass)
          @f.icmp("ne", @f.band(@f.fetch("i64", klass, off(@l.layout("RBasic"), "flags")), imm(@l.const("FL_RANKED"))), imm(0))
        end

        # The class of any value: a cell's from its header, the rest from
        # the kernel.
        def class_of(v)
          cell = @f.label
          special = @f.label
          have, (klass,) = @f.block(["i64"])
          @f.brif(@f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil)), cell, special)
          switch(cell)
          @f.jump(have, [@f.fetch("i64", v, off(@l.layout("RBasic"), "klass"))])
          switch(special)
          @f.jump(have, [kernel("zr_class_of", v)])
          switch(have)
          klass
        end

        # `klass.is_a?(mod)` written out, as `zr_is_a_fast` answers it:
        # where `mod` is a ranked class too, `mod`'s rank names the one
        # place in `klass`'s table it can be. Anything else -- a module,
        # a class whose table is not built yet, a box's view -- goes to
        # `open`, the road that calls, which builds the tables.
        def is_a_in_place(klass, mod, merge, open)
          ext_of = @l.layout("RClass")
          ext = @l.layout("ClassExt")
          cell = @f.label
          ranked = @f.label
          within = @f.label
          above = @f.label
          cellp = @f.band(@f.icmp("eq", @f.band(mod, imm(7)), imm(0)), @f.icmp("ugt", mod, @qnil))
          @f.brif(cellp, cell, open)
          switch(cell)
          @f.brif(@f.band(ranked?(mod), ranked?(klass)), ranked, open)
          switch(ranked)
          r = @f.fetch("i64", @f.fetch("i64", mod, off(ext_of, "ext")), off(ext, "rank"))
          mine = @f.fetch("i64", klass, off(ext_of, "ext"))
          @f.brif(@f.icmp("ule", r, @f.fetch("i64", mine, off(ext, "rank"))), within, above)
          switch(within)
          at = @f.iadd(@f.fetch("i64", mine, off(ext, "supers")), @f.ishl(@f.isub(r, imm(1)), imm(3)))
          @f.jump(merge, [ruby_bool(@f.icmp("eq", @f.fetch("i64", at, 0), mod))])
          switch(above)
          @f.jump(merge, [imm(@l.const("QFALSE"))])
        end

        # `frozen?` as `zr_frozen_p` reads it: every special constant is
        # frozen, and a cell says so in its flags. Written out here rather
        # than called, since the kernel's answer is a Bool, which wasm
        # carries as an i32 where every Value is an i64.
        def frozen_in_place(recv, merge)
          cell = @f.label
          special = @f.label
          @f.brif(@f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil)), cell, special)
          switch(special)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(cell)
          flags = @f.fetch("i64", recv, off(@l.layout("RBasic"), "flags"))
          @f.jump(merge, [ruby_bool(@f.icmp("ne", @f.band(flags, imm(@l.const("FL_FREEZE"))), imm(0)))])
        end

        # A fast answer, or nil where it leaves the question to the call.
        def answered(v, merge, call)
          settled = @f.label
          @f.brif(@f.icmp("eq", v, @qnil), call, settled)
          switch(settled)
          @f.jump(merge, [v])
        end

        def ruby_bool(cond) = @f.csel(cond, imm(@l.const("QTRUE")), imm(@l.const("QFALSE")))

        # An accessor's whole body at the site. The cell said its entry is
        # one, and the site has already found the receiver's class to be
        # the cell's, so what is left is the receiver's kind, the ractor
        # and the row the entry guesses -- the three tests
        # `guessed_ivar_row` makes for `@name` of this frame's own. A
        # receiver that is not a plain object, a ractor, a frozen receiver
        # under the writer, or a guess that does not hold goes to `slow`,
        # the kernel's send, which calls the accessor as it always did and
        # is what sets the guess.
        #
        # The keyword word is cleared as the accessor clears it: a hit
        # here is the call that would have.
        def accessor_in_place(shape, recv, entry, argv, merge, slow)
          table = @l.layout("IvTab")
          row = @l.layout("IvEntry")
          meta = @l.layout("MEntry")
          plain = @f.label
          indexed = @f.label
          hit = @f.label
          @f.store(imm(0), @task_addr, off(@task, "kw"), region: :task)
          mask = @l.const("T_MASK") | (shape == :writer ? @l.const("FL_FREEZE") : 0)
          kind = @f.band(@f.fetch("i64", recv, off(@l.layout("RBasic"), "flags")), imm(mask))
          outside = @f.icmp("eq", @f.fetch("i64", @task_addr, off(@task, "ractor")), imm(0))
          @f.brif(@f.band(@f.icmp("eq", kind, imm(@l.const("T_OBJECT"))), outside), plain, slow)
          switch(plain)
          t = @f.iadd(recv, imm(off(@l.layout("RObject"), "iv")))
          i = @f.fetch("i64", @f.iadd(entry, imm(off(meta, "ivar"))), off(@l.layout("IvarCache"), "index"))
          @f.brif(@f.icmp("ult", i, @f.fetch("i64", t, off(table, "len"))), indexed, slow)
          switch(indexed)
          at = @f.iadd(@f.fetch("i64", t, off(table, "rows")), @f.ishl(i, imm(Math.log2(row.size).to_i)))
          @f.brif(@f.icmp("eq", @f.fetch("i64", at, off(row, "id")), @f.fetch("i64", entry, off(meta, "fn"))), hit, slow)
          switch(hit)
          if shape == :writer
            v = @f.fetch("i64", argv, 0)
            @f.store(v, at, off(row, "value"), region: :malloc)
            cell_barrier(recv, v)
            @f.jump(merge, [v])
          else
            held = @f.fetch("i64", at, off(row, "value"))
            @f.jump(merge, [@f.csel(@f.icmp("eq", held, qundef), @qnil, held)])
          end
        end

        # The send with a block: a descriptor for a block literal, with
        # the site's own `break` caught on the way out, or the `&value`.
        def call_with_block(node, recv, argv, argc)
          if node.block.is_a?(Hir::BlockPass)
            proc = checked(kernel("zr_block_pass", expr(node.block.value)))
            at_node(node)
            argc = keyword_argc(node, argc, argv)
            activate(node)
            return checked(node.name == :new ? new_send(node, recv, argc, argv, proc) : cached_send(node, recv, argc, argv, proc))
          end

          site, block = make_block(node.block)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          catching_break(site) { node.name == :new ? new_send(node, recv, argc, argv, block) : cached_send(node, recv, argc, argv, block) }
        end

        # `recv.new(...)`, with its block if it has one: the kernel's
        # opt_new, a cell for `new` and one for `initialize`.
        def new_send(node, recv, argc, argv, blk)
          kernel("zr_new_cached", cache("ic", "CallCache", 2 * CALL_WAYS), recv, argc, argv, blk, imm(send_mode(node)))
        end

        # The block literal's descriptor and its site number. The
        # descriptor is a Proc's image in a slot of this record, written
        # by stores alone: no cell, unless a kernel def keeps the block
        # (`zr_block_proc`, rt/kernel/proc.rb). Its flags say it is a
        # stack's and marked already, so the collector reads nothing
        # through it: what it names, this frame roots.
        def make_block(block)
          fn = @l.block(block, self)
          site = (@sites += 1)
          # Where a `return` written in the block lands. A block inside a
          # method names that method's frame. A block inside another block
          # names what that block names, unless the block is a lambda:
          # a lambda is the innermost frame a return can leave, so the
          # answer is known only when the proc is called.
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

        # The block's call answered; a `break` from the block literal at
        # `site` is the answer, any other signal takes the landing block.
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

        # `super(args)`: the arguments staged as for a send, then the
        # runtime finds the next method past this frame's owner. A bare
        # `super` in a block asks first whether the block is a method
        # `define_method` made, where CRuby refuses it.
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

        # A bare `super` the builder could not expand, one with no def
        # around it: the runtime raises for it.
        def zsuper(node)
          at_node(node)
          checked(kernel("zr_zsuper_outside", @rec))
        end

        # An Integer operator: the fixnum fast path inline when both sides
        # are fixnums and the gate is clear, else the call. Equality takes
        # the call for any other operand too: `1 == 1.0` is true, and
        # `1 == obj` asks `obj == 1`.
        def operator(node, recv, argv)
          arg = @f.fetch("i64", argv)
          both = @f.band(recv, arg)
          fix = @f.icmp("ne", @f.band(both, imm(1)), imm(0))
          ok = @f.band(fix, gate_clear(OPS.fetch(node.name)))
          fast = @f.label
          slow = @f.label
          floating = @f.label if float_path?(node)
          merge, (result,) = @f.block(["i64"])
          @f.brif(ok, fast, floating || slow)
          switch(fast)
          value = fast_path(node.name, recv, arg, slow)
          @f.jump(merge, [value])
          if floating
            switch(floating)
            @f.jump(merge, [float_path(node.name, recv, arg, slow)])
          end
          switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv, imm(1))])
          switch(merge)
          result
        end

        # `recv.succ` on a fixnum while Integer's `succ` is its own: the
        # sum inline, the call past the fixnums or under a redefinition.
        # `bm_ruby_xor` counts with `i.succ`, and every call of it was a
        # send.
        def unary(node, recv, argv)
          fix = @f.icmp("ne", @f.band(recv, imm(1)), imm(0))
          ok = @f.band(fix, gate_clear(UNARY.fetch(node.name)))
          fast = @f.label
          slow = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(ok, fast, slow)
          switch(fast)
          @f.jump(merge, [overflow_or(@f.sadd_overflow(recv, imm(2)), slow)])
          switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv, imm(0))])
          switch(merge)
          result
        end

        # Whether the site gets the flonum path (`float_path`), which is
        # some forty instructions: an operator with one, unless an
        # operand is an Integer literal of a sum, a difference or a
        # comparison, which count and index far more often than they
        # meet a Float (`x * 2` and `x / 2` keep it).
        def float_path?(node)
          return false unless FLOAT_OPS.key?(node.name)
          return true if %i[* /].include?(node.name)

          [node.recv, node.args.first].none? { |n| n.is_a?(Hir::Literal) && n.value.is_a?(Integer) }
        end

        # The flonum path: both operands flonums, or one a flonum and
        # the other a fixnum (within 2^53 for a comparison, which ruby
        # makes exactly), with Integer's and Float's gates for the
        # operator both clear; the arithmetic on doubles, answered as a
        # flonum again or the kernel's heap Float; a comparison as
        # ruby's, false with a NaN. Anything else takes `slow`.
        def float_path(op, a, b, slow)
          fop, gate = FLOAT_OPS.fetch(op)
          compare = fop.is_a?(String)
          go = @f.label
          numbers = @f.band(number?(a, compare), number?(b, compare))
          some_flonum = @f.bor(flonum?(a), flonum?(b))
          gates = gates_clear(OPS.fetch(op), gate)
          @f.brif(@f.band(@f.band(numbers, some_flonum), gates), go, slow)
          switch(go)
          x = as_double(a)
          y = as_double(b)
          return @f.csel(@f.fcmp(fop, x, y), imm(@l.const("QTRUE")), imm(@l.const("QFALSE"))) if compare

          float_value(@f.fbinop(fop, x, y))
        end

        def flonum?(v) = @f.icmp("eq", @f.band(v, imm(3)), imm(2))

        # A flonum or a fixnum, the fixnum within 2^53 either way when
        # `exact`.
        def number?(v, exact)
          fix = @f.icmp("ne", @f.band(v, imm(1)), imm(0))
          fix = @f.band(fix, @f.icmp("ult", @f.iadd(@f.sshr(v, imm(1)), imm(1 << 53)), imm(1 << 54))) if exact
          @f.bor(flonum?(v), fix)
        end

        # The double a flonum or a fixnum `v` holds: `zr_float_value`'s
        # rotation, +0.0 for the flonum zero, a fixnum converted.
        def as_double(v)
          sign = @f.ushr(v, imm(63))
          x = @f.bor(@f.isub(imm(2), sign), @f.band(v, imm(-4)))
          rotated = @f.bor(@f.ushr(x, imm(3)), @f.ishl(x, imm(61)))
          decoded = @f.csel(@f.icmp("eq", v, imm(FLONUM_ZERO)), imm(0), rotated)
          converted = @f.bitcast("i64", @f.fcvt_from_sint(@f.sshr(v, imm(1))))
          @f.bitcast("f64", @f.csel(flonum?(v), decoded, converted))
        end

        # `zr_float_new` inline: a flonum when the exponent's top bits
        # are 011 or 100, the flonum zero for +0.0, else the kernel's
        # cell.
        def float_value(d)
          b = @f.bitcast("i64", d)
          top = @f.band(@f.ushr(b, imm(60)), imm(7))
          fits = @f.band(@f.icmp("ne", b, imm(FLONUM_HOLE)), @f.icmp("ult", @f.isub(top, imm(3)), imm(2)))
          rotated = @f.bor(@f.ishl(b, imm(3)), @f.ushr(b, imm(61)))
          flonum = @f.bor(@f.band(rotated, imm(-2)), imm(2))
          rotate = @f.label
          other = @f.label
          zero = @f.label
          heap = @f.label
          merge, (v,) = @f.block(["i64"])
          @f.brif(fits, rotate, other)
          switch(rotate)
          @f.jump(merge, [flonum])
          switch(other)
          @f.brif(@f.icmp("eq", b, imm(0)), zero, heap)
          switch(zero)
          @f.jump(merge, [imm(FLONUM_ZERO)])
          switch(heap)
          @f.jump(merge, [kernel("zr_float_new", d)])
          switch(merge)
          v
        end

        # The tagged result of `op` on tagged fixnums `a` and `b`; a
        # result outside the fixnum range takes `slow`.
        def fast_path(op, a, b, slow)
          one = imm(1)
          case op
          when :+ then overflow_or(@f.sadd_overflow(a, @f.isub(b, one)), slow)
          when :- then @f.bor(overflow_or(@f.ssub_overflow(a, b), slow), one)
          when :* then @f.bor(overflow_or(@f.smul_overflow(@f.sshr(a, one), @f.isub(b, one)), slow), one)
          when :/, :%
            # -2^62 / -1 leaves the fixnum range: that pair takes the call.
            x = @f.sshr(a, one)
            y = @f.sshr(b, one)
            unless_equal(y, 0, slow)
            unless_equal(y, -1, slow) if op == :/
            @f.bor(@f.ishl(floored(op, x, y), one), one)
          when :& then @f.band(a, b)
          when :| then @f.bor(a, b)
          when :^ then @f.bor(@f.bxor(a, b), one)
          when :>>
            # A shift of 63 or more, or of a negative count, is not a
            # shift right of a fixnum: it takes the call.
            k = @f.sshr(b, one)
            unless_unsigned_below(k, 63, slow)
            @f.bor(@f.sshr(a, k), one)
          when :<, :<=, :>, :>=, :==, :!=
            cond = { :< => "slt", :<= => "sle", :> => "sgt", :>= => "sge", :== => "eq", :!= => "ne" }.fetch(op)
            @f.csel(@f.icmp(cond, a, b), imm(@l.const("QTRUE")), imm(@l.const("QFALSE")))
          end
        end

        # A negative count reads as a huge unsigned one, so one branch
        # holds both ends of the range.
        def unless_unsigned_below(value, n, escape)
          ok = @f.label
          @f.brif(@f.icmp("uge", value, imm(n)), escape, ok)
          switch(ok)
        end

        # `x / y` or `x % y` rounded toward minus infinity, for `y` not
        # 0: when neither is negative the machine's truncation is that
        # already, else the kernel's floor.
        def floored(op, x, y)
          same = @f.label
          call = @f.label
          merge, (q,) = @f.block(["i64"])
          @f.brif(@f.icmp("sge", @f.bor(x, y), imm(0)), same, call)
          switch(same)
          @f.jump(merge, [op == :/ ? @f.sdiv(x, y) : @f.srem(x, y)])
          switch(call)
          @f.jump(merge, [kernel(op == :/ ? "zr_floor_div" : "zr_floor_mod", x, y)])
          switch(merge)
          q
        end

        def unless_equal(value, n, escape)
          ok = @f.label
          @f.brif(@f.icmp("eq", value, imm(n)), escape, ok)
          switch(ok)
        end

        def overflow_or((value, flag), slow)
          ok = @f.label
          @f.brif(flag, slow, ok)
          switch(ok)
          value
        end

        def gate_clear(name) = gates_clear(name)

        # Whether every one of the gates named is clear: one test of the
        # word, out of its register.
        def gates_clear(*names)
          @f.icmp("eq", @f.band(@f.gates, imm(names.sum { |name| @l.const(name) })), imm(0))
        end

        # `!v` inline for nil, true and false while none of their
        # classes redefines `!` (GATE_NOT); any other receiver sends
        # `!` through a cell of its own, as a call would. The three are
        # the only Values under 28 with their low two bits clear.
        def negate(node)
          staged([node.value]) do |slots, base|
            v = @f.fetch("i64", @rec, value_offset(base))
            fast = @f.label
            slow = @f.label
            merge, (result,) = @f.block(["i64"])
            boolean = @f.icmp("eq", @f.bor(v, imm(28)), imm(28))
            @f.brif(@f.band(boolean, gate_clear("GATE_NOT")), fast, slow)
            switch(fast)
            @f.jump(merge, [@f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))])
            switch(slow)
            send = @l.noted(Hir::Send.new(node.value, :!, [], node.line, false, false, nil, nil, false), node)
            @f.jump(merge, [dispatch(send, v, @f.iadd(slots, imm(8)), imm(0))])
            switch(merge)
            result
          end
        end
      end
    end
  end
end
