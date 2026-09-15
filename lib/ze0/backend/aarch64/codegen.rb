# frozen_string_literal: true

require "set"

require_relative "../../backend"
require_relative "registers"
require_relative "assembler"
require_relative "../../ir/function"
require_relative "../../ir/types"
require_relative "regalloc"
require_relative "../../obj/model"

module Ze0
  module Backend
    module Aarch64
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
      # Encodings come from `Backend::Aarch64`; relocations are recorded
      # here at the instruction's offset.
      class Codegen
        include Registers

        SCRATCH = [X9, X10, X11, X12, X13, X14, X15].freeze
        SCRATCH_W = [W9, W10, W11, W12, W13, W14, W15].freeze
        # The IR's condition codes to arm64's.
        CONDS = {
          "eq" => :eq, "ne" => :ne, "slt" => :lt, "sle" => :le, "sgt" => :gt, "sge" => :ge,
          "ult" => :lo, "ule" => :ls, "ugt" => :hi, "uge" => :hs
        }.freeze
        # Float comparisons after fcmp: NaN on either side sets C and V and
        # clears N and Z, which every condition but `ne` reads as false.
        FCONDS = { "eq" => :eq, "ne" => :ne, "lt" => :mi, "le" => :ls, "gt" => :gt, "ge" => :ge }.freeze
        # The condition that holds exactly when the other does not: arm64
        # numbers them in pairs, so this is the code with its low bit
        # flipped, written out to stay readable.
        # The condition that holds for `b op a` when the IR asked `a op b`.
        SWAPPED = {
          "eq" => "eq", "ne" => "ne", "slt" => "sgt", "sle" => "sge", "sgt" => "slt", "sge" => "sle",
          "ult" => "ugt", "ule" => "uge", "ugt" => "ult", "uge" => "ule"
        }.freeze
        # The bits an operand of each type carries into an instruction:
        # the width its load gives it.
        WIDTH_MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        INVERSE = {
          eq: :ne, ne: :eq, lt: :ge, ge: :lt, le: :gt, gt: :le,
          lo: :hs, hs: :lo, ls: :hi, hi: :ls, mi: :pl, pl: :mi, vs: :vc, vc: :vs
        }.freeze

        # The floating-point instructions, as words: `FMOV Dd, Xn`,
        # `FMOV Xd, Dn`, the arithmetic and the conversions, with d16..d19
        # as scratch. Each carries its own text, because a word the
        # assembler is handed cannot name itself to a listing.
        # The mnemonics the one-operand float instructions go by.
        FUNOPS = { fneg: :fneg, fabs: :fabs, sqrt: :fsqrt, floor: :frintm,
                   ceil: :frintp, trunc: :frintz, nearest: :frintn }.freeze

        class Refused < Backend::Refused; end

        # `far` branches past the megabyte a conditional branch reaches,
        # which only a function that large pays for.
        # The assembler the compile drove, which a caller that gave its own
        # reads its listing out of.
        attr_reader :asm

        # `defined`: every symbol this unit defines, which decides whether a
        # symbol is reached directly or through the GOT. A Set, because a
        # unit names thousands of them and this is asked once per symbol in
        # every function; `to_set` on a Set is the Set, so a caller that
        # already made one pays nothing here.
        def initialize(function, defined: [], assembler: Assembler, far: false)
          @f = function
          @defined = defined.to_set
          @far = far
          @asm = assembler.new
          @relocs = []
          @reg = {}
          @home = {}
          @labels = {}
        end

        def compile
          assign_types
          plan_slots
          plan_constants
          plan_bytes
          @reg = Regalloc.of(@f, skip: @remade)
          plan_fusion
          assign_homes
          @f.blocks.each { |b| @labels[b.name] = @asm.make_label(b.name) }
          prologue
          @f.blocks.each_with_index do |b, n|
            @asm.put_label(@labels[b.name])
            @next = @f.blocks[n + 1]&.name
            b.insts.each { |i| emit(i) }
          end
          Obj::Function.new(@f.name, @asm.to_binary, relocs: @relocs, linkage: :export)
        rescue Assembler::OutOfReach
          # A conditional branch that cannot reach its block: the whole
          # function again, every such branch the long way.
          raise if @far

          # This attempt's code and plans are as big as the function, and
          # nothing reads them again: let them go before the second is made.
          assembler = @asm.class
          @asm = @reg = @home = @labels = @relocs = @const = @remade = @types = nil
          again = self.class.new(@f, defined: @defined, assembler: assembler, far: true)
          bytes = again.compile
          @asm = again.asm
          bytes
        end

        private

        # --- layout -------------------------------------------------------

        def assign_types
          @types = IR::Types.new(@f)
          @types.all
        rescue IR::Types::Refused => e
          raise Refused, e.message
        end

        def type_of(v)
          @types.of(v)
        rescue IR::Types::Refused => e
          raise Refused, e.message
        end

        # An `icmp` whose one use is the `brif` right after it needs no
        # boolean at all: the compare sets the flags and the branch reads
        # them. `docs/plan.md` has said so since the backend was specified.
        #
        # Without it the pair costs `cmp`, `cset`, a store of the byte, a
        # load of it back, a `uxtb` and a `cbz`. `Zr::Function#checked`
        # writes one after every call a compiled Ruby method makes, so this
        # is the shape most branches in the program have.
        #
        # Adjacency is what makes the flags safe: nothing runs between the
        # two, so nothing can write NZCV in between.
        def plan_fusion
          counted = Hash.new(0)
          @f.blocks.each do |b|
            b.insts.each do |i|
              i.args.each { |a| counted[a] += 1 if Regalloc.value?(a) }
              i.targets&.each { |(_, args)| args.each { |a| counted[a] += 1 if Regalloc.value?(a) } }
            end
          end
          @fused = {}
          @f.blocks.each do |b|
            # A constant made at its reads emits nothing where it stands, so
            # it does not part a compare from its branch.
            b.insts.reject { |i| @remade.include?(i.results[0]) }.each_cons(2) do |cmp, brif|
              next unless cmp.op == :icmp && brif.op == :brif

              r = cmp.results[0]
              next unless brif.args[0] == r && counted[r] == 1

              @fused[cmp] = brif
              @fused[brif] = CONDS.fetch(cmp.cond)
            end
          end
        end

        # Where each slot sits above sp. Slots come first in the frame, so
        # this is known before any value has a home.
        #
        # A slot's address is made where it is read, as a small constant
        # is (`@stack`): `IR::Function#hoisted` puts every `stack_addr` in
        # the entry block, so each one held a register for the whole
        # function, and the frame saved and restored that register. A load
        # or a store through it addresses sp directly and makes nothing.
        def plan_slots
          off = 0
          @slot_at = @f.slots.map do |s|
            off = align(off, [s.align, 8].max)
            at = off
            off += s.bytes
            at
          end
          @slots_end = align(off, 8)
          @stack = {}
          @f.blocks.each do |b|
            b.insts.each do |i|
              next unless i.op == :stack_addr

              at = @slot_at[Integer(i.args[0].delete_prefix("ss"))]
              @stack[i.results[0]] = at if at <= 4095
            end
          end
        end

        # Every `iconst` by the value it names. A value is defined once, so
        # wherever it is used its number is known, and an instruction with
        # an immediate form can take the number instead of a register.
        #
        # A constant one instruction makes is made again at every read and
        # nowhere else (`@remade`): no register, no slot, and nothing at its
        # definition. A read that takes it as an immediate makes nothing at
        # all, and one that does not pays a `movz` where it paid an `ldr`.
        # The register it no longer holds goes to a value that has to live
        # somewhere. `IR::Function#hoisted` puts every constant in the entry
        # block, so each of them held one for the whole function.
        def plan_constants
          @const = {}
          @remade = Set.new(@stack.keys)
          @f.blocks.each do |b|
            b.insts.each do |i|
              next unless i.op == :iconst

              v = i.results[0]
              @const[v] = i.args[0]
              type = type_of(v)
              @remade << v if WIDTH_MASK.key?(type) && materialized(i.args[0] & WIDTH_MASK[type]) == 1
            end
          end
        end

        # The `i8` values whose register holds nothing above the byte, which
        # an operation may then read straight out of its home.
        #
        # A register home holds a whole word, and most bytes leave junk
        # above them -- a narrowing keeps the word it narrowed, a call's
        # answer is only its low byte -- so reading one takes a `uxtb`. A
        # comparison's `cset`, a byte load and a small constant write zero
        # above, and so do `and`, `orr` and `eor` of two such bytes. Those
        # are most of the bytes a kernel function has: every `&&` and `||`
        # over tests joins two of them.
        def plan_bytes
          @clean = Set.new
          @f.blocks.each do |b|
            b.insts.each do |i|
              v = i.results[0]
              next unless v && type_of(v) == "i8"

              @clean << v if case i.op
                             when :icmp, :fcmp, :load then true
                             when :iconst then i.args[0].between?(0, 255)
                             when :band, :bor, :bxor then i.args.all? { |a| @clean.include?(a) }
                             end
            end
          end
        end

        # The number `v` holds, as `type` wide, when it is a constant.
        def constant(v, type)
          k = @const[v]
          k && k & WIDTH_MASK.fetch(type, 0xFFFF_FFFF_FFFF_FFFF)
        end

        def assign_homes
          off = @slots_end
          @f.blocks.each do |b|
            (b.params.map(&:first) + b.insts.flat_map(&:results)).each do |v|
              next if @reg.key?(v) || @remade.include?(v)

              @home[v] = off
              off += 8
            end
          end
          # A callee-saved register this function uses has to come back to
          # its caller as it was, so the frame keeps a place for each.
          @saved_at = {}
          @reg.values.uniq.sort_by(&:to_i).each do |r|
            @saved_at[r] = off
            off += 8
          end
          @frame = align(off, 16)
        end

        def align(n, a)
          (n + a - 1) & ~(a - 1)
        end

        def sig_of(fn) = @types.sig_of(fn)
        def sig_named(sig) = @types.sig_named(sig)
        def callee_of(fn) = @types.callee_named(fn)
        def global_of(gv) = @types.global_named(gv)
        def block_named(name) = @types.block_named(name)

        # --- frame access -------------------------------------------------

        # `[base, offset]` for `off` from sp, the offset small enough for a
        # scaled immediate of `width` bytes; x17 holds a page base when not.
        #
        # x17 and not a scratch register: `emit_jump` stages a jump's
        # arguments in `SCRATCH` and then stores each one, and a store to a
        # far offset comes back here. With x15 as the page base -- x15 is
        # `SCRATCH[6]` -- storing argument 5 would destroy argument 6 before
        # it was stored. x16 and x17 are the linker's veneer registers, dead
        # across every call and named nowhere else in the backend.
        def address(off, width)
          return [SP, off] if off % width == 0 && off / width <= 4095

          hi = off & ~0xFFF
          @asm.add X17, SP, hi >> 12, lsl: 12
          [X17, off & 0xFFF]
        end

        # `reg = sp + off`: one `add` for twelve bits, two past them.
        def frame_address(reg, off)
          return @asm.add(reg, SP, off) if off <= 4095

          @asm.add reg, SP, off >> 12, lsl: 12
          @asm.add reg, reg, off & 0xFFF unless (off & 0xFFF).zero?
        end

        # An f64 value lives in its slot as bits and moves through the
        # integer registers.
        def load_value(v, reg)
          home = @reg[v]
          return narrow(reg, home, @clean.include?(v) ? "i64" : type_of(v)) if home
          return frame_address(reg, @stack[v]) if @stack.key?(v)
          return materialize(reg, @const[v] & WIDTH_MASK[type_of(v)]) if @remade.include?(v)

          off = @home.fetch(v)
          case type_of(v)
          when "i64", "f64" then @asm.ldr reg, address(off, 8)
          when "i32" then @asm.ldr w(reg), address(off, 4)
          when "i8" then @asm.ldrb w(reg), address(off, 1)
          else raise Refused, "#{@f.name}: a #{type_of(v)} value"
          end
        end

        # The register an operand can be read out of: its own home when it
        # has one, and `scratch` after a load when it does not.
        #
        # Only operands are read this way. A result always goes to a scratch
        # register and is stored from there, because an instruction that
        # writes its destination before reading every source would otherwise
        # clobber an operand that shares the register.
        #
        # An `i8` has no direct form unless it is `@clean`: its home holds
        # the whole word, and a w-register read would carry the bits above
        # the byte into an operation that is 32 bits wide.
        def value_in(v, scratch)
          home = @reg[v]
          return home if home && (type_of(v) != "i8" || @clean.include?(v))

          load_value(v, scratch)
          scratch
        end

        # Where a result is computed: its own register home when it has
        # one, and a scratch register to be stored from when it does not.
        #
        # Only an instruction that reads every operand before it writes its
        # destination may use this. One that reads an operand again
        # afterwards -- `emit_rem` and `emit_mul_overflow` do -- would find
        # the operand overwritten.
        def result_in(v, scratch) = @reg[v] || scratch

        # A register home holds the whole word, so a narrower value takes
        # the low bits of it, which is what the narrow load gives.
        def narrow(reg, home, type)
          case type
          when "i64", "f64" then @asm.mov reg, home
          when "i32" then @asm.mov w(reg), w(home)
          when "i8" then @asm.uxtb w(reg), w(home)
          else raise Refused, "#{@f.name}: a #{type} value"
          end
        end

        # Store the whole 64-bit register: a 32-bit result has zero above.
        def store_value(v, reg)
          home = @reg[v]
          return if home.equal?(reg)
          return @asm.mov(home, reg) if home

          @asm.str reg, address(@home.fetch(v), 8)
        end

        def store_param(v, reg)
          home = @reg[v]
          return @asm.mov(home, reg) if home

          off = @home.fetch(v)
          case type_of(v)
          when "i64", "f64" then @asm.str reg, address(off, 8)
          when "i32" then @asm.str w(reg), address(off, 4)
          when "i8" then @asm.strb w(reg), address(off, 1)
          else raise Refused, "#{@f.name}: a #{type_of(v)} parameter"
          end
        end

        def w(x)
          Registers.w(x.to_i)
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
          @saved_at.each { |r, off| @asm.str r, address(off, 8) }
          entry = @f.blocks.first
          # Eight is where the registers run out and the ABI starts pushing
          # arguments onto the stack. Nothing reaches it: every lowering
          # keeps a signature to eight, and the whole runtime -- 4732
          # functions -- sits at eight parameters and eight call arguments
          # and never above. So this refuses rather than growing a stack
          # argument path no program would take.
          raise Refused, "#{@f.name}: more than eight parameters" if entry.params.size > IR::REGISTER_ARGS

          ints = 0
          floats = 0
          entry.params.each do |v, t|
            if t == "f64"
              @asm.fmov X9, Registers.d(floats)
              floats += 1
              store_param(v, X9)
            else
              store_param(v, Registers.const_get(:"X#{ints}"))
              ints += 1
            end
          end
        end

        # Two immediates reach 16 MiB less one page; a frame past that is
        # refused by name rather than cut short.
        def sub_sp(n)
          raise Refused, "#{@f.name} needs a frame of #{n} bytes, past the 16 MiB sub sp reaches" if n >= 1 << 24

          @asm.sub SP, SP, n >> 12, lsl: 12 if n >= 4096
          @asm.sub SP, SP, n & 0xFFF if (n & 0xFFF) != 0
        end

        def epilogue
          @saved_at.each { |r, off| @asm.ldr r, address(off, 8) }
          @asm.mov SP, X29
          @asm.ldp X29, X30, [SP], 16
          @asm.ret
        end

        # --- instructions -------------------------------------------------

        def emit(i)
          case i.op
          when :iconst
            return if @remade.include?(i.results[0])

            d = result_in(i.results[0], X9)
            materialize(d, i.args[0])
            store_value(i.results[0], d)
          when :load then emit_load(i)
          when :store then emit_store(i)
          when :stack_addr
            return if @remade.include?(i.results[0])

            frame_address(X9, @slot_at[Integer(i.args[0].delete_prefix("ss"))])
            store_value(i.results[0], X9)
          when :symbol_value then emit_symbol(i.results[0], global_of(i.args[0]).symbol, global_of(i.args[0]).colocated)
          when :func_addr
            c = callee_of(i.args[0])
            emit_symbol(i.results[0], c.symbol, @defined.include?(c.symbol))
          when :call then emit_call(i)
          when :call_indirect then emit_call_indirect(i)
          when :icmp
            cond = emit_compare(i)
            # The `brif` that follows reads the flags; there is no boolean.
            if (brif = @fused[i])
              @fused[brif] = cond
              return
            end

            d = result_in(i.results[0], X11)
            @asm.cset d, cond
            store_value(i.results[0], d)
          when :iadd, :isub, :imul, :udiv, :sdiv, :band, :bor, :bxor, :ishl, :ushr, :sshr then emit_binop(i)
          when :urem, :srem then emit_rem(i)
          when :ireduce, :uextend
            # A narrower value reads the low bits of its slot; a wider one
            # needs the high bits clear, which the narrow load gives.
            load_value(i.args[0], X9)
            store_value(i.results[0], X9)
          when :sextend
            a = value_in(i.args[0], X9)
            type_of(i.args[0]) == "i8" ? @asm.sxtb(X9, w(a)) : @asm.sxtw(X9, w(a))
            store_value(i.results[0], X9)
          when :select
            cond = value_in(i.args[0], X9)
            a = value_in(i.args[1], X10)
            b = value_in(i.args[2], X11)
            d = result_in(i.results[0], X12)
            @asm.cmp reg_for(i.args[0], cond), 0
            @asm.csel reg_for(i.args[1], d), reg_for(i.args[1], a), reg_for(i.args[1], b), :ne
            store_value(i.results[0], d)
          when :sadd_overflow, :ssub_overflow then emit_overflow(i)
          when :smul_overflow then emit_mul_overflow(i)
          when *IR::Inst::FBINOPS
            a = value_in(i.args[0], X9)
            b = value_in(i.args[1], X10)
            @asm.fmov D16, a
            @asm.fmov D17, b
            @asm.public_send(i.op, D18, D16, D17)
            @asm.fmov X11, D18
            store_value(i.results[0], X11)
          when *IR::Inst::FUNOPS
            a = value_in(i.args[0], X9)
            @asm.fmov D16, a
            @asm.public_send(FUNOPS.fetch(i.op), D17, D16)
            @asm.fmov X11, D17
            store_value(i.results[0], X11)
          when :fcmp
            a = value_in(i.args[0], X9)
            b = value_in(i.args[1], X10)
            @asm.fmov D16, a
            @asm.fmov D17, b
            @asm.fcmp D16, D17
            @asm.cset X11, FCONDS.fetch(i.cond)
            store_value(i.results[0], X11)
          when :fcvt_from_sint
            a = value_in(i.args[0], X9)
            @asm.scvtf D16, wide?(i.args[0]) ? a : Registers.w(a.to_i)
            @asm.fmov X11, D16
            store_value(i.results[0], X11)
          when :fcvt_to_sint_sat
            a = value_in(i.args[0], X9)
            @asm.fmov D16, a
            @asm.fcvtzs X11, D16
            store_value(i.results[0], X11)
          when :bitcast
            load_value(i.args[0], X9)
            store_value(i.results[0], X9)
          when :brif
            yes, no = i.targets.map(&:first)
            # A fused compare left the answer in the flags.
            if (cond = @fused[i])
              if yes == @next
                branch_on(INVERSE.fetch(cond), no)
              else
                branch_on(cond, yes)
                @asm.b @labels.fetch(no) unless no == @next
              end
              return
            end
            # The block that follows needs no branch: control falls into it.
            reg = reg_for(i.args[0], value_in(i.args[0], X9))
            if yes == @next
              branch_if(:cbz, reg, no)
            else
              branch_if(:cbnz, reg, yes)
              @asm.b @labels.fetch(no) unless no == @next
            end
          when :jump then emit_jump(i)
          when :return
            unless i.args.empty?
              load_value(i.args[0], X0)
              @asm.fmov D0, X0 if float?(i.args[0])
            end
            epilogue
          else raise Refused, "#{@f.name}: no lowering for #{i.op}"
          end
        end

        # `cbz` or `cbnz` to a block. A far one branches the other way over
        # a `b`, which reaches 128 megabytes to the megabyte of its own.
        def branch_if(op, reg, target)
          return @asm.public_send(op, reg, @labels.fetch(target)) unless @far

          @asm.public_send(op == :cbz ? :cbnz : :cbz, reg, 2)
          @asm.b @labels.fetch(target)
        end

        # `b.cond` to a block, on the flags a fused compare left. A far one
        # branches the other way over a `b`, as `branch_if` does.
        def branch_on(cond, target)
          return @asm.b(@labels.fetch(target), cond: cond) unless @far

          @asm.b 2, cond: INVERSE.fetch(cond)
          @asm.b @labels.fetch(target)
        end

        def emit_load(i)
          d = result_in(i.results[0], X10)
          case i.type
          when "i64", "f64" then @asm.ldr d, through(i.args[0], X9, i.offset, 8)
          when "i32" then @asm.ldr w(d), through(i.args[0], X9, i.offset, 4)
          when "i8" then @asm.ldrb w(d), through(i.args[0], X9, i.offset, 1)
          else raise Refused, "#{@f.name}: load.#{i.type}"
          end
          store_value(i.results[0], d)
        end

        def emit_store(i)
          v = value_in(i.args[0], X9)
          case type_of(i.args[0])
          when "i64", "f64" then @asm.str v, through(i.args[1], X10, i.offset, 8)
          when "i32" then @asm.str w(v), through(i.args[1], X10, i.offset, 4)
          when "i8" then @asm.strb w(v), through(i.args[1], X10, i.offset, 1)
          end
        end

        # The memory operand for `off` past the address `base` holds: sp
        # itself when `base` is a slot's address and the sum fits, else the
        # address in a register, read into `scratch` when it has none.
        def through(base, scratch, off, width)
          at = @stack[base]
          return [SP, at + off] if at && off >= 0 && (at + off) % width == 0 && (at + off) / width <= 4095

          reach(value_in(base, scratch), off, width)
        end

        # A base and an offset one load or store can hold: the offset
        # scaled into twelve bits, else the whole address built in X11
        # first, which neither emitter above uses.
        def reach(base, off, width)
          return [base, off] if off >= 0 && off % width == 0 && off / width <= 4095

          materialize(X11, off)
          @asm.add X11, base, X11
          [X11, 0]
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
          raise Refused, "#{@f.name}: a call with more than eight arguments" if i.args.size > IR::REGISTER_ARGS

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
              @asm.fmov Registers.d(floats), X9
              floats += 1
            else
              load_value(v, Registers.const_get(:"X#{ints}"))
              ints += 1
            end
          end
        end

        # A 32-bit or narrower result has undefined bits above: clear them.
        # A float result comes back in d0.
        def store_result(v, ret)
          if ret == "f64"
            @asm.fmov X0, D0
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
          raise Refused, "#{@f.name}: a call with more than eight arguments" if args.size > IR::REGISTER_ARGS

          load_args(args)
          @asm.blr value_in(ptr, X9)
          return if i.results.empty?

          store_result(i.results[0], sig.ret)
        end

        # `cmp`, and the arm64 condition to read its flags by. A constant
        # of twelve bits is the immediate form and takes no register: the
        # check `Zr::Function#checked` makes after every call is `cmp x, #52`.
        # A constant on the left goes to the right, and the condition turns
        # round with it.
        def emit_compare(i)
          a, b = i.args
          cond = i.cond
          type = type_of(a)
          if !constant(b, type) && constant(a, type)
            a, b = b, a
            cond = SWAPPED.fetch(cond)
          end
          left = reg_for(a, value_in(a, X9))
          k = constant(b, type)
          if k && k <= 4095
            @asm.cmp left, k
          else
            @asm.cmp left, reg_for(a, value_in(b, X10))
          end
          CONDS.fetch(cond)
        end

        COMMUTES = %i[iadd band bor bxor].freeze
        SHIFTS = { ishl: :lsl, ushr: :lsr, sshr: :asr }.freeze
        LOGICAL = { band: :and, bor: :orr, bxor: :eor }.freeze

        # A binary operation, with its constant operand as an immediate
        # when the instruction has a form for one.
        def emit_binop(i)
          return if emit_immediate_binop(i)

          dest = result_in(i.results[0], X11)
          d, a, b = [dest, value_in(i.args[0], X9), value_in(i.args[1], X10)].map { |x| reg_for(i.args[0], x) }
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
          store_value(i.results[0], dest)
        end

        # `add`/`sub` of twelve bits, a shift by a number in the register,
        # and `and`/`orr`/`eor` of a bitmask immediate. False when the
        # constant fits no form, and nothing is emitted.
        #
        # The constant is taken as wide as its type, which is what loading
        # it would have given; the instruction then runs at the width the
        # register form would have, so the low bits of the answer are the
        # same bits.
        def emit_immediate_binop(i)
          a, b = i.args
          type = type_of(a)
          return false if type == "f64"

          a, b = b, a if COMMUTES.include?(i.op) && !constant(b, type) && constant(a, type)
          k = constant(b, type)
          return false unless k

          bits = wide?(a) ? 64 : 32
          full = (1 << bits) - 1
          form =
            case i.op
            when :iadd, :isub
              negated = -k & full
              if k <= 4095 then [i.op == :iadd ? :add : :sub, k]
              elsif negated <= 4095 then [i.op == :iadd ? :sub : :add, negated]
              end
            when :ishl, :ushr, :sshr then [SHIFTS.fetch(i.op), k] if k < bits
            when :band, :bor, :bxor then [LOGICAL.fetch(i.op), k] if Assembler.bitmask(k, bits)
            end
          return false unless form

          dest = result_in(i.results[0], X11)
          @asm.public_send(form[0], reg_for(a, dest), reg_for(a, value_in(a, X9)), form[1])
          store_value(i.results[0], dest)
          true
        end

        # `a - (a / b) * b`, as arm64 spells a remainder.
        def emit_rem(i)
          d, a, b = [X11, value_in(i.args[0], X9), value_in(i.args[1], X10)].map { |x| reg_for(i.args[0], x) }
          i.op == :urem ? @asm.udiv(d, a, b) : @asm.sdiv(d, a, b)
          @asm.msub d, d, b, a
          store_value(i.results[0], X11)
        end

        def emit_overflow(i)
          dest = result_in(i.results[0], X11)
          flag = result_in(i.results[1], X12)
          d, a, b = [dest, value_in(i.args[0], X9), value_in(i.args[1], X10)].map { |x| reg_for(i.args[0], x) }
          i.op == :sadd_overflow ? @asm.adds(d, a, b) : @asm.subs(d, a, b)
          @asm.cset flag, :vs
          store_value(i.results[0], dest)
          store_value(i.results[1], flag)
        end

        # 64-bit only: the high half of the product must be the sign of the low.
        def emit_mul_overflow(i)
          raise Refused, "#{@f.name}: smul_overflow on #{type_of(i.args[0])}" unless wide?(i.args[0])

          a = value_in(i.args[0], X9)
          b = value_in(i.args[1], X10)
          @asm.mul X11, a, b
          @asm.smulh X12, a, b
          @asm.cmp X12, X11, shift: :asr, amount: 63
          @asm.cset X12, :ne
          store_value(i.results[0], X11)
          store_value(i.results[1], X12)
        end

        # Block arguments as a parallel copy: every destination ends up
        # holding what its source held before the jump, whatever order the
        # copies go in.
        #
        # No limit on how many an edge carries. There was one -- seven,
        # one `SCRATCH` register an argument -- because the old form held
        # every source at once. The resolver holds one.
        def emit_jump(i)
          name, args = i.targets[0]
          parallel_copy(block_named(name).params.map(&:first), args)
          @asm.b @labels.fetch(name) unless name == @next
        end

        # Where a value is between instructions: the register the allocator
        # gave it, or the offset of its frame slot. Two values share a
        # place only by sharing a register, because every slot has its own
        # offset.
        #
        # A Register and an Integer in one Hash, and not a pair naming
        # which: a Register carries the identity every register object is
        # compared by and is never equal to a number, so the two kinds
        # cannot collide -- and this runs several times for every edge in
        # the program, which is no place to make an Array.
        #
        # A constant made where it is read has no place, and is never a
        # destination: its own name stands for it, which no Register and no
        # Integer equals.
        def place(v) = @reg[v] || @home.fetch(v) { @remade.include?(v) ? v : raise(KeyError, v) }

        # The copies an edge asks for, in an order where no destination is
        # written while a source still has to be read out of it.
        #
        # Loading every source into `SCRATCH` and then storing every one is
        # always correct and almost always wasteful. An argument the
        # allocator already put where its parameter lives -- a loop
        # variable carried along the back edge unchanged, which is most of
        # what a `while` passes -- needs no instruction at all; one that is
        # not there needs a single load, `mov` or store; and a temporary is
        # needed only for a real cycle, where two parameters trade places.
        #
        # It is worth less than it looks: every `if`, `while`, `&&` and
        # `||` merge in the zr road comes through here, but the allocator
        # hands out ten registers, so most arguments and most parameters
        # are in the frame and a slot to a slot still costs a load and a
        # store. The saving is on the edges where one end got a register.
        #
        # `SCRATCH[0]` carries one copy and is dead after it. `SCRATCH[1]`
        # holds the value a broken cycle took out of the way, and is live
        # until that cycle's last copy.
        def parallel_copy(dests, srcs)
          pending = {}
          reads = Hash.new(0)
          dests.each_with_index do |d, n|
            s = srcs[n]
            to = place(d)
            from = place(s)
            # Already there. The types have to agree as well: a place holds
            # a whole word, and a narrower value is read out of it by its
            # own width.
            next if to == from && type_of(d) == type_of(s)

            pending[to] = [d, s]
            reads[from] += 1
          end
          drain(pending, reads)
          break_cycle(pending) until pending.empty?
        end

        # Every copy whose destination no pending copy still reads, and
        # then every copy that one freed, until only cycles are left.
        def drain(pending, reads)
          ready = pending.keys.reject { |p| reads[p].positive? }
          while (p = ready.pop)
            d, s = pending.delete(p)
            copy(d, s)
            from = place(s)
            reads[from] -= 1
            ready << from if reads[from].zero? && pending.key?(from)
          end
        end

        # What `drain` leaves behind is cycles and nothing else: every
        # remaining destination is still read, and a copy reads one place,
        # so the places left map one to one onto themselves.
        #
        # Take one copy out of the way -- its source into a scratch
        # register -- and the rest of its cycle falls into order behind it.
        def break_cycle(pending)
          start = pending.keys.first
          held, source = pending.delete(start)
          load_value(source, SCRATCH[1])
          at = place(source)
          while at != start
            d, s = pending.delete(at)
            copy(d, s)
            at = place(s)
          end
          store_value(held, SCRATCH[1])
        end

        # One value to where another one lives. A source with a register
        # home is stored straight out of it; only a slot needs the load.
        def copy(dest, source) = store_value(dest, value_in(source, SCRATCH[0]))

        # How many instructions `materialize` spends on `n`.
        def materialized(n)
          n &= 0xFFFF_FFFF_FFFF_FFFF
          chunks = 4.times.map { |k| (n >> (16 * k)) & 0xFFFF }
          filler = chunks.count(0xFFFF) > chunks.count(0) ? 0xFFFF : 0
          [chunks.count { |c| c != filler }, 1].max
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
end
