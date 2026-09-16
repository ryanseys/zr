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

        OPT_ENTRIES = { :[] => "zr_opt_aref", :[]= => "zr_opt_aset", :<< => "zr_opt_ltlt" }.freeze

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

        private

        # The receiver and arguments wait in record slots (a splat gathers
        # them into one Array there), keywords last as a Hash the task
        # flags, then the send.
        def call(node)
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

        # `recv&.name(args)`: nil when the receiver is, with the arguments
        # left unevaluated; else the send.
        def safe_call(node)
          # `self&.x` is `self.x`: self is never nil, and the receiver
          # stays a literal self for the visibility rule.
          return call(node.dup.tap { |n| n.safe = false }) if node.recv.is_a?(Hir::SelfRef)

          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = Hir::Send.new(Hir::Slot.new(slot, node.line), node.name, node.args, node.line, false, node.opt, node.block, node.kwargs, false, node.write, node.using)
          is_nil = @f.label
          go = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", @f.fetch("i64", @rec, value_offset(slot)), @qnil), is_nil, go)
          switch(is_nil)
          @f.jump(merge, [@qnil])
          switch(go)
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
          if node.block
            call_with_block(node, recv, argv, argc)
          elsif node.args.size == 1 && node.kwargs.nil? && OPS.key?(node.name) && !node.vcall && node.using.nil? && !traced?
            operator(node, recv, argv)
          else
            dispatch(node, recv, argv, argc)
          end
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
            ids = node.kwargs.pairs.each_slice(2).map { |key, _| sym_id(key.value) }
            @f.store(@f.symbol_value(@f.symbol(@l.keyword_table([ids.size, *ids]))), @task_addr, off(@task, "kw"))
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
        # the task so the lookup sees them.
        def activate(node)
          return if node.using.nil?

          if node.using == :owner
            kernel("zr_activate_owner", @rec)
          else
            kernel("zr_activate", imm(node.using))
          end
        end

        # The mode `zr_dispatch` takes: 0 for an implicit or `self`
        # receiver, 1 for a bare identifier, 2 for an explicit receiver,
        # which visibility applies to.
        def send_mode(node)
          mode = node.vcall ? 1 : (explicit?(node) ? 2 : 0)
          @l.internal? && !PROTOCOL.include?(node.name) ? mode | SEND_CORE : mode
        end

        def dispatch(node, recv, argv, argc)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          if node.opt && node.using.nil? && !traced?
            checked(kernel(OPT_ENTRIES.fetch(node.name), recv, imm(sym_id(node.name)), argc, argv, imm(send_mode(node))))
          elsif node.name == :new
            checked(kernel("zr_new_cached", cache("ic", "CallCache", 2), recv, argc, argv, imm(send_mode(node))))
          else
            checked(cached_send(node, recv, argc, argv, @qnil))
          end
        end

        # A send through the site's own cell (rt/kernel/cache.rb), which
        # keeps the method the receiver's class answered there last. The
        # site tests the cell itself: a fixnum's class is Integer, a
        # heap object's is in its header, and when that class is the
        # cell's and the cell's stamp is the site stamp, the cell's
        # function is called with the method signature. Anything else --
        # another special constant, a stale cell, the cells off -- is the
        # kernel's send, which fills the cell. A site under `using` asks
        # the kernel every time: a refinement decides, never the cell.
        def cached_send(node, recv, argc, argv, blk)
          cc = cache("ic", "CallCache")
          slow = -> { kernel("zr_send_cached", cc, recv, imm(sym_id(node.name)), argc, argv, blk, imm(send_mode(node))) }
          return slow.call if node.using

          cell = @l.layout("CallCache")
          fixnum = @f.label
          other = @f.label
          heap = @f.label
          have, (klass,) = @f.block(["i64"])
          direct = @f.label
          miss = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("ne", @f.band(recv, imm(1)), imm(0)), fixnum, other)
          switch(fixnum)
          @f.jump(have, [global("G_INTEGER")])
          switch(other)
          pointer = @f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil))
          @f.brif(pointer, heap, miss)
          switch(heap)
          @f.jump(have, [@f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))])
          switch(have)
          same = @f.band(@f.icmp("eq", klass, @f.fetch("i64", cc, off(cell, "klass"))),
                         @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("site_stamp"))))
          @f.brif(same, direct, miss)
          switch(direct)
          fn = @f.fetch("i64", cc, off(cell, "fn"))
          args = [recv, argc, argv, @f.fetch("i64", cc, off(cell, "entry")), blk, @f.fetch("i64", cc, off(cell, "found"))]
          @f.jump(merge, [@f.call_indirect_val(@f.sig(ABI.fetch(:def), "i64"), fn, args)])
          switch(miss)
          @f.jump(merge, [slow.call])
          switch(merge)
          result
        end

        # The send with a block: a descriptor for a block literal, with
        # the site's own `break` caught on the way out, or the `&value`.
        def call_with_block(node, recv, argv, argc)
          if node.block.is_a?(Hir::BlockPass)
            proc = checked(kernel("zr_block_pass", expr(node.block.value)))
            at_node(node)
            argc = keyword_argc(node, argc, argv)
            activate(node)
            return checked(cached_send(node, recv, argc, argv, proc))
          end

          site, block = make_block(node.block)
          at_node(node)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          catching_break(site) { cached_send(node, recv, argc, argv, block) }
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
          @f.store(imm(%w[T_PROC FL_ALLOCATED FL_MARK FL_STACK].sum { |c| @l.const(c) }), desc, off(basic, "flags"))
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
          call = -> { kernel("zr_super", @rec, argc, argv, blk) }
          site ? catching_break(site, &call) : checked(call.call)
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
          merge, (result,) = @f.block(["i64"])
          @f.brif(ok, fast, slow)
          switch(fast)
          value = fast_path(node.name, recv, arg, slow)
          @f.jump(merge, [value])
          switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv, imm(1))])
          switch(merge)
          result
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
            q = kernel(op == :/ ? "zr_floor_div" : "zr_floor_mod", x, y)
            @f.bor(@f.ishl(q, one), one)
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

        def gate_clear(name)
          gates = @f.fetch("i64", static("gates"))
          @f.icmp("eq", @f.band(gates, imm(@l.const(name))), imm(0))
        end

        # `!v` inline while BasicObject#! is the runtime's own.
        def negate(node)
          staged([node.value]) do |slots, base|
            v = @f.fetch("i64", @rec, value_offset(base))
            fast = @f.label
            slow = @f.label
            merge, (result,) = @f.block(["i64"])
            @f.brif(gate_clear("GATE_NOT"), fast, slow)
            switch(fast)
            @f.jump(merge, [@f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))])
            switch(slow)
            at_node(node)
            @f.jump(merge, [checked(kernel("zr_send", v, imm(sym_id(:!)), imm(0), @f.iadd(slots, imm(8))))])
            switch(merge)
            result
          end
        end
      end
    end
  end
end
