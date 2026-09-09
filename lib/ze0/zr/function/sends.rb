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

        def call(node)
          recv_node = node.recv || Hir::SelfRef.new(node.line)
          staged([recv_node, *node.args], node.block ? 1 : 0) do |slots, base|
            recv = @f.fetch("i64", @rec, value_offset(base))
            argv = @f.iadd(slots, imm(8))
            if node.block
              call_with_block(node, recv, argv, base + 1 + node.args.size)
            elsif node.args.size == 1 && OPS.key?(node.name) && !node.vcall
              operator(node, recv, argv)
            else
              dispatch(node, recv, argv)
            end
          end
        end

        def dispatch(node, recv, argv)
          entry = if node.vcall then "zr_vcall"
                  elsif node.opt then OPT_ENTRIES.fetch(node.name)
                  else "zr_send"
                  end
          at_line(node.line)
          checked(kernel(entry, recv, imm(sym_id(node.name)), imm(node.args.size), argv))
        end

        # A Proc for the block in the record slot `slot`, the send with it,
        # and the site's own `break` caught on the way out.
        def call_with_block(node, recv, argv, slot)
          fn = @l.block(node.block, self)
          site = (@sites += 1)
          ret_home = @kind == :block ? proc_field("ret_home") : @rec
          proc = kernel("zr_proc_new", @f.func_addr(@f.callee(fn, ABI.fetch(:block), "i64")), @env, @self, @cref, @blk, @rec,
                        imm((site << 32) | node.block.params.size), ret_home)
          @f.store(proc, @rec, value_offset(slot))
          at_line(node.line)
          r = kernel("zr_send_blk", recv, imm(sym_id(node.name)), imm(node.args.size), argv, proc)
          fine = @f.label
          signal = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", r, qundef), signal, fine)
          @f.switch(fine)
          @f.jump(merge, [r])
          @f.switch(signal)
          caught = kernel("zr_catch_break", @rec, imm(site))
          @landing ||= @f.label
          ours = @f.label
          @f.brif(@f.icmp("eq", caught, qundef), @landing, ours)
          @f.switch(ours)
          @f.jump(merge, [caught])
          @f.switch(merge)
          result
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
          @f.switch(fast)
          value = fast_path(node.name, recv, arg, slow)
          @f.jump(merge, [value])
          @f.switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv)])
          @f.switch(merge)
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
          @f.switch(ok)
        end

        def overflow_or((value, flag), slow)
          ok = @f.label
          @f.brif(flag, slow, ok)
          @f.switch(ok)
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
            @f.switch(fast)
            @f.jump(merge, [@f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))])
            @f.switch(slow)
            at_line(node.line)
            @f.jump(merge, [checked(kernel("zr_send", v, imm(sym_id(:!)), imm(0), @f.iadd(slots, imm(8))))])
            @f.switch(merge)
            result
          end
        end
      end
    end
  end
end
