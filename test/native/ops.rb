# frozen_string_literal: true

require_relative "../../lib/ze0/ir"

module Ze0
  module Native
    # Every opcode `IR::Arm64` lowers, each in the smallest function that
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
        ops["symbol_value.local"] = build("symbol_local", [], "i64") { |f| f.symbol_value(f.symbol("here")) }
        ops["symbol_value.import"] = build("symbol_import", [], "i64") do |f|
          f.symbol_value(f.symbol("elsewhere", colocated: false))
        end
        ops["func_addr"] = build("func_addr", [], "i64") { |f| f.func_addr(f.callee("other", %w[i64], "i64")) }
      end

      def integers(ops)
        IR::Inst::BINOPS.each do |op|
          %w[i64 i32].each do |t|
            ops["#{op}.#{t}"] = build("#{op}_#{t}", [t, t], t) { |f, a, b| f.binop(op, a, b) }
          end
        end
        IR::Inst::CONDS.each do |cond|
          ops["icmp.#{cond}"] = build("icmp_#{cond}", %w[i64 i64], "i8") { |f, a, b| f.icmp(cond, a, b) }
        end
        ops["icmp.i32"] = build("icmp_i32", %w[i32 i32], "i8") { |f, a, b| f.icmp("slt", a, b) }
        %w[i64 i32].each do |t|
          ops["select.#{t}"] = build("select_#{t}", ["i8", t, t], t) { |f, c, a, b| f.csel(c, a, b) }
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
        ops["brif"] = build("brif", %w[i8 i64], "i64") do |f, c, a|
          yes = f.label
          no = f.label
          f.brif(c, yes, no)
          f.switch(yes)
          f.ret(a)
          f.switch(no)
          f.iconst("i64", 0)
        end
        ops["return.void"] = build("return_void", [], nil) { nil }
        ops["return.f64"] = build("return_f64", %w[f64], "f64") { |_f, a| a }
      end
    end
  end
end
