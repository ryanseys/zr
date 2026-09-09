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
          :< => "GATE_LT", :<= => "GATE_LE", :> => "GATE_GT", :>= => "GATE_GE", :== => "GATE_EQ", :!= => "GATE_NE"
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
              send_staged(node, @f.fetch("i64", slots), array_ptr(ary), array_len(ary), base + 2)
            end
          else
            staged([recv_node, *args], node.block ? 1 : 0) do |slots, base|
              send_staged(node, @f.fetch("i64", slots), @f.iadd(slots, imm(8)), imm(args.size), base + 1 + args.size)
            end
          end
        end

        # `recv&.name(args)`: nil when the receiver is, with the arguments
        # left unevaluated; else the send.
        def safe_call(node)
          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          plain = Hir::Send.new(Hir::Slot.new(slot, node.line), node.name, node.args, node.line, false, node.opt, node.block, node.kwargs, false)
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
          elsif node.args.size == 1 && node.kwargs.nil? && OPS.key?(node.name) && !node.vcall
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

        # A bare identifier, an implicit or `self` receiver, or an explicit
        # one, which visibility applies to.
        def dispatch(node, recv, argv, argc)
          entry = if node.vcall then "zr_vcall"
                  elsif node.opt then OPT_ENTRIES.fetch(node.name)
                  elsif explicit?(node) then "zr_call"
                  else "zr_send"
                  end
          at_line(node.line)
          kernel("zr_kw_pass") if node.kwargs
          checked(kernel(entry, recv, imm(sym_id(node.name)), argc, argv))
        end

        # The send with a block: a Proc for a block literal, with the
        # site's own `break` caught on the way out, or the `&value`.
        def call_with_block(node, recv, argv, argc, slot)
          if node.block.is_a?(Hir::BlockPass)
            proc = checked(kernel("zr_block_pass", expr(node.block.value)))
            at_line(node.line)
            kernel("zr_kw_pass") if node.kwargs
            return checked(kernel(explicit?(node) ? "zr_call_blk" : "zr_send_blk", recv, imm(sym_id(node.name)), argc, argv, proc))
          end

          site, proc = make_proc(node.block, slot)
          at_line(node.line)
          kernel("zr_kw_pass") if node.kwargs
          catching_break(site) { kernel(explicit?(node) ? "zr_call_blk" : "zr_send_blk", recv, imm(sym_id(node.name)), argc, argv, proc) }
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
        # runtime finds the next method past this frame's owner.
        def super_call(node)
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
          kernel("zr_kw_pass") if node.kwargs
          call = -> { kernel("zr_super", @rec, argc, argv, blk) }
          site ? catching_break(site, &call) : checked(call.call)
        end

        # The bare `super`: the enclosing method's parameters, as they
        # stand now, become the arguments.
        def zsuper(node)
          fn = self
          depth = 0
          until fn.kind == :def
            @l.refuse(node, "super outside a method is not lowered yet") if fn.outer.nil?
            fn = fn.outer
            depth += 1
          end
          p = fn.def_node.params
          local = ->(name) { Hir::Local.new(name, depth, node.line) }
          positional = (p.required + p.optional.map(&:first)).map(&local) + [p.rest && p.rest != :implicit ? Hir::Splat.new(local.call(p.rest), node.line) : nil].compact + p.post.map(&local)
          pairs = p.keywords.flat_map { |name, _| [Hir::Literal.new(name, node.line), local.call(name)] }
          pairs += [Hir::HashSplat.new(local.call(p.kwrest), node.line), nil] if p.kwrest
          kwargs = pairs.empty? ? nil : Hir::HashLit.new(pairs, node.line)
          block = node.block || (p.block && Hir::BlockPass.new(local.call(p.block), node.line))
          super_call(Hir::Super.new(positional, kwargs, block, node.line))
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
          when :<, :<=, :>, :>=, :==, :!=
            cond = { :< => "slt", :<= => "sle", :> => "sgt", :>= => "sge", :== => "eq", :!= => "ne" }.fetch(op)
            @f.csel(@f.icmp(cond, a, b), imm(@l.const("QTRUE")), imm(@l.const("QFALSE")))
          end
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
          gates = @f.fetch("i64", @f.symbol_value(@f.symbol("zr_static_gates")))
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
