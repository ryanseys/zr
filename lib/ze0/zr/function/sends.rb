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

        private

        # The receiver and arguments wait in record slots (a splat gathers
        # them into one Array there), keywords last as a Hash the task
        # flags, then the send.
        def call(node)
          return safe_call(node) if node.safe
          return primitive(node) if primitive?(node)

          recv_node = node.recv || Hir::SelfRef.new(node.line)
          args = node.args + [node.kwargs].compact
          if args.any?(Hir::Splat)
            staged([recv_node], 1 + (node.block ? 1 : 0)) do |slots, base|
              ary = gather(args, base + 1)
              # A write answers the value it wrote, which is the last thing
              # gathered, not whatever the writer returned.
              last = node.write ? kernel("zr_ary_at", ary, @f.isub(array_len(ary), imm(1))) : nil
              r = send_staged(node, @f.fetch("i64", slots), array_ptr(ary), array_len(ary), base + 2)
              node.write ? last : r
            end
          else
            staged([recv_node, *args], node.block ? 1 : 0) do |slots, base|
              r = send_staged(node, @f.fetch("i64", slots), @f.iadd(slots, imm(8)), imm(args.size), base + 1 + args.size)
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
        # itself, called directly with Values.
        def primitive?(node)
          @l.internal? && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive && node.recv.scope.nil?
        end

        def primitive(node)
          return @qnil if node.name == :attr!

          d = @l.kernel_def(node.name.to_s)
          @l.refuse(node, "Primitive.#{node.name} takes #{d.params.size} arguments, not #{node.args.size}") if d.params.size != node.args.size
          @l.refuse(node, "Primitive.#{node.name} takes a block or keywords") if node.block || node.kwargs
          d.params.each { |name, type| @l.refuse(node, "Primitive.#{node.name}'s #{name} is a #{type}, not a Value") unless type == "Value" }
          @l.refuse(node, "Primitive.#{node.name} answers a #{d.ret}, not a Value") unless d.ret == "Value"
          at_line(node.line)
          staged(node.args) do |slots, base|
            args = node.args.each_index.map { |i| @f.fetch("i64", @rec, value_offset(base + i)) }
            checked(kernel(node.name.to_s, *args))
          end
        end

        def explicit?(node)
          !(node.recv.nil? || node.recv.is_a?(Hir::SelfRef))
        end

        def send_staged(node, recv, argv, argc, block_slot)
          if node.block
            call_with_block(node, recv, argv, argc, block_slot)
          elsif node.args.size == 1 && node.kwargs.nil? && OPS.key?(node.name) && !node.vcall && node.using.nil?
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
        def keyword_argc(node, argc, argv)
          return kernel("zr_kw_argc", argc, argv) if node.kwargs
          return kernel("zr_kw_ruby2_out", argc, argv) if node.args.any?(Hir::Splat)

          argc
        end

        # `using mod` fills the row it names, so every send under it
        # reads what this module refines.
        def using_row(node)
          at_line(node.line)
          checked(kernel("zr_using_activate", imm(node.id), expr(node.value), imm(node.from)))
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
          return 1 if node.vcall

          explicit?(node) ? 2 : 0
        end

        def dispatch(node, recv, argv, argc)
          at_line(node.line)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          if node.opt && node.using.nil?
            checked(kernel(OPT_ENTRIES.fetch(node.name), recv, imm(sym_id(node.name)), argc, argv))
          elsif node.name == :new
            checked(kernel("zr_new_cached", cache("ic", "CallCache", 2), recv, argc, argv, imm(send_mode(node))))
          else
            checked(cached_send(node, recv, argc, argv, @qnil))
          end
        end

        # A send through the site's own cell (rt/kernel/cache.rb), which
        # keeps the method the receiver's class answered there last.
        def cached_send(node, recv, argc, argv, blk)
          kernel("zr_send_cached", cache("ic", "CallCache"), recv, imm(sym_id(node.name)), argc, argv, blk, imm(send_mode(node)))
        end

        # The send with a block: a Proc for a block literal, with the
        # site's own `break` caught on the way out, or the `&value`.
        def call_with_block(node, recv, argv, argc, slot)
          if node.block.is_a?(Hir::BlockPass)
            proc = checked(kernel("zr_block_pass", expr(node.block.value)))
            at_line(node.line)
            argc = keyword_argc(node, argc, argv)
            activate(node)
            return checked(cached_send(node, recv, argc, argv, proc))
          end

          site, proc = make_proc(node.block, slot)
          at_line(node.line)
          argc = keyword_argc(node, argc, argv)
          activate(node)
          catching_break(site) { cached_send(node, recv, argc, argv, proc) }
        end

        # A Proc for the block literal, kept in the record slot `slot`,
        # and its site number.
        def make_proc(block, slot)
          fn = @l.block(block, self)
          site = (@sites += 1)
          ret_home = @kind == :block ? proc_field("ret_home") : @rec
          proc = kernel("zr_proc_new", @f.symbol_value(@f.symbol("zr_meta_#{fn}")), @env, @self, @cref, @blk, @rec,
                        imm((site << 32) | (block.params.spread? ? 1 : 0)), ret_home)
          @f.store(proc, @rec, value_offset(slot))
          [site, proc]
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
            at_line(node.line)
            checked(kernel("zr_zsuper_in_block", @rec))
          end
          args = node.args + [node.kwargs].compact
          if args.any?(Hir::Splat)
            staged([], 1 + (node.block ? 1 : 0)) do |_, base|
              ary = gather(args, base)
              super_staged(node, array_ptr(ary), array_len(ary), base + 1)
            end
          else
            staged(args, node.block ? 1 : 0) { |slots, base| super_staged(node, slots, imm(args.size), base + args.size) }
          end
        end

        def super_staged(node, argv, argc, block_slot)
          site = nil
          blk = case node.block
                when nil then @blk
                when Hir::BlockPass then checked(kernel("zr_block_pass", expr(node.block.value)))
                else
                  site, proc = make_proc(node.block, block_slot)
                  proc
                end
          at_line(node.line)
          argc = keyword_argc(node, argc, argv)
          call = -> { kernel("zr_super", @rec, argc, argv, blk) }
          site ? catching_break(site, &call) : checked(call.call)
        end

        # A bare `super` the builder could not expand, one with no def
        # around it: the runtime raises for it.
        def zsuper(node)
          at_line(node.line)
          checked(kernel("zr_zsuper_outside", @rec))
        end

        # An Integer operator: the fixnum fast path inline when both sides
        # are fixnums (the receiver alone for equality) and the gate is
        # clear, else the call.
        def operator(node, recv, argv)
          arg = @f.fetch("i64", argv)
          both = %i[== !=].include?(node.name) ? recv : @f.band(recv, arg)
          fix = @f.icmp("eq", @f.band(both, imm(1)), imm(1))
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
            at_line(node.line)
            @f.jump(merge, [checked(kernel("zr_send", v, imm(sym_id(:!)), imm(0), @f.iadd(slots, imm(8))))])
            switch(merge)
            result
          end
        end
      end
    end
  end
end
