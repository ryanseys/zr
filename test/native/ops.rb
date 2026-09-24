# frozen_string_literal: true

require_relative "../../lib/zr/ir"

module Zr
  module Native
    # Every opcode `Backend::Aarch64::Codegen` lowers, each in the smallest function that
    # can hold it: the operands arrive as parameters and the result is
    # returned, so what a snapshot shows is the opcode, its frame, and
    # nothing else.
    #
    # A width appears twice where the lowering differs by it, because an
    # operation below `i64` runs in a w-register.
    module Ops
      module_function

      # `{ "iadd.i64" => IR::Function, ... }`, in the order they are named.
      def all
        ops = {}
        literals(ops)
        memory(ops)
        integers(ops)
        floats(ops)
        control(ops)
        ops
      end

      # One function around whatever `body` emits. A body that ends the
      # block itself needs no return added.
      def build(name, params, ret)
        f = IR::Function.new(name, params, ret)
        value = yield(f, *f.args)
        f.ret(value) unless f.terminated?
        f
      end

      def literals(ops)
        # A small constant is one `movz`; a wide one is a chain of `movk`;
        # a negative one starts from `movn`.
        ops["iconst.small"] = build("iconst_small", [], "i64") { |f| f.iconst("i64", 7) }
        ops["iconst.wide"] = build("iconst_wide", [], "i64") { |f| f.iconst("i64", 0x1234_5678_9ABC_DEF0) }
        ops["iconst.negative"] = build("iconst_negative", [], "i64") { |f| f.iconst("i64", -2) }
        ops["iconst.i32"] = build("iconst_i32", [], "i32") { |f| f.iconst("i32", 1) }
      end

      def memory(ops)
        %w[i8 i32 i64 f64].each do |t|
          ops["load.#{t}"] = build("load_#{t}", %w[i64], t) { |f, p| f.fetch(t, p) }
        end
        # An offset too large for the scaled immediate builds the address.
        ops["load.far"] = build("load_far", %w[i64], "i64") { |f, p| f.fetch("i64", p, 0x1_0000) }
        %w[i8 i32 i64].each do |t|
          ops["store.#{t}"] = build("store_#{t}", ["i64", t], nil) { |f, p, v| f.store(v, p) }
        end
        ops["stack_addr"] = build("stack_addr", [], "i64") { |f| f.stack_addr(f.slot(16)) }
        # Two stores of words eight bytes apart: one `stp`, as the nil
        # fills of a record are.
        ops["store.pair"] = build("store_pair", %w[i64 i64], nil) do |f, p, v|
          f.store(v, p, 8)
          f.store(f.iconst("i64", 8), p, 16)
        end
        # The same past the pair's reach, on a slot so far up a frame that
        # the second store's offset needs sp paged through x17.
        ops["store.pair_far"] = build("store_pair_far", %w[i64], nil) do |f, v|
          p = f.stack_addr(f.slot(40_000))
          f.store(v, p, 32_744)
          f.store(f.iconst("i64", 8), p, 32_752)
        end
        # A load whose address is a constant past a base: the constant
        # could fold into the load's own offset.
        ops["load.iadd_base"] = build("load_iadd_base", %w[i64], "i64") do |f, p|
          f.fetch("i64", f.iadd(p, f.iconst("i64", 24)))
        end
        ops["load.iadd_stack"] = build("load_iadd_stack", [], "i64") do |f|
          f.fetch("i64", f.iadd(f.stack_addr(f.slot(32)), f.iconst("i64", 16)))
        end
        # A slot's address and two constants, read as a value: one `add`
        # from sp could make it, with the inner sum read through alone.
        ops["iadd.stack_chain"] = build("iadd_stack_chain", %w[i64], "i64") do |f, v|
          inner = f.iadd(f.stack_addr(f.slot(32)), f.iconst("i64", 16))
          f.store(v, inner)
          f.iadd(inner, f.iconst("i64", 8))
        end
        # One value stored twice, eight bytes apart: one register would do.
        ops["store.pair_same"] = build("store_pair_same", %w[i64], nil) do |f, p|
          nil_word = f.iconst("i64", 8)
          f.store(nil_word, p, 8)
          f.store(nil_word, p, 16)
        end
        ops["symbol_value.local"] = build("symbol_local", [], "i64") { |f| f.symbol_value(f.symbol("here")) }
        ops["symbol_value.import"] = build("symbol_import", [], "i64") do |f|
          f.symbol_value(f.symbol("elsewhere", colocated: false))
        end
        ops["func_addr"] = build("func_addr", [], "i64") { |f| f.func_addr(f.callee("other", %w[i64], "i64")) }
      end

      # A constant operand an instruction has a form for takes no
      # register: twelve bits for `add`, `sub` and `cmp`, a shift inside
      # the register, and a bitmask for `and`, `orr` and `eor`. The
      # constant itself is still made in the entry block until something
      # removes a constant nothing reads.
      def immediates(ops)
        ops["imm.add"] = build("imm_add", %w[i64], "i64") { |f, a| f.iadd(a, f.iconst("i64", 52)) }
        ops["imm.add_negative"] = build("imm_add_negative", %w[i64], "i64") { |f, a| f.iadd(a, f.iconst("i64", -8)) }
        ops["imm.add_wide"] = build("imm_add_wide", %w[i64], "i64") { |f, a| f.iadd(a, f.iconst("i64", 5000)) }
        ops["imm.sub.i32"] = build("imm_sub_i32", %w[i32], "i32") { |f, a| f.isub(a, f.iconst("i32", 1)) }
        ops["imm.and"] = build("imm_and", %w[i64], "i64") { |f, a| f.band(a, f.iconst("i64", 7)) }
        ops["imm.and_not_a_mask"] = build("imm_and_not_a_mask", %w[i64], "i64") { |f, a| f.band(a, f.iconst("i64", 5)) }
        ops["imm.orr_left"] = build("imm_orr_left", %w[i64], "i64") { |f, a| f.bor(f.iconst("i64", -4), a) }
        ops["imm.ushr"] = build("imm_ushr", %w[i64], "i64") { |f, a| f.ushr(a, f.iconst("i64", 3)) }
        ops["imm.ishl.i32"] = build("imm_ishl_i32", %w[i32], "i32") { |f, a| f.ishl(a, f.iconst("i32", 8)) }
        ops["imm.sshr"] = build("imm_sshr", %w[i64], "i64") { |f, a| f.sshr(a, f.iconst("i64", 63)) }
        ops["imm.icmp"] = build("imm_icmp", %w[i64], "i8") { |f, a| f.icmp("eq", a, f.iconst("i64", 52)) }
        # A constant on the left turns the condition round.
        ops["imm.icmp_left"] = build("imm_icmp_left", %w[i64], "i8") { |f, a| f.icmp("slt", f.iconst("i64", 10), a) }
      end

      def integers(ops)
        IR::Inst::BINOPS.each do |op|
          %w[i64 i32].each do |t|
            ops["#{op}.#{t}"] = build("#{op}_#{t}", [t, t], t) { |f, a, b| f.binop(op, a, b) }
          end
        end
        IR::Inst::BITOPS.each do |op|
          %w[i64 i32].each do |t|
            ops["#{op}.#{t}"] = build("#{op}_#{t}", [t], t) { |f, a| f.bitop(op, a) }
          end
        end
        IR::Inst::CONDS.each do |cond|
          ops["icmp.#{cond}"] = build("icmp_#{cond}", %w[i64 i64], "i8") { |f, a, b| f.icmp(cond, a, b) }
        end
        ops["icmp.i32"] = build("icmp_i32", %w[i32 i32], "i8") { |f, a, b| f.icmp("slt", a, b) }
        immediates(ops)
        %w[i64 i32].each do |t|
          ops["select.#{t}"] = build("select_#{t}", ["i8", t, t], t) { |f, c, a, b| f.csel(c, a, b) }
        end
        # A select whose condition is one compare with no other use: the
        # compare's flags could feed the select directly.
        ops["select.of_icmp"] = build("select_of_icmp", %w[i64 i64], "i64") do |f, a, b|
          f.csel(f.icmp("slt", a, b), a, b)
        end
        ops["ireduce"] = build("ireduce", %w[i64], "i32") { |f, a| f.ireduce("i32", a) }
        ops["uextend"] = build("uextend", %w[i32], "i64") { |f, a| f.uextend("i64", a) }
        ops["sextend.i8"] = build("sextend_i8", %w[i8], "i64") { |f, a| f.sextend("i64", a) }
        ops["sextend.i32"] = build("sextend_i32", %w[i32], "i64") { |f, a| f.sextend("i64", a) }
        ops["bitcast"] = build("bitcast", %w[f64], "i64") { |f, a| f.bitcast("i64", a) }
        %i[sadd_overflow ssub_overflow].each do |op|
          %w[i64 i32].each do |t|
            ops["#{op}.#{t}"] = build("#{op}_#{t}", [t, t], t) { |f, a, b| f.public_send(op, a, b).first }
          end
        end
        ops["smul_overflow"] = build("smul_overflow", %w[i64 i64], "i64") { |f, a, b| f.smul_overflow(a, b).first }
      end

      def floats(ops)
        IR::Inst::FBINOPS.each do |op|
          ops[op.to_s] = build(op.to_s, %w[f64 f64], "f64") { |f, a, b| f.fbinop(op, a, b) }
        end
        IR::Inst::FUNOPS.each do |op|
          ops[op.to_s] = build(op.to_s, %w[f64], "f64") { |f, a| f.funop(op, a) }
        end
        IR::Inst::FCONDS.each do |cond|
          ops["fcmp.#{cond}"] = build("fcmp_#{cond}", %w[f64 f64], "i8") { |f, a, b| f.fcmp(cond, a, b) }
        end
        ops["fcvt_from_sint"] = build("fcvt_from_sint", %w[i64], "f64") { |f, a| f.fcvt_from_sint(a) }
        ops["fcvt_from_sint.i32"] = build("fcvt_from_sint_i32", %w[i32], "f64") { |f, a| f.fcvt_from_sint(a) }
        # A chain of float operations: each result could stay in a d
        # register for the next.
        ops["fbinop.chain"] = build("fbinop_chain", %w[f64 f64], "f64") do |f, a, b|
          f.fbinop(:fmul, f.fbinop(:fadd, a, b), f.fbinop(:fsub, a, b))
        end
        ops["fcvt_to_sint_sat"] = build("fcvt_to_sint_sat", %w[f64], "i64") { |f, a| f.fcvt_to_sint_sat(a) }
      end

      def control(ops)
        ops["call"] = build("call", %w[i64], "i64") do |f, a|
          f.call_val(f.callee("other", %w[i64], "i64"), [a])
        end
        ops["call.import"] = build("call_import", %w[i64], "i64") do |f, a|
          f.call_val(f.callee("elsewhere", %w[i64], "i64", colocated: false), [a])
        end
        ops["call.void"] = build("call_void", [], nil) { |f| f.call(f.callee("other", [], nil)) }
        ops["call.i32"] = build("call_i32", [], "i32") { |f| f.call_val(f.callee("other", [], "i32")) }
        ops["call_indirect"] = build("call_indirect", %w[i64 i64], "i64") do |f, ptr, a|
          f.call_indirect_val(f.sig(%w[i64], "i64"), ptr, [a])
        end
        # A jump carrying arguments is a parallel copy at the edge.
        ops["jump"] = build("jump", %w[i64 i64], "i64") do |f, a, b|
          block, (x, y) = f.block(%w[i64 i64])
          f.jump(block, [b, a])
          f.switch(block)
          f.iadd(x, y)
        end
        # An argument already where its parameter lives needs no
        # instruction: a loop that carries a variable along its back edge
        # unchanged is the shape this is here for.
        ops["jump.same"] = build("jump_same", %w[i64], "i64") do |f, a|
          block, (x, ) = f.block(%w[i64])
          f.jump(block, [a])
          f.switch(block)
          f.jump(block, [x])
        end
        # Two parameters that trade places are a cycle, and a cycle is
        # the one case that needs a register to hold a value out of the
        # way while the rest of the copies go round.
        ops["jump.cycle"] = build("jump_cycle", %w[i64 i64], "i64") do |f, a, b|
          block, (x, y) = f.block(%w[i64 i64])
          f.jump(block, [a, b])
          f.switch(block)
          f.jump(block, [y, x])
        end
        # Nothing limits how many arguments an edge carries: the
        # resolver needs one register for a copy and one for a cycle,
        # whatever the width. Two parameters here read the same source.
        ops["jump.wide"] = build("jump_wide", %w[i64 i64 i64 i64], "i64") do |f, a, b, c, d|
          block, ps = f.block(%w[i64] * 8)
          f.jump(block, [a, b, c, d, d, c, b, a])
          f.switch(block)
          f.jump(block, ps.rotate(1))
        end
        # A compare and its branch with a constant between them, as the
        # stack check has: the compare could still fuse with the branch.
        ops["brif.across_constant"] = build("brif_across_constant", %w[i64 i64], "i64") do |f, a, b|
          c = f.icmp("slt", a, b)
          k = f.iconst("i64", 0x1234_5678)
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(k)
          f.switch(no)
          f.ret(a)
        end
        # A compare and its branch with a load between them: the load
        # leaves the flags alone, so the two still fuse.
        ops["brif.across_load"] = build("brif_across_load", %w[i64 i64], "i64") do |f, a, b|
          c = f.icmp("slt", a, b)
          x = f.fetch("i64", a)
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(x)
          f.switch(no)
          f.ret(b)
        end
        # A branch on one bit of a word: a tbz or tbnz would do.
        ops["brif.tbz"] = build("brif_tbz", %w[i64], "i64") do |f, a|
          c = f.icmp("ne", f.band(a, f.iconst("i64", 8)), f.iconst("i64", 0))
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(f.iconst("i64", 1))
          f.switch(no)
          f.ret(f.iconst("i64", 0))
        end
        # A branch on any of some bits of a word: a `tst` would do.
        ops["brif.tst"] = build("brif_tst", %w[i64], "i64") do |f, a|
          c = f.icmp("eq", f.band(a, f.iconst("i64", 7)), f.iconst("i64", 0))
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(f.iconst("i64", 1))
          f.switch(no)
          f.ret(f.iconst("i64", 0))
        end
        # A branch on an overflow flag: `b.vs` reads it straight.
        ops["brif.overflow"] = build("brif_overflow", %w[i64 i64], "i64") do |f, a, b|
          sum, flag = f.sadd_overflow(a, b)
          yes = f.label
          no = f.label
          f.brif(flag, yes, no)
          f.switch(yes)
          f.ret(f.iconst("i64", 0))
          f.switch(no)
          f.ret(sum)
        end
        # Two returns: each could share one epilogue.
        ops["return.twice"] = build("return_twice", %w[i8 i64], "i64") do |f, c, a|
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(a)
          f.switch(no)
          f.ret(f.iadd(a, f.iconst("i64", 1)))
        end
        ops["brif"] = build("brif", %w[i8 i64], "i64") do |f, c, a|
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(a)
          f.switch(no)
          f.iconst("i64", 0)
        end
        # An `icmp` whose one use is the `brif` next to it: the compare
        # sets the flags and `b.cond` reads them, so no boolean is made.
        #
        # Nothing here makes a constant after the compare. A constant
        # goes to the entry block just before its terminator, which is
        # this `brif`, and that would put an instruction between the two
        # and leave them unfused.
        ops["brif.fused"] = build("brif_fused", %w[i64 i64], "i64") do |f, a, b|
          yes = f.label
          no = f.label
          f.brif(f.icmp("eq", a, b), yes, no)
          f.switch(yes)
          f.ret(a)
          f.switch(no)
          b
        end
        # The same, with the taken block falling through: the branch goes
        # the other way, on the condition that is left.
        ops["brif.fused_fallthrough"] = build("brif_fused_ft", %w[i64 i64], "i64") do |f, a, b|
          yes = f.label
          no = f.label
          f.brif(f.icmp("slt", a, b), yes, no)
          f.switch(no)
          f.ret(b)
          f.switch(yes)
          a
        end
        # A compare read twice cannot fuse: the boolean is still made.
        ops["brif.unfused"] = build("brif_unfused", %w[i64 i64], "i64") do |f, a, b|
          c = f.icmp("eq", a, b)
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(f.uextend("i64", c))
          f.switch(no)
          b
        end
        ops["return.void"] = build("return_void", [], nil) { nil }
        ops["return.f64"] = build("return_f64", %w[f64], "f64") { |_f, a| a }
      end
    end
  end
end
