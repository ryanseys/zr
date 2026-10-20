# frozen_string_literal: true

require_relative "../../backend"
require_relative "registers"
require_relative "assembler"
require_relative "../../ir/function"
require_relative "../../ir/types"
require_relative "../native/moves"
require_relative "../native/planner"
require_relative "../native/regalloc"
require_relative "../../obj/model"

module Zr
  module Backend
    module X86_64
      # Compiles an `IR::Function` to `Obj::Code` of x86-64 machine code
      # for the System V ABI, with a relocation for each symbol that it
      # refers to.
      #
      # A value is in the register that `Regalloc` gives it, or else in an
      # 8-byte frame slot, as on aarch64 (`Native::Planner`). An
      # instruction reads its operands into rax and rcx (rdx for a
      # division), computes in a register, and stores a frame result from
      # a register. A compare that one branch or select reads leaves its
      # result in the flags.
      #
      # The frame is `push rbp; mov rbp, rsp; sub rsp, frame`, laid out as
      # `[outgoing stack arguments) [slots) [values) [saved registers)`
      # and addressed from rsp. rsp stays 16-byte aligned at each call.
      # The gate word is not in a register: a `gates` value is a load of
      # the kernel's static (`zr_static_gates`), which `Machine.gates_set`
      # stores first, so `gates_set` and `gates_enter` emit nothing.
      class Codegen
        # @rbs @f: IR::Function
        # @rbs @defined: Set[String] | Native::Spelled
        # @rbs @allocate: bool
        # @rbs @asm: Assembler
        # @rbs @relocs: Array[Obj::Reloc]
        # @rbs @reg: Hash[String, Registers::Register]
        # @rbs @home: Hash[String, Integer]
        # @rbs @labels: Hash[String, Assembler::Label]
        # @rbs @epilogue: Assembler::Label?
        # @rbs @returns: Integer
        # @rbs @next: String?
        # @rbs @types: IR::Types
        # @rbs @uses: Hash[String, Integer]
        # @rbs @def_of: Hash[String, IR::Inst]
        # @rbs @enters: bool
        # @rbs @pinned: Set[String]
        # @rbs @slot_at: Array[Integer]
        # @rbs @slots_end: Integer
        # @rbs @stack: Hash[String, Integer]
        # @rbs @va_list: IR::Inst?
        # @rbs @const: Hash[String, Integer]
        # @rbs @symbol: Hash[String, [String, bool]]
        # @rbs @remade: Set[String]
        # @rbs @derived: Hash[String, [String, Integer]]
        # @rbs @via: Hash[String, String]
        # @rbs @silent: Set[String]
        # @rbs @from_sp: Hash[String, Integer]
        # @rbs @clean: Set[String]
        # A compare maps to its reader, and the reader to its condition.
        # The key's role tells the two apart.
        # @rbs @fused: Hash[IR::Inst, untyped]
        # @rbs @bit_tests: Hash[IR::Inst, [String, Integer, Symbol]]
        # @rbs @mask_tests: Hash[IR::Inst, [String, Integer | String]]
        # @rbs @pairs: Hash[IR::Inst, IR::Inst]
        # @rbs @paired: Set[IR::Inst]
        # @rbs @saved_at: Hash[Registers::Register, Integer]
        # @rbs @frame: Integer

        # @rbs skip -- in sig/zr/backend/x86_64/registers.rbs
        include Registers
        # @rbs skip -- in sig/zr/backend/x86_64/registers.rbs
        include Native::Planner
        include Native::Moves

        # The two registers that `Native::Moves` moves values through.
        SCRATCH = [R10, RAX].freeze #: [Registers::Register, Registers::Register]
        # The kernel's static that holds the gate word.
        GATE_WORD = "zr_static_gates"
        # A `gates` value is never in a register here (`@pinned` is empty).
        GATES = nil
        # IR conditions as x86 condition codes.
        CONDS = {
          "eq" => :e, "ne" => :ne, "slt" => :l, "sle" => :le, "sgt" => :g, "sge" => :ge,
          "ult" => :b, "ule" => :be, "ugt" => :a, "uge" => :ae
        }.freeze #: Hash[String, Symbol]
        # The condition that is true for `b op a` when the IR gives `a op b`.
        SWAPPED = {
          "eq" => "eq", "ne" => "ne", "slt" => "sgt", "sle" => "sge", "sgt" => "slt", "sge" => "sle",
          "ult" => "ugt", "ule" => "uge", "ugt" => "ult", "uge" => "ule"
        }.freeze #: Hash[String, String]
        # The condition that is true only when the other is false: x86
        # numbers them in pairs that differ in the low bit.
        INVERSE = Assembler::CONDITIONS.to_h do |c, n|
          [c, Assembler::CONDITIONS.key(n ^ 1)]
        end.freeze #: Hash[Symbol, Symbol]
        # The branch of a bit test (`Native::Planner#bit_test`): `bt` puts
        # the bit in CF.
        BIT_BRANCHES = { tbnz: :b, tbz: :ae }.freeze #: Hash[Symbol, Symbol]
        # The opcodes whose lowering here does not change the flags: moves,
        # loads, stores, address forms and conversions. Every ALU operation
        # writes them, and a constant is made with `mov`, never `xor`.
        FLAG_NEUTRAL = %i[iconst load store stack_addr symbol_value func_addr ireduce uextend sextend bitcast
                          gates gates_set gates_enter fcvt_from_sint].to_set.freeze #: Set[IR::op]
        FBINOPS = { fadd: :addsd, fsub: :subsd, fmul: :mulsd, fdiv: :divsd }.freeze #: Hash[IR::op, Symbol]
        # `roundsd`'s mode for each rounding op.
        ROUNDS = { floor: 9, ceil: 10, trunc: 11, nearest: 8 }.freeze #: Hash[IR::op, Integer]
        # The bytes below the slots: the outgoing area for a call's 7th
        # and 8th integer arguments.
        OUTGOING = 16
        # The Value that a QUNDEF check reads, for the stubs.
        QUNDEF = 0x24

        class Refused < Backend::Refused; end

        attr_reader :asm #: Assembler

        # @rbs function: IR::Function
        # @rbs defined: Array[String] | Set[String] | untyped
        # @rbs assembler: singleton(Assembler)
        # @rbs far: bool -- unused: every branch reaches 2 GiB
        # @rbs allocate: bool
        # @rbs return: void
        def initialize(function, defined: [], assembler: Assembler, far: false, allocate: true)
          @f = function
          @defined = defined.to_set
          @allocate = allocate
          @asm = assembler.new
          @relocs = []
          @reg = {}
          @home = {}
          @labels = {}
        end

        #: () -> Obj::Code
        def compile
          assign_types
          count_uses
          @pinned = Set.new
          @pairs = {}
          @paired = Set.new
          plan_slots
          plan_constants
          plan_addresses
          plan_bytes
          plan_fusion
          @reg = @allocate ? Native::Regalloc.of(@f, POOLS, skip: @silent, via: @via) : {} #: Hash[String, Registers::Register]
          assign_homes
          @f.blocks.each { |b| @labels[b.name] = @asm.make_label(b.name) }
          @epilogue = @asm.make_label("epilogue") if @returns > 1
          prologue
          order = laid_out
          order.each_with_index do |b, n|
            @asm.put_label(@labels[b.name])
            @next = order[n + 1]&.name
            b.insts.each { |i| lower(i) }
          end
          if (shared = @epilogue)
            @asm.put_label(shared)
            epilogue
          end
          Obj::Code.new(@f.name, @asm.to_binary, relocs: @relocs, linkage: :export, align: 16)
        end

        private

        # --- Native::Planner hooks ----------------------------------------

        #: (IR::op op) -> bool
        def flag_neutral?(op) = FLAG_NEUTRAL.include?(op)

        # `test r64, imm32` sign-extends its immediate.
        #: (Integer mask, Integer bits) -> bool
        def logical_immediate?(mask, bits) = bits == 32 || !imm32(mask, true).nil?

        # Every constant is one `mov`.
        #: (Integer _n) -> Integer
        def materialized(_n) = 1

        #: (Integer off, Integer _width) -> bool
        def immediate?(off, _width) = off.between?(-(1 << 31), (1 << 31) - 1)

        #: (Integer _off) -> bool
        def slot_address?(_off) = true

        #: () -> Integer
        def frame_base = OUTGOING

        # A function that foreign code enters saves every callee-saved
        # register, so the collector's scan of the C frames finds the
        # values that C keeps in them.
        #: (Array[Registers::Register] used) -> Array[Registers::Register]
        def callee_saves(used)
          saved = @enters ? POOLS.callee : used.select { |r| POOLS.callee?(r) }
          saved.sort_by(&:to_i) #: Array[Registers::Register]
        end

        #: (untyped x) -> bool
        def register?(x) = x.is_a?(Register)

        #: (String v) -> bool
        def wide?(v) = type_of(v) == "i64" || type_of(v) == "f64"

        #: (String v) -> bool
        def float?(v) = type_of(v) == "f64"

        # The register at the width of `v`: 64 bits, else 32.
        #: (String v, Registers::Register x) -> Registers::Register
        def reg_for(v, x) = wide?(v) ? x : x.w

        # `k` as a signed 32-bit immediate of an operation of the width
        # `wide`, or nil when no immediate form takes it.
        #: (Integer k, bool wide) -> Integer?
        def imm32(k, wide)
          return k if !wide && k.between?(0, 0xFFFF_FFFF)

          k -= 1 << 64 if k >= 1 << 63
          k if k.between?(-(1 << 31), (1 << 31) - 1)
        end

        # --- values ---------------------------------------------------------

        #: (Integer off) -> [Registers::Register, Integer]
        def frame(off) = [RSP, off]

        #: (String v, Registers::Register reg) -> void
        def load_value(v, reg)
          home = @reg[v]
          return narrow(reg, home, @clean.include?(v) ? "i64" : type_of(v)) if home
          return @asm.lea(reg, frame(@stack[v])) if @stack.key?(v)
          if @remade.include?(v)
            s = @symbol[v]
            return symbol_address(reg, s[0], s[1]) if s

            return @asm.mov_imm(reg, @const[v] & WIDTH_MASK[type_of(v)])
          end

          off = @home.fetch(v)
          case type_of(v)
          when "i64", "f64" then @asm.ld(reg, frame(off))
          when "i32" then @asm.ld(reg.w, frame(off))
          when "i8" then @asm.ld(reg.b, frame(off))
          else raise Refused, "#{@f.name}: a #{type_of(v)} value"
          end
        end

        # The register to read an operand from: its register home, or else
        # `scratch` after a load. An `i8` is read directly only when it is
        # `@clean`.
        #: (String v, Registers::Register scratch) -> Registers::Register
        def value_in(v, scratch)
          home = @reg[v]
          return home if home && (type_of(v) != "i8" || @clean.include?(v))

          load_value(v, scratch)
          scratch
        end

        #: (String v, Registers::Register scratch) -> Registers::Register
        def result_in(v, scratch) = @reg[v] || scratch

        #: (Registers::Register reg, Registers::Register home, String type) -> void
        def narrow(reg, home, type)
          case type
          when "i64", "f64" then @asm.mov(reg, home)
          when "i32" then @asm.mov(reg.w, home.w)
          when "i8" then @asm.movzx8(reg.w, home.b)
          else raise Refused, "#{@f.name}: a #{type} value"
          end
        end

        #: (String v, Registers::Register reg) -> void
        def store_value(v, reg)
          home = @reg[v]
          return if home.equal?(reg)
          return @asm.mov(home, reg) if home

          @asm.store(frame(@home.fetch(v)), reg)
        end

        #: (String v, Registers::Register reg) -> void
        def store_param(v, reg)
          home = @reg[v]
          return @asm.mov(home, reg) if home

          off = @home.fetch(v)
          case type_of(v)
          when "i64", "f64" then @asm.store(frame(off), reg)
          when "i32" then @asm.store(frame(off), reg.w)
          when "i8" then @asm.store(frame(off), reg.b)
          else raise Refused, "#{@f.name}: a #{type_of(v)} parameter"
          end
        end

        # --- prologue and epilogue ---------------------------------------

        #: () -> void
        def prologue
          @asm.push RBP
          @asm.mov RBP, RSP
          @asm.sub RSP, @frame if @frame.positive?
          @saved_at.each { |r, off| @asm.store(frame(off), r) }
          entry = @f.blocks.first
          raise Refused, "#{@f.name}: more than eight parameters" if entry.params.size > IR::REGISTER_ARGS

          ints, floats = entry.params.partition { |_, t| t != "f64" }.map { |list| list.map(&:first) } #: [Array[String], Array[String]]
          va_list_prologue(ints.size, floats.size)
          held = ints.first(ARGS.size)
          move_registers(held.map { |v| [place(v), v] }, ARGS.first(held.size))
          ints.drop(ARGS.size).each_with_index do |v, n|
            @asm.ld(RAX, [RBP, 16 + (8 * n)])
            store_param(v, RAX)
          end
          floats.each_with_index do |v, n|
            @asm.movq(RAX, XMM[n])
            store_param(v, RAX)
          end
        end

        # Fills a System V va_list (kind 2) before the parameters move: its
        # 24 bytes, then the register save area of rdi..r9 and xmm0..xmm7.
        # `gp_offset` and `fp_offset` skip the named parameters, and the
        # stack arguments start past the named ones that came on the stack.
        #: (Integer ints, Integer floats) -> void
        def va_list_prologue(ints, floats)
          i = @va_list or return

          at = @slot_at[Integer(i.args[0].delete_prefix("ss"))]
          @asm.lea R10, frame(at)
          ARGS.each_with_index { |r, n| @asm.store([R10, 24 + (8 * n)], r) }
          XMM.first(8).each_with_index { |x, n| @asm.movsd_store([R10, 72 + (16 * n)], x) }
          @asm.lea R11, [RBP, 16 + (8 * [ints - ARGS.size, 0].max)]
          @asm.store([R10, 8], R11)
          @asm.lea R11, [R10, 24]
          @asm.store([R10, 16], R11)
          @asm.mov_imm(R11, ([ints, ARGS.size].min * 8) | ((48 + (16 * [floats, 8].min)) << 32))
          @asm.store([R10, 0], R11)
        end

        #: (IR::Inst i) -> void
        def emit_return(i)
          unless i.args.empty?
            load_value(i.args[0], RAX)
            @asm.movq(XMM0, RAX) if float?(i.args[0])
          end
          shared = @epilogue
          return epilogue unless shared

          @asm.jmp shared unless @next.nil?
        end

        #: () -> void
        def epilogue
          @saved_at.each { |r, off| @asm.ld(r, frame(off)) }
          @asm.mov RSP, RBP
          @asm.pop RBP
          @asm.ret
        end

        # --- instructions -------------------------------------------------

        #: (IR::Inst i) -> void
        def lower(i)
          case i.op
          when :iconst
            return if @remade.include?(i.results[0])

            d = result_in(i.results[0], RAX)
            @asm.mov_imm(d, i.args[0])
            store_value(i.results[0], d)
          when :load then emit_load(i)
          when :store then emit_store(i)
          when :stack_addr, :va_list
            return if @remade.include?(i.results[0])

            d = result_in(i.results[0], RAX)
            @asm.lea(d, frame(@slot_at[Integer(i.args[0].delete_prefix("ss"))]))
            store_value(i.results[0], d)
          when :symbol_value
            return if @remade.include?(i.results[0])

            emit_symbol(i.results[0], global_of(i.args[0]).symbol, global_of(i.args[0]).colocated)
          when :gates
            d = result_in(i.results[0], RAX)
            @asm.load_rip(d) { |at| reloc(at, :pc32, GATE_WORD) }
            store_value(i.results[0], d)
          when :gates_set, :gates_enter then nil
          when :func_addr
            c = callee_of(i.args[0])
            emit_symbol(i.results[0], c.symbol, @defined.include?(c.symbol))
          when :call then emit_call(i)
          when :call_indirect then emit_call_indirect(i)
          when :icmp, :fcmp
            if (reader = @fused[i])
              @fused[reader] = i.op == :icmp ? emit_compare(i) : emit_fcompare(i)
              return
            end
            return if @silent.include?(i.results[0])

            cond = i.op == :icmp ? emit_compare(i) : emit_fcompare(i)
            d = result_in(i.results[0], RAX)
            @asm.set(cond, d)
            @asm.movzx8(d.w, d.b)
            store_value(i.results[0], d)
          when :iadd, :isub, :imul, :band, :bor, :bxor, :ishl, :ushr, :sshr
            return if @silent.include?(i.results[0])

            if (at = @from_sp[i.results[0]])
              d = result_in(i.results[0], RAX)
              @asm.lea(d, frame(at))
              store_value(i.results[0], d)
              return
            end
            emit_binop(i)
          when :udiv, :sdiv, :urem, :srem then emit_divide(i)
          when :ctz, :clz, :popcnt, :bswap then emit_bitop(i)
          when :ireduce, :uextend, :bitcast
            d = result_in(i.results[0], RAX)
            load_value(i.args[0], d)
            store_value(i.results[0], d)
          when :sextend
            a = value_in(i.args[0], RAX)
            d = result_in(i.results[0], RAX)
            type_of(i.args[0]) == "i8" ? @asm.movsx8(d, a.b) : @asm.movsxd(d, a.w)
            store_value(i.results[0], d)
          when :select then emit_select(i)
          when :sadd_overflow, :ssub_overflow, :smul_overflow then emit_overflow(i)
          when :fadd, :fsub, :fmul, :fdiv
            @asm.movq XMM0, value_in(i.args[0], RAX)
            @asm.movq XMM1, value_in(i.args[1], RCX)
            @asm.public_send(FBINOPS.fetch(i.op), XMM0, XMM1)
            float_result(i.results[0])
          when :fneg, :fabs
            d = result_in(i.results[0], RAX)
            load_value(i.args[0], d)
            i.op == :fneg ? @asm.btc(d, 63) : @asm.btr(d, 63)
            store_value(i.results[0], d)
          when :sqrt, :floor, :ceil, :trunc, :nearest
            @asm.movq XMM0, value_in(i.args[0], RAX)
            i.op == :sqrt ? @asm.sqrtsd(XMM0, XMM0) : @asm.roundsd(XMM0, XMM0, ROUNDS.fetch(i.op))
            float_result(i.results[0])
          when :fcvt_from_sint
            @asm.cvtsi2sd XMM0, reg_for(i.args[0], value_in(i.args[0], RAX))
            float_result(i.results[0])
          when :fcvt_to_sint_sat then emit_to_sint(i)
          when :brif then emit_brif(i)
          when :switch then emit_switch(i)
          when :jump then emit_jump(i)
          when :return then emit_return(i)
          else raise Refused, "#{@f.name}: no lowering for #{i.op}"
          end
        end

        #: (String v) -> void
        def float_result(v)
          d = result_in(v, RAX)
          @asm.movq d, XMM0
          store_value(v, d)
        end

        # A branch to one of two blocks: on a bit test, on the flags of a
        # fused compare, or on the boolean. The next block needs no branch.
        #: (IR::Inst i) -> void
        def emit_brif(i)
          yes, no = i.targets.map(&:first) #: [String, String]
          if (x, bit, op = @bit_tests[i])
            @asm.bt value_in(x, RAX), bit
            cond = BIT_BRANCHES.fetch(op)
          elsif (fused = @fused[i])
            cond = fused
          else
            r = reg_for(i.args[0], value_in(i.args[0], RAX))
            @asm.tst r, r
            cond = :ne
          end
          if yes == @next
            @asm.j INVERSE.fetch(cond), @labels.fetch(no)
          else
            @asm.j cond, @labels.fetch(yes)
            @asm.jmp @labels.fetch(no) unless no == @next
          end
        end

        # A jump table of 32-bit distances from the table to each block,
        # after a check that sends an index past the table to the default.
        #: (IR::Inst i) -> void
        def emit_switch(i)
          v, *keys = i.args
          names = i.targets.map(&:first)
          default = names.fetch(0)
          to = keys.zip(names.drop(1)).to_h
          lo, hi = keys.minmax
          wide = wide?(v)
          index = reg_for(v, RAX)
          load_value(v, RAX)
          offset_by(index, -lo, wide) unless lo.zero?
          span = hi - lo
          if (k = imm32(span, wide))
            @asm.cmp index, k
          else
            @asm.mov_imm RCX, span
            @asm.cmp index, reg_for(v, RCX)
          end
          @asm.j :a, @labels.fetch(default)
          table = @asm.make_label("#{@f.name}_table")
          @asm.lea_label RCX, table
          @asm.movsxd_load RAX, [RCX, 0, RAX, 4]
          @asm.add RAX, RCX
          @asm.jmp_reg RAX
          @asm.put_label(table)
          (lo..hi).each { |n| @asm.table_word(@labels.fetch(to.fetch(n, default)), table) }
        end

        # `reg += k`, through rcx when `k` takes no immediate.
        #: (Registers::Register reg, Integer k, bool wide) -> void
        def offset_by(reg, k, wide)
          k &= wide ? WIDTH_MASK["i64"] : WIDTH_MASK["i32"]
          if (n = imm32(k, wide))
            @asm.add reg, n
          else
            @asm.mov_imm RCX, k
            @asm.add reg, wide ? RCX : RCX.w
          end
        end

        # `cmov` on the flags of a fused compare, or on its own `test` of
        # the boolean. The moves between the test and the `cmov` keep the
        # flags.
        #: (IR::Inst i) -> void
        def emit_select(i)
          c, a, b = i.args
          cond = @fused[i]
          unless cond
            r = reg_for(c, value_in(c, RAX))
            @asm.tst r, r
            cond = :ne
          end
          x = value_in(a, RCX)
          load_value(b, RAX)
          @asm.cmov cond, reg_for(a, RAX), reg_for(a, x)
          store_value(i.results[0], RAX)
        end

        #: (IR::Inst i) -> void
        def emit_load(i)
          d = result_in(i.results[0], RAX)
          at = through(i.args[0], RCX, i.offset)
          case i.type
          when "i64", "f64" then @asm.ld(d, at)
          when "i32" then @asm.ld(d.w, at)
          when "i8" then @asm.ld(d.b, at)
          else raise Refused, "#{@f.name}: load.#{i.type}"
          end
          store_value(i.results[0], d)
        end

        #: (IR::Inst i) -> void
        def emit_store(i)
          v = value_in(i.args[0], RAX)
          at = through(i.args[1], RCX, i.offset)
          case type_of(i.args[0])
          when "i64", "f64" then @asm.store(at, v)
          when "i32" then @asm.store(at, v.w)
          when "i8" then @asm.store(at, v.b)
          end
        end

        # The memory operand for `off` past the address in `base`: rsp when
        # `base` is a slot's address, a folded base's root plus its
        # constant (`@derived`), or the address in a register. An offset
        # past 32 bits goes through rdx.
        #: (String base, Registers::Register scratch, Integer off) -> [Registers::Register, Integer]
        def through(base, scratch, off)
          root, k = @derived[base]
          if root
            base = root
            off += k
          end
          at = @stack[base] || @from_sp[base]
          return [RSP, at + off] if at && immediate?(at + off, 8)

          reg = value_in(base, scratch)
          return [reg, off] if immediate?(off, 8)

          @asm.mov_imm RDX, off
          @asm.add RDX, reg
          [RDX, 0]
        end

        # A symbol's address: rip-relative for a symbol of this link, or
        # from the GOT for an import.
        #: (String result, String symbol, bool local) -> void
        def emit_symbol(result, symbol, local)
          d = result_in(result, RAX)
          symbol_address(d, symbol, local)
          store_value(result, d)
        end

        #: (Registers::Register reg, String symbol, bool local) -> void
        def symbol_address(reg, symbol, local)
          if local
            @asm.lea_rip(reg) { |at| reloc(at, :pc32, symbol) }
          else
            @asm.load_rip(reg) { |at| reloc(at, :gotpcrel, symbol) }
          end
        end

        #: (IR::Inst i) -> void
        def emit_call(i)
          c = callee_of(i.callee)
          sig = sig_of(i.callee)
          raise Refused, "#{@f.name}: a call with more than eight arguments" if i.args.size > IR::REGISTER_ARGS

          floats = load_args(i.args)
          # A variadic C function reads in al how many vector registers
          # carry arguments.
          @asm.mov_imm(RAX.w, floats) unless @defined.include?(c.symbol)
          @asm.call_rel { |at| reloc(at, :plt32, c.symbol) }
          store_result(i.results[0], sig.ret) unless i.results.empty?
        end

        # The pointer goes to r11, which no argument move uses.
        #: (IR::Inst i) -> void
        def emit_call_indirect(i)
          sig = sig_named(i.callee)
          ptr, *args = i.args
          raise Refused, "#{@f.name}: a call with more than eight arguments" if args.size > IR::REGISTER_ARGS

          load_value(ptr, R11)
          floats = load_args(args)
          @asm.mov_imm(RAX.w, floats)
          @asm.call_reg R11
          store_result(i.results[0], sig.ret) unless i.results.empty?
        end

        # The 7th and 8th integer arguments go to the outgoing area, the
        # floats to xmm0.., then the first six integers move as one
        # parallel copy. Returns the number of float arguments.
        #: (Array[String] args) -> Integer
        def load_args(args)
          floats, ints = args.partition { |v| float?(v) }
          ints.drop(ARGS.size).each_with_index { |v, n| @asm.store(frame(8 * n), value_in(v, RAX)) }
          floats.each_with_index { |v, n| @asm.movq XMM[n], value_in(v, RAX) }
          held = ints.first(ARGS.size)
          move_registers(ARGS.first(held.size).map { |r| [r, nil] }, held)
          floats.size
        end

        # A narrower result has undefined bits above: clear them. A float
        # comes back in xmm0.
        #: (String v, String? ret) -> void
        def store_result(v, ret)
          if ret == "f64"
            @asm.movq RAX, XMM0
          elsif ret != "i64"
            @asm.mov RAX.w, RAX.w
          end
          store_value(v, RAX)
        end

        # `cmp`, or `test` for a mask test, and the condition that reads
        # its flags. A constant on the left moves to the right.
        #: (IR::Inst i) -> Symbol
        def emit_compare(i)
          if (x, mask = @mask_tests[i])
            r = reg_for(x, value_in(x, RAX))
            if mask.is_a?(Integer)
              @asm.tst r, imm32(mask, wide?(x)) || raise(Refused, "#{@f.name}: a mask past 32 bits")
            else
              @asm.tst r, reg_for(x, value_in(mask, RCX))
            end
            return CONDS.fetch(i.cond)
          end

          a, b = i.args
          cond = i.cond
          type = type_of(a)
          if !constant(b, type) && constant(a, type)
            a, b = b, a
            cond = SWAPPED.fetch(cond)
          end
          left = reg_for(a, value_in(a, RAX))
          k = constant(b, type)
          if k && (n = imm32(k, wide?(a)))
            @asm.cmp left, n
          else
            @asm.cmp left, reg_for(a, value_in(b, RCX))
          end
          CONDS.fetch(cond)
        end

        # `ucomisd` sets ZF, PF and CF for an unordered pair. `above` and
        # `above or equal` are false then, so `<` and `<=` compare the
        # other way round. Equality needs ZF and not PF: it makes a byte
        # and tests it, so the reader takes `ne`.
        #: (IR::Inst i) -> Symbol
        def emit_fcompare(i)
          @asm.movq XMM0, value_in(i.args[0], RAX)
          @asm.movq XMM1, value_in(i.args[1], RCX)
          case i.cond
          when "gt", "ge"
            @asm.ucomisd XMM0, XMM1
            i.cond == "gt" ? :a : :ae
          when "lt", "le"
            @asm.ucomisd XMM1, XMM0
            i.cond == "lt" ? :a : :ae
          else
            @asm.ucomisd XMM0, XMM1
            if i.cond == "eq"
              @asm.set :e, RAX
              @asm.set :np, RCX
              @asm.and RAX.b, RCX.b
            else
              @asm.set :ne, RAX
              @asm.set :p, RCX
              @asm.or RAX.b, RCX.b
            end
            :ne
          end
        end

        COMMUTES = %i[iadd imul band bor bxor].freeze #: Array[IR::op]
        ALU = { iadd: :add, isub: :sub, band: :and, bor: :or, bxor: :xor }.freeze #: Hash[IR::op, Symbol]
        SHIFTS = { ishl: :shl, ushr: :shr, sshr: :sar }.freeze #: Hash[IR::op, Symbol]

        # `d = a; d op= b`, where `d` is the result's register unless `b`
        # is in it, and a constant `b` is an immediate when the operation
        # takes one. A shift by a register reads its amount in cl.
        #: (IR::Inst i) -> void
        def emit_binop(i)
          a, b = i.args
          type = type_of(a)
          a, b = b, a if COMMUTES.include?(i.op) && !constant(b, type) && constant(a, type)
          wide = wide?(a)
          k = constant(b, type)
          if (shift = SHIFTS[i.op])
            d = result_in(i.results[0], RAX)
            if k
              load_value(a, d)
              @asm.public_send(shift, reg_for(a, d), k % (wide ? 64 : 32))
            else
              load_value(b, RCX)
              load_value(a, d)
              @asm.public_send(shift, reg_for(a, d), :cl)
            end
            return store_value(i.results[0], d)
          end

          n = k && imm32(k, wide)
          src = n || value_in(b, RCX)
          d = result_in(i.results[0], RAX)
          d = RAX if d.equal?(src)
          load_value(a, d)
          dest = reg_for(a, d)
          operand = src.is_a?(Integer) ? src : reg_for(a, src)
          if i.op == :imul
            operand.is_a?(Integer) ? @asm.imul(dest, dest, operand) : @asm.imul(dest, operand)
          else
            @asm.public_send(ALU.fetch(i.op), dest, operand)
          end
          store_value(i.results[0], d)
        end

        # A division or remainder with the IR's rules: by zero gives 0, or
        # the dividend for a remainder; the most negative number by -1
        # wraps for `sdiv` and gives 0 for `srem`.
        #: (IR::Inst i) -> void
        def emit_divide(i)
          a, b = i.args
          wide = wide?(a)
          ax = reg_for(a, RAX)
          cx = reg_for(a, RCX)
          load_value(a, RAX)
          load_value(b, RCX)
          zero = @asm.make_label("zero")
          done = @asm.make_label("done")
          signed = i.op == :sdiv || i.op == :srem
          rem = i.op == :urem || i.op == :srem
          minus = nil #: Assembler::Label?
          @asm.tst cx, cx
          @asm.j :e, zero
          if signed
            minus = @asm.make_label("minus")
            @asm.cmp cx, -1
            @asm.j :e, minus
            @asm.sign_extend_rax(wide)
            @asm.idiv cx
          else
            @asm.mov_imm RDX.w, 0
            @asm.div cx
          end
          @asm.mov RAX, RDX if rem
          @asm.jmp done
          @asm.put_label(zero)
          @asm.mov_imm(RAX, 0) unless rem
          if minus
            @asm.jmp done
            @asm.put_label(minus)
            rem ? @asm.mov_imm(RAX, 0) : @asm.neg(ax)
          end
          @asm.put_label(done)
          store_value(i.results[0], RAX)
        end

        # `ctz` and `clz` of zero give the width: `bsf` and `bsr` set ZF
        # for a zero source, and a `cmov` puts the width in. `clz` is the
        # top bit's index, flipped.
        #: (IR::Inst i) -> void
        def emit_bitop(i)
          a = i.args[0]
          bits = wide?(a) ? 64 : 32
          ax = reg_for(a, RAX)
          case i.op
          when :popcnt then @asm.popcnt ax, reg_for(a, value_in(a, RCX))
          when :bswap
            load_value(a, RAX)
            @asm.bswap ax
          when :ctz
            @asm.bsf ax, reg_for(a, value_in(a, RCX))
            @asm.mov_imm RDX, bits
            @asm.cmov :e, ax, reg_for(a, RDX)
          when :clz
            @asm.bsr ax, reg_for(a, value_in(a, RCX))
            @asm.mov_imm RDX, (2 * bits) - 1
            @asm.cmov :e, ax, reg_for(a, RDX)
            @asm.xor ax, bits - 1
          end
          store_value(i.results[0], RAX)
        end

        # The operation, then the overflow flag for the branch or select
        # that reads it, or as a byte. `imul` sets OF on a signed overflow
        # of 64 bits.
        #: (IR::Inst i) -> void
        def emit_overflow(i)
          raise Refused, "#{@f.name}: smul_overflow on #{type_of(i.args[0])}" if i.op == :smul_overflow && !wide?(i.args[0])

          a, b = i.args
          x = value_in(b, RCX)
          load_value(a, RAX)
          ax = reg_for(a, RAX)
          case i.op
          when :sadd_overflow then @asm.add ax, reg_for(a, x)
          when :ssub_overflow then @asm.sub ax, reg_for(a, x)
          else @asm.imul ax, x
          end
          store_value(i.results[0], RAX)
          if (reader = @fused[i])
            @fused[reader] = :o
            return
          end
          flag = result_in(i.results[1], RCX)
          @asm.set :o, flag
          @asm.movzx8 flag.w, flag.b
          store_value(i.results[1], flag)
        end

        # `cvttsd2si` gives the most negative number for NaN and for every
        # value past the range. NaN goes to 0, and a positive value past
        # the range to the most positive number, as arm64's `fcvtzs` does.
        #: (IR::Inst i) -> void
        def emit_to_sint(i)
          @asm.movq XMM0, value_in(i.args[0], RAX)
          @asm.cvttsd2si RAX, XMM0
          done = @asm.make_label("done")
          nan = @asm.make_label("nan")
          @asm.mov_imm RCX, 1 << 63
          @asm.cmp RAX, RCX
          @asm.j :ne, done
          @asm.ucomisd XMM0, XMM0
          @asm.j :p, nan
          @asm.movq RCX, XMM0
          @asm.tst RCX, RCX
          @asm.j :s, done
          @asm.mov_imm RAX, (1 << 63) - 1
          @asm.jmp done
          @asm.put_label(nan)
          @asm.mov_imm RAX, 0
          @asm.put_label(done)
          store_value(i.results[0], RAX)
        end

        # Block arguments as a parallel copy (`Native::Moves`).
        #: (IR::Inst i) -> void
        def emit_jump(i)
          name, args = i.targets[0]
          parallel_copy(block_named(name).params.map(&:first), args)
          @asm.jmp @labels.fetch(name) unless name == @next
        end

        # A relocation at the displacement `at`, which ends its instruction,
        # so the value is relative to `at + 4`.
        #: (Integer at, Obj::reloc_kind kind, String symbol) -> void
        def reloc(at, kind, symbol)
          @relocs << Obj::Reloc.new(at, kind, symbol, -4)
        end
      end
    end
  end
end
