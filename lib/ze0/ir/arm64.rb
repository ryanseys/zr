# frozen_string_literal: true

require_relative "../machine/aarch64"
require_relative "function"
require_relative "../obj/model"

module Ze0
  module IR
    # The aarch64 backend: an `IR::Function` to an `Obj::Function` of Apple
    # arm64 machine code, with relocations for every symbol it names.
    #
    # Register allocation spills everything: every SSA value and block
    # parameter owns an 8-byte slot in the frame, an instruction loads its
    # operands into x9..x15, computes, and stores its result. No callee-saved
    # register is touched, x18 is never used, and sp stays 16-byte aligned.
    # The frame is `[sp + 0 .. slots) [values)`, addressed from sp with
    # unsigned scaled offsets, and x29 keeps the frame chain.
    #
    # Encodings come from `Machine::Aarch64`; relocations are recorded
    # here at the instruction's offset.
    class Arm64
      include Machine::Aarch64::Registers

      SCRATCH = [X9, X10, X11, X12, X13, X14, X15].freeze
      SCRATCH_W = [W9, W10, W11, W12, W13, W14, W15].freeze
      # CLIF condition codes to arm64's.
      CONDS = {
        "eq" => :eq, "ne" => :ne, "slt" => :lt, "sle" => :le, "sgt" => :gt, "sge" => :ge,
        "ult" => :lo, "ule" => :ls, "ugt" => :hi, "uge" => :hs
      }.freeze
      # Float comparisons after fcmp: NaN on either side sets C and V and
      # clears N and Z, which every condition but `ne` reads as false.
      FCONDS = { "eq" => :eq, "ne" => :ne, "lt" => :mi, "le" => :ls, "gt" => :gt, "ge" => :ge }.freeze

      # The floating-point instructions, as words: `FMOV Dd, Xn`,
      # `FMOV Xd, Dn`, the arithmetic and the conversions, with d16..d19
      # as scratch.
      module FP
        Word = Struct.new(:word) do
          def encode(_position) = word
        end

        module_function

        def to_d(d, x) = Word.new(0x9E670000 | (x << 5) | d)
        def to_x(x, d) = Word.new(0x9E660000 | (d << 5) | x)
        def binop(op, d, n, m)
          base = { fadd: 0x1E602800, fsub: 0x1E603800, fmul: 0x1E600800, fdiv: 0x1E601800 }.fetch(op)
          Word.new(base | (m << 16) | (n << 5) | d)
        end

        def unop(op, d, n)
          base = { fneg: 0x1E614000, fabs: 0x1E60C000, sqrt: 0x1E61C000, floor: 0x1E654000, ceil: 0x1E64C000, trunc: 0x1E65C000, nearest: 0x1E644000 }.fetch(op)
          Word.new(base | (n << 5) | d)
        end

        def cmp(n, m) = Word.new(0x1E602000 | (m << 16) | (n << 5))
        def scvtf(d, x) = Word.new(0x9E620000 | (x << 5) | d)
        def fcvtzs(x, d) = Word.new(0x9E780000 | (d << 5) | x)
      end

      class Refused < StandardError; end

      def initialize(function, defined: [], assembler: Machine::Aarch64::Assembler)
        @f = function
        @defined = defined
        @asm = assembler.new
        @relocs = []
        @type = {}
        @home = {}
        @labels = {}
      end

      def compile
        assign_types
        assign_homes
        @f.blocks.each { |b| @labels[b.name] = @asm.make_label(b.name) }
        prologue
        @f.blocks.each_with_index do |b, n|
          @asm.put_label(@labels[b.name])
          @next = @f.blocks[n + 1]&.name
          b.insts.each { |i| emit(i) }
        end
        Obj::Function.new(@f.name, @asm.to_binary, relocs: @relocs, linkage: :export)
      end

      private

      # --- layout -------------------------------------------------------

      def assign_types
        @f.blocks.each { |b| b.params.each { |v, t| @type[v] = t } }
        @f.blocks.each do |b|
          b.insts.each do |i|
            next if i.results.empty?

            t = case i.op
                when :iconst, :load, :ireduce, :uextend, :sextend then i.type
                when :call then sig_of(i.callee).ret
                when :call_indirect then sig_named(i.callee).ret
                when :icmp, :fcmp then "i8"
                when :stack_addr, :symbol_value, :func_addr then "i64"
                when *Inst::FBINOPS, *Inst::FUNOPS then "f64"
                when :select then type_of(i.args[1])
                when :sadd_overflow, :ssub_overflow, :smul_overflow then type_of(i.args[0])
                else i.type || type_of(i.args[0])
                end
            @type[i.results[0]] = t
            @type[i.results[1]] = "i8" if i.results.size > 1
          end
        end
      end

      def type_of(v)
        @type.fetch(v) { raise Refused, "#{@f.name}: no type for #{v}" }
      end

      def assign_homes
        off = 0
        @slot_at = @f.slots.map do |s|
          off = align(off, [s.align, 8].max)
          at = off
          off += s.bytes
          at
        end
        off = align(off, 8)
        @f.blocks.each do |b|
          b.params.each do |v, _|
            @home[v] = off
            off += 8
          end
          b.insts.each do |i|
            i.results.each do |v|
              @home[v] = off
              off += 8
            end
          end
        end
        @frame = align(off, 16)
      end

      def align(n, a)
        (n + a - 1) & ~(a - 1)
      end

      def sig_of(fn)
        callee = callee_of(fn) or raise Refused, "#{@f.name}: no callee #{fn}"
        sig_named(callee.sig)
      end

      def sig_named(sig)
        @sig_named ||= first_by(@f.sigs, &:sig)
        @sig_named[sig] or raise Refused, "#{@f.name}: no signature #{sig}"
      end

      def callee_of(fn)
        @callee_of ||= first_by(@f.callees, &:fn)
        @callee_of[fn]
      end

      def global_of(gv)
        @global_of ||= first_by(@f.globals, &:gv)
        @global_of[gv]
      end

      def block_named(name)
        @block_named ||= first_by(@f.blocks, &:name)
        @block_named.fetch(name)
      end

      # Each row by its key, the first row winning as `find` would.
      def first_by(rows)
        rows.each_with_object({}) { |row, index| index[yield(row)] ||= row }
      end

      # --- frame access -------------------------------------------------

      # `[base, offset]` for `off` from sp, the offset small enough for a
      # scaled immediate of `width` bytes; x15 holds a page base when not.
      def address(off, width)
        return [SP, off] if off % width == 0 && off / width <= 4095

        hi = off & ~0xFFF
        @asm.add X15, SP, hi >> 12, lsl: 12
        [X15, off & 0xFFF]
      end

      # An f64 value lives in its slot as bits and moves through the
      # integer registers.
      def load_value(v, reg)
        off = @home.fetch(v)
        case type_of(v)
        when "i64", "f64" then @asm.ldr reg, address(off, 8)
        when "i32" then @asm.ldr w(reg), address(off, 4)
        when "i8" then @asm.ldrb w(reg), address(off, 1)
        else raise Refused, "#{@f.name}: a #{type_of(v)} value"
        end
      end

      # Store the whole 64-bit register: a 32-bit result has zero above.
      def store_value(v, reg)
        @asm.str reg, address(@home.fetch(v), 8)
      end

      def store_param(v, reg)
        off = @home.fetch(v)
        case type_of(v)
        when "i64", "f64" then @asm.str reg, address(off, 8)
        when "i32" then @asm.str w(reg), address(off, 4)
        when "i8" then @asm.strb w(reg), address(off, 1)
        else raise Refused, "#{@f.name}: a #{type_of(v)} parameter"
        end
      end

      def w(x)
        Machine::Aarch64::Registers.const_get(:"W#{x.to_i}")
      end

      def wide?(v)
        type_of(v) == "i64" || type_of(v) == "f64"
      end

      def float?(v)
        type_of(v) == "f64"
      end

      def reg_for(v, x)
        wide?(v) ? x : w(x)
      end

      # --- prologue and epilogue ---------------------------------------

      def prologue
        @asm.stp X29, X30, [SP, -16], :!
        @asm.mov X29, SP
        sub_sp(@frame)
        entry = @f.blocks.first
        raise Refused, "#{@f.name}: more than eight parameters" if entry.params.size > 8

        ints = 0
        floats = 0
        entry.params.each do |v, t|
          if t == "f64"
            @asm << FP.to_x(9, floats)
            floats += 1
            store_param(v, X9)
          else
            store_param(v, Machine::Aarch64::Registers.const_get(:"X#{ints}"))
            ints += 1
          end
        end
      end

      def sub_sp(n)
        @asm.sub SP, SP, n >> 12, lsl: 12 if n >= 4096
        @asm.sub SP, SP, n & 0xFFF if (n & 0xFFF) != 0
      end

      def epilogue
        @asm.mov SP, X29
        @asm.ldp X29, X30, [SP], 16
        @asm.ret
      end

      # --- instructions -------------------------------------------------

      def emit(i)
        case i.op
        when :iconst then materialize(X9, i.args[0]); store_value(i.results[0], X9)
        when :load then emit_load(i)
        when :store then emit_store(i)
        when :stack_addr
          @asm.add X9, SP, @slot_at[Integer(i.args[0].delete_prefix("ss"))]
          store_value(i.results[0], X9)
        when :symbol_value then emit_symbol(i.results[0], global_of(i.args[0]).symbol, global_of(i.args[0]).colocated)
        when :func_addr
          c = callee_of(i.args[0])
          emit_symbol(i.results[0], c.symbol, @defined.include?(c.symbol))
        when :call then emit_call(i)
        when :call_indirect then emit_call_indirect(i)
        when :icmp
          load_value(i.args[0], X9)
          load_value(i.args[1], X10)
          @asm.cmp reg_for(i.args[0], X9), reg_for(i.args[0], X10)
          @asm.cset X11, CONDS.fetch(i.cond)
          store_value(i.results[0], X11)
        when :iadd, :isub, :imul, :udiv, :sdiv, :band, :bor, :bxor, :ishl, :ushr, :sshr then emit_binop(i)
        when :urem, :srem then emit_rem(i)
        when :ireduce, :uextend
          # A narrower value reads the low bits of its slot; a wider one
          # needs the high bits clear, which the narrow load gives.
          load_value(i.args[0], X9)
          store_value(i.results[0], X9)
        when :sextend
          load_value(i.args[0], X9)
          type_of(i.args[0]) == "i8" ? @asm.sxtb(X9, W9) : @asm.sxtw(X9, W9)
          store_value(i.results[0], X9)
        when :select
          load_value(i.args[0], X9)
          load_value(i.args[1], X10)
          load_value(i.args[2], X11)
          @asm.cmp reg_for(i.args[0], X9), 0
          @asm.csel reg_for(i.args[1], X12), reg_for(i.args[1], X10), reg_for(i.args[1], X11), :ne
          store_value(i.results[0], X12)
        when :sadd_overflow, :ssub_overflow then emit_overflow(i)
        when :smul_overflow then emit_mul_overflow(i)
        when *Inst::FBINOPS
          load_value(i.args[0], X9)
          load_value(i.args[1], X10)
          @asm << FP.to_d(16, 9) << FP.to_d(17, 10) << FP.binop(i.op, 18, 16, 17) << FP.to_x(11, 18)
          store_value(i.results[0], X11)
        when *Inst::FUNOPS
          load_value(i.args[0], X9)
          @asm << FP.to_d(16, 9) << FP.unop(i.op, 17, 16) << FP.to_x(11, 17)
          store_value(i.results[0], X11)
        when :fcmp
          load_value(i.args[0], X9)
          load_value(i.args[1], X10)
          @asm << FP.to_d(16, 9) << FP.to_d(17, 10) << FP.cmp(16, 17)
          @asm.cset X11, FCONDS.fetch(i.cond)
          store_value(i.results[0], X11)
        when :fcvt_from_sint
          load_value(i.args[0], X9)
          @asm << FP.scvtf(16, 9) << FP.to_x(11, 16)
          store_value(i.results[0], X11)
        when :fcvt_to_sint_sat
          load_value(i.args[0], X9)
          @asm << FP.to_d(16, 9) << FP.fcvtzs(11, 16)
          store_value(i.results[0], X11)
        when :bitcast
          load_value(i.args[0], X9)
          store_value(i.results[0], X9)
        when :brif
          # The block that follows needs no branch: control falls into it.
          load_value(i.args[0], X9)
          reg = reg_for(i.args[0], X9)
          yes, no = i.targets.map(&:first)
          if yes == @next
            @asm.cbz reg, @labels.fetch(no)
          else
            @asm.cbnz reg, @labels.fetch(yes)
            @asm.b @labels.fetch(no) unless no == @next
          end
        when :jump then emit_jump(i)
        when :return
          unless i.args.empty?
            load_value(i.args[0], X0)
            @asm << FP.to_d(0, 0) if float?(i.args[0])
          end
          epilogue
        else raise Refused, "#{@f.name}: no lowering for #{i.op}"
        end
      end

      def emit_load(i)
        load_value(i.args[0], X9)
        case i.type
        when "i64", "f64" then @asm.ldr X10, [X9, i.offset]
        when "i32" then @asm.ldr W10, [X9, i.offset]
        when "i8" then @asm.ldrb W10, [X9, i.offset]
        else raise Refused, "#{@f.name}: load.#{i.type}"
        end
        store_value(i.results[0], X10)
      end

      def emit_store(i)
        load_value(i.args[0], X9)
        load_value(i.args[1], X10)
        case type_of(i.args[0])
        when "i64", "f64" then @asm.str X9, [X10, i.offset]
        when "i32" then @asm.str W9, [X10, i.offset]
        when "i8" then @asm.strb W9, [X10, i.offset]
        end
      end

      # A symbol's address: page plus offset for one this link defines,
      # through the GOT for an import.
      def emit_symbol(result, symbol, local)
        if local
          reloc(:page21, symbol)
          @asm.adrp X9, 0
          reloc(:pageoff12, symbol)
          @asm.add X9, X9, 0
        else
          reloc(:got_page21, symbol)
          @asm.adrp X9, 0
          reloc(:got_pageoff12, symbol)
          @asm.ldr X9, [X9, 0]
        end
        store_value(result, X9)
      end

      def emit_call(i)
        c = callee_of(i.callee)
        sig = sig_of(i.callee)
        raise Refused, "#{@f.name}: a call with more than eight arguments" if i.args.size > 8

        load_args(i.args)
        reloc(:branch26, c.symbol)
        @asm.bl 0
        return if i.results.empty?

        store_result(i.results[0], sig.ret)
      end

      # Integer arguments take x0.. and float arguments d0.., each in
      # its own order, as the ABI says.
      def load_args(args)
        ints = 0
        floats = 0
        args.each do |v|
          if float?(v)
            load_value(v, X9)
            @asm << FP.to_d(floats, 9)
            floats += 1
          else
            load_value(v, Machine::Aarch64::Registers.const_get(:"X#{ints}"))
            ints += 1
          end
        end
      end

      # A 32-bit or narrower result has undefined bits above: clear them.
      # A float result comes back in d0.
      def store_result(v, ret)
        if ret == "f64"
          @asm << FP.to_x(0, 0)
        elsif ret != "i64"
          @asm.mov W0, W0
        end
        store_value(v, X0)
      end

      # The pointer goes to x9 after the arguments are in place: no
      # argument load touches it.
      def emit_call_indirect(i)
        sig = sig_named(i.callee)
        ptr, *args = i.args
        raise Refused, "#{@f.name}: a call with more than eight arguments" if args.size > 8

        load_args(args)
        load_value(ptr, X9)
        @asm.blr X9
        return if i.results.empty?

        store_result(i.results[0], sig.ret)
      end

      def emit_binop(i)
        load_value(i.args[0], X9)
        load_value(i.args[1], X10)
        d, a, b = [X11, X9, X10].map { |x| reg_for(i.args[0], x) }
        case i.op
        when :iadd then @asm.add d, a, b
        when :isub then @asm.sub d, a, b
        when :imul then @asm.mul d, a, b
        when :udiv then @asm.udiv d, a, b
        when :sdiv then @asm.sdiv d, a, b
        when :band then @asm.and d, a, b
        when :bor then @asm.orr d, a, b
        when :bxor then @asm.eor d, a, b
        when :ishl then @asm.lsl d, a, b
        when :ushr then @asm.lsr d, a, b
        when :sshr then @asm.asr d, a, b
        end
        store_value(i.results[0], X11)
      end

      # `a - (a / b) * b`, as arm64 spells a remainder.
      def emit_rem(i)
        load_value(i.args[0], X9)
        load_value(i.args[1], X10)
        d, a, b = [X11, X9, X10].map { |x| reg_for(i.args[0], x) }
        i.op == :urem ? @asm.udiv(d, a, b) : @asm.sdiv(d, a, b)
        @asm.msub d, d, b, a
        store_value(i.results[0], X11)
      end

      def emit_overflow(i)
        load_value(i.args[0], X9)
        load_value(i.args[1], X10)
        d, a, b = [X11, X9, X10].map { |x| reg_for(i.args[0], x) }
        i.op == :sadd_overflow ? @asm.adds(d, a, b) : @asm.subs(d, a, b)
        @asm.cset X12, :vs
        store_value(i.results[0], X11)
        store_value(i.results[1], X12)
      end

      # 64-bit only: the high half of the product must be the sign of the low.
      def emit_mul_overflow(i)
        raise Refused, "#{@f.name}: smul_overflow on #{type_of(i.args[0])}" unless wide?(i.args[0])

        load_value(i.args[0], X9)
        load_value(i.args[1], X10)
        @asm.mul X11, X9, X10
        @asm.smulh X12, X9, X10
        @asm.cmp X12, X11, shift: :asr, amount: 63
        @asm.cset X12, :ne
        store_value(i.results[0], X11)
        store_value(i.results[1], X12)
      end

      # Block arguments as a parallel copy: every source in a register
      # before any target slot is written.
      def emit_jump(i)
        name, args = i.targets[0]
        raise Refused, "#{@f.name}: a jump with more than seven arguments" if args.size > 7

        params = block_named(name).params
        args.each_with_index { |v, n| load_value(v, SCRATCH[n]) }
        args.each_with_index { |_, n| store_value(params[n][0], SCRATCH[n]) }
        @asm.b @labels.fetch(name) unless name == @next
      end

      # `reg = n`, 16 bits at a time; a negative value starts from its
      # complement so the high halves need no instruction.
      def materialize(reg, n)
        n &= 0xFFFF_FFFF_FFFF_FFFF
        chunks = 4.times.map { |k| (n >> (16 * k)) & 0xFFFF }
        if chunks.count(0xFFFF) > chunks.count(0)
          first = chunks.index { |c| c != 0xFFFF } || 0
          @asm.movn reg, chunks[first] ^ 0xFFFF, lsl: 16 * first
          chunks.each_with_index { |c, k| @asm.movk reg, c, lsl: 16 * k if k != first && c != 0xFFFF }
        else
          first = chunks.index { |c| c != 0 } || 0
          @asm.movz reg, chunks[first], lsl: 16 * first
          chunks.each_with_index { |c, k| @asm.movk reg, c, lsl: 16 * k if k != first && c != 0 }
        end
      end

      def reloc(kind, symbol)
        @asm.patch_location { |off| @relocs << Obj::Reloc.new(off, kind, symbol) }
      end
    end
  end
end
