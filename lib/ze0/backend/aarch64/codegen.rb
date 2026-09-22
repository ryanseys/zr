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
      # A value lives in the register `Regalloc` gives it, or in an 8-byte
      # slot of the frame when it gives none; a constant one instruction
      # makes or read once, a slot's address, and an address a constant
      # past a base are made where they are read and live nowhere. An
      # instruction reads a frame operand into x9..x12, computes in a
      # register, and stores a frame result from one. A compare read once
      # by a branch or a select leaves its answer in the flags. The frame
      # is `[x29, x30) [slots) [values) [saved callee registers)`, addressed
      # from sp with unsigned scaled offsets (x17 holds a page of it when
      # one does not fit): one pre-indexed `stp` makes the whole of a
      # frame of 496 bytes or less and one post-indexed `ldp` unmakes it,
      # and a larger frame keeps the x29 pair at its top with `sub sp`
      # below. x29 keeps the frame chain either way, x18 is never used,
      # and sp stays 16-byte aligned.
      #
      # Encodings come from `Backend::Aarch64`; relocations are recorded
      # here at the instruction's offset.
      class Codegen
        include Registers

        # The two registers `parallel_copy` carries values in. x11 and
        # x12 are named where an instruction needs more; x13 to x15 are
        # the allocator's, in `Regalloc::CALLER`.
        SCRATCH = [X9, X10].freeze
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
        # The branch that goes when the other does not.
        OPPOSITE = { cbz: :cbnz, cbnz: :cbz, tbz: :tbnz, tbnz: :tbz }.freeze
        # The opcodes whose lowering leaves NZCV alone, so a compare's
        # flags survive them on the way to the branch or select that reads
        # them. A compare, a select made with its own `cmp`, an overflow
        # check and a call all write the flags; a terminator ends the block.
        FLAG_NEUTRAL = (%i[iconst load store stack_addr symbol_value func_addr ireduce uextend sextend bitcast
                           fcvt_from_sint fcvt_to_sint_sat gates] +
                        IR::Inst::BINOPS + IR::Inst::BITOPS + IR::Inst::FBINOPS + IR::Inst::FUNOPS).to_set.freeze

        # The mnemonics the one-operand float instructions go by.
        FUNOPS = { fneg: :fneg, fabs: :fabs, sqrt: :fsqrt, floor: :frintm,
                   ceil: :frintp, trunc: :frintz, nearest: :frintn }.freeze
        # The d registers an f64 value stays in between the instruction
        # that makes or loads it and the ones in the same block that read
        # it: caller-saved, so a call empties them, and never saved.
        DOUBLES = [D16, D17, D18, D19, D20, D21, D22, D23].freeze
        # The register `popcnt` counts in: outside `DOUBLES`, so it
        # displaces nothing held there.
        COUNTER = D24

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
        # `allocate: false` leaves every value in its frame home, the
        # road the allocator's own answers are checked against: the two
        # must run alike, and the checks hold them to it.
        def initialize(function, defined: [], assembler: Assembler, far: false, allocate: true)
          @f = function
          @defined = defined.to_set
          @far = far
          @allocate = allocate
          @asm = assembler.new
          @relocs = []
          @reg = {}
          @home = {}
          @labels = {}
        end

        def compile
          assign_types
          count_uses
          plan_pinned
          plan_slots
          plan_constants
          plan_addresses
          plan_bytes
          plan_fusion
          plan_pairs
          @reg = @allocate ? Regalloc.of(@f, skip: @silent, via: @via) : {}
          assign_homes
          @f.blocks.each { |b| @labels[b.name] = @asm.make_label(b.name) }
          @epilogue = @asm.make_label("epilogue") if @returns > 1
          prologue
          @f.blocks.each_with_index do |b, n|
            @asm.put_label(@labels[b.name])
            @next = @f.blocks[n + 1]&.name
            forget_doubles
            b.insts.each { |i| emit(i) }
          end
          if @epilogue
            @asm.put_label(@epilogue)
            epilogue
          end
          Obj::Function.new(@f.name, @asm.to_binary, relocs: @relocs, linkage: :export)
        rescue Assembler::OutOfReach
          # A conditional branch that cannot reach its block: the whole
          # function again, every such branch the long way.
          raise if @far

          # This attempt's code and plans are as big as the function, and
          # nothing reads them again: let them go before the second is made.
          assembler = @asm.class
          @asm = @reg = @home = @labels = @relocs = @const = @remade = @silent = @derived = @via = @types = @epilogue = @pairs = @paired = nil
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

        # An `icmp` whose one use is a `brif` or a `select` in the same
        # block, with nothing that writes the flags between them, needs no
        # boolean at all: the compare sets the flags and the branch or the
        # select reads them.
        #
        # Without it the pair costs `cmp`, `cset`, a store of the byte, a
        # load of it back, a `uxtb` and a `cbz`. `Zr::Function#checked`
        # writes one after every call a compiled Ruby method makes, so this
        # is the shape most branches in the program have. The stack check
        # at the top of every Ruby function has a load between the two.
        #
        # A branch on one bit of a word (`brif (band x, 2^n) != 0`) is a
        # `tbz` or `tbnz` on the word itself: the `band` and the compare
        # emit nothing (`@silent`), and the branch reads the word, which
        # the allocator then keeps live to it (`@via`).
        def plan_fusion
          @fused = {}
          @bit_tests = {}
          @mask_tests = {}
          @f.blocks.each do |b|
            # What emits nothing where it stands does not part a compare
            # from its reader.
            insts = b.insts.reject { |i| @silent.include?(i.results[0]) }
            insts.each_with_index do |cmp, n|
              r = FLAG_SETTERS.include?(cmp.op) ? cmp.results[1] : cmp.results[0]
              next unless (cmp.op == :icmp || cmp.op == :fcmp || FLAG_SETTERS.include?(cmp.op)) && @uses[r] == 1

              reader = insts[(n + 1)..].find { |i| !FLAG_NEUTRAL.include?(i.op) }
              next unless reader && (reader.op == :brif || reader.op == :select) && reader.args[0] == r

              # Either way the boolean is never made, so it has no home.
              @silent << r
              if cmp.op == :icmp && reader.op == :brif && (test = bit_test(cmp))
                @bit_tests[reader] = test
                @silent << cmp.args.find { |a| @def_of[a]&.op == :band }
                @via[r] = test[0]
              else
                @fused[cmp] = reader
                next unless cmp.op == :icmp && (test = mask_test(cmp))

                # `tst` reads the word: the `band` is never made.
                @mask_tests[cmp] = test
                m = cmp.args.find { |a| @def_of[a]&.op == :band }
                @silent << m
                @via[m] = test[0]
              end
            end
          end
        end

        # The instructions whose second result is a flag they leave in
        # NZCV as well: an overflow check, whose branch reads `vs`
        # straight when nothing parts them (`emit_overflow`).
        FLAG_SETTERS = %i[sadd_overflow ssub_overflow smul_overflow].to_set.freeze

        # Two stores of words to the same base, the second eight bytes
        # past the first with nothing that emits between them, are one
        # `stp`: the nil fills after every send and in every prologue are
        # runs of these. `@pairs` maps the first to the second, and
        # `@paired` holds the seconds, which emit nothing of their own.
        def plan_pairs
          @pairs = {}
          @paired = Set.new
          @f.blocks.each do |b|
            b.insts.reject { |i| @silent.include?(i.results[0]) }.each_cons(2) do |first, second|
              next unless first.op == :store && second.op == :store && !@paired.include?(first)
              next unless first.args[1] == second.args[1] && second.offset == first.offset + 8
              next unless wide?(first.args[0]) && wide?(second.args[0])

              @pairs[first] = second
              @paired << second
            end
          end
        end

        # `[word, bit, branch]` when `cmp` asks whether one bit of a word
        # is set: it compares a `band` of the word and a power of two with
        # zero, and nothing else reads the `band`.
        def bit_test(cmp)
          return unless cmp.cond == "eq" || cmp.cond == "ne"

          m, z = cmp.args
          m, z = z, m if @const.key?(m)
          return unless constant(z, type_of(m)) == 0 && @uses[m] == 1 && @def_of[m]&.op == :band

          x, k = @def_of[m].args
          x, k = k, x if @const.key?(x)
          return if @const.key?(x)

          mask = constant(k, type_of(x))
          return unless mask&.positive? && (mask & (mask - 1)).zero?

          [x, mask.bit_length - 1, cmp.cond == "ne" ? :tbnz : :tbz]
        end

        # `[word, mask]` when `cmp` asks whether any of some bits of a
        # word are set: a `band` of the word and a bitmask immediate,
        # compared with zero, and nothing else reads the `band`. That is
        # one `tst`, where the `and` and `cmp` were two.
        def mask_test(cmp)
          return unless cmp.cond == "eq" || cmp.cond == "ne"

          m, z = cmp.args
          m, z = z, m if @const.key?(m)
          return unless constant(z, type_of(m)) == 0 && @uses[m] == 1 && @def_of[m]&.op == :band

          x, k = @def_of[m].args
          x, k = k, x if @const.key?(x)
          return if @const.key?(x)

          mask = constant(k, type_of(x))
          return unless mask && Assembler.bitmask(mask, wide?(x) ? 64 : 32)

          [x, mask]
        end

        # A `gates` value is the word as it was when read: an instruction
        # that reads it later reads that, whatever the register holds by
        # then. One whose every read is in its own block before anything
        # that can change the register -- a call, since a callee may set
        # a gate, or a set of the register itself -- is read out of the
        # register where it is read (`@pinned`): no register of its own,
        # no home, nothing emitted at its definition, and a bit test of
        # it is one `tbz` of `x28`. Any other is copied out of the
        # register at its definition, a value like any other.
        def plan_pinned
          @pinned = Set.new
          @f.blocks.each do |b|
            open = {}
            b.insts.each do |i|
              i.args.each { |a| open[a] += 1 if open.key?(a) }
              i.targets&.each { |(_, args)| args.each { |a| open[a] += 1 if open.key?(a) } }
              case i.op
              when :gates then open[i.results[0]] = 0
              when :call, :call_indirect, :gates_set, :gates_enter
                open.each { |v, n| @pinned << v if n == @uses[v] }
                open.clear
              end
            end
            open.each { |v, n| @pinned << v if n == @uses[v] }
          end
        end

        # How many times each value is read: by an instruction, or by a
        # jump that carries it to a block. What is read once or never is
        # planned differently from what is read again and again.
        def count_uses
          @uses = Hash.new(0)
          @def_of = {}
          @returns = 0
          # Whether this function is entered from foreign code, which
          # loads the gate register and gives it back as it was.
          @enters = false
          @f.blocks.each do |b|
            b.insts.each do |i|
              @def_of[i.results[0]] = i if i.results[0]
              @returns += 1 if i.op == :return
              @enters = true if i.op == :gates_enter
              i.args.each { |a| @uses[a] += 1 if Regalloc.value?(a) }
              i.targets&.each { |(_, args)| args.each { |a| @uses[a] += 1 if Regalloc.value?(a) } }
            end
          end
        end

        # Where each slot sits above sp. Slots come first in the frame,
        # past the x29 pair, so this is known before any value has a home.
        #
        # A slot's address is made where it is read, as a small constant
        # is (`@stack`): `IR::Function#hoisted` puts every `stack_addr` in
        # the entry block, so each one held a register for the whole
        # function, and the frame saved and restored that register. A load
        # or a store through it addresses sp directly and makes nothing.
        def plan_slots
          off = PAIR
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
        # A constant is made again at every read and nowhere else
        # (`@remade`) when one instruction makes it, or when it is read at
        # most once: no register, no slot, and nothing at its definition. A
        # read that takes it as an immediate makes nothing at all, and one
        # that does not pays the `movz` where it paid an `ldr`. A constant
        # read once costs the same made at its read as made once, and a
        # constant read nowhere then costs nothing: the line words
        # `Zr::Function` stores before every send are read once each, and
        # `IR::Function#hoisted` put every one in the entry block, where
        # each held a register for the whole function. What is read again
        # and again and takes several instructions is still made once.
        #
        # A symbol's address read once (`adrp` and `add`, or a GOT load)
        # is made at its read the same way: `IR::Function#hoisted` puts
        # every one in the entry block, where made once it held a
        # callee-saved register for the whole function, which the
        # prologue saves and the epilogue restores at every call. One
        # read more than once keeps its register: a send reads its
        # site's cell five times on the way to the call, and made at
        # each read the address cost `fib` 6%.
        def plan_constants
          @const = {}
          @symbol = {}
          @remade = Set.new(@stack.keys)
          @f.blocks.each do |b|
            b.insts.each do |i|
              v = i.results[0]
              case i.op
              when :iconst
                @const[v] = i.args[0]
                type = type_of(v)
                next unless WIDTH_MASK.key?(type)

                @remade << v if @uses[v] <= 1 || materialized(i.args[0] & WIDTH_MASK[type]) == 1
              when :symbol_value
                g = global_of(i.args[0])
                @symbol[v] = [g.symbol, g.colocated]
                @remade << v if @uses[v] <= 1
              end
            end
          end
        end

        # An address a constant past a base folds into the loads and stores
        # that read through it: `ldr x, [base, #k + off]` where the `iadd`
        # made a register hold `base + k` first. The `iadd` is then emitted
        # nowhere (`@silent`), and its base is what the allocator keeps
        # live at each read (`@via`). A chain of such additions folds to
        # its first base with the constants summed.
        #
        # Only an addition every use reads through folds, and only when
        # every read's offset fits the scaled immediate: one that is also
        # read as a value, or reaches past the immediate somewhere, is
        # made as before and its reads go through it. The record slots
        # `Zr::Function` stages a send's arguments in are addressed this
        # way at every send, and a struct field a kernel def reads is
        # `iadd` of the pointer and the field's offset.
        def plan_addresses
          @derived = {}
          @via = {}
          @silent = @remade | @pinned
          memory = Hash.new { |h, k| h[k] = [] }
          # `[value, base, root, k]` a sum: its own base, and the first
          # base of its chain with the constants added up.
          sums = []
          chain = {}
          @f.blocks.each do |b|
            b.insts.each do |i|
              case i.op
              when :load then memory[i.args[0]] << [i.offset, WIDTHS.fetch(i.type)]
              when :store then memory[i.args[1]] << [i.offset, WIDTHS.fetch(type_of(i.args[0]))]
              when :iadd
                base, k = summed(i)
                next unless base

                root, j = chain[base]
                root ? k += j : root = base
                chain[i.results[0]] = [root, k]
                sums << [i.results[0], base, root, k]
              end
            end
          end
          # The reads an addition is not folded into still hold it as a
          # value; a later addition folded away lets go of its base, so
          # the outer additions of a chain are decided first.
          other = @uses.dup
          memory.each { |v, reads| other[v] -= reads.size }
          @from_sp = {}
          sums.reverse_each do |v, base, root, k|
            if other[v].zero? && memory[v].all? { |off, width| reaches?(root, k + off, width) }
              @derived[v] = [root, k]
              @via[v] = root
              @silent << v
              other[base] -= 1
            elsif (at = @stack[root])
              # Read as a value, but a slot's address and a constant: one
              # `add` from sp, which reads none of the chain. The argument
              # vector `Zr::Function` passes a send is one of these.
              @from_sp[v] = at + k
              other[base] -= 1
            end
          end
        end

        # `[base, k]` for an `iadd` of a value and a constant, taken as
        # signed; nil for any other addition.
        def summed(i)
          return nil unless type_of(i.results[0]) == "i64"

          a, b = i.args
          a, b = b, a if constant(a, "i64") && !constant(b, "i64")
          k = constant(b, "i64")
          return nil if k.nil? || constant(a, "i64") || !Regalloc.value?(a)

          [a, k >= 1 << 63 ? k - (1 << 64) : k]
        end

        # Whether `off` past `root` is an offset one load or store of
        # `width` bytes can name: from sp when `root` is a slot's address,
        # from the register that holds `root` otherwise.
        def reaches?(root, off, width)
          at = @stack[root]
          off += at if at
          immediate?(off, width)
        end

        def immediate?(off, width) = off >= 0 && (off % width).zero? && off / width <= 4095

        # The bytes a load or store of each type moves.
        WIDTHS = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze

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
              next if @reg.key?(v) || @silent.include?(v)

              @home[v] = off
              off += 8
            end
          end
          # A callee-saved register this function uses has to come back to
          # its caller as it was, so the frame keeps a place for each.
          @saved_at = {}
          saved = @reg.values.uniq.select { |r| Regalloc.callee?(r) }
          saved << Regalloc::GATES if @enters
          saved.sort_by(&:to_i).each do |r|
            @saved_at[r] = off
            off += 8
          end
          @frame = align(off, 16)
        end

        def align(n, a)
          (n + a - 1) & ~(a - 1)
        end

        # The bytes the x29 pair takes at the bottom of the frame.
        PAIR = 16
        # The largest frame one pre-indexed `stp` makes and one
        # post-indexed `ldp` unmakes: seven signed bits of eights reach
        # 504, and a frame is a multiple of 16.
        SMALL = 496

        def small_frame? = @frame <= SMALL

        def sig_of(fn) = @types.sig_of(fn)
        def sig_named(sig) = @types.sig_named(sig)
        def callee_of(fn) = @types.callee_named(fn)
        def global_of(gv) = @types.global_named(gv)
        def block_named(name) = @types.block_named(name)

        # --- frame access -------------------------------------------------

        # `[base, offset]` for `off` from sp, the offset small enough for a
        # scaled immediate of `width` bytes; x17 holds a page base when not.
        #
        # x17 and not a scratch register: a store to a far offset comes
        # here from inside an instruction whose scratch registers are
        # already carrying its operands (`parallel_copy` holds a broken
        # cycle's value in x10 across several stores), so a page base in
        # one of them would destroy what was about to be stored. x16 and
        # x17 are the linker's veneer registers, dead across every call
        # and named nowhere else in the backend.
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
          return @asm.mov(reg, Regalloc::GATES) if @pinned.include?(v)

          home = @reg[v]
          return narrow(reg, home, @clean.include?(v) ? "i64" : type_of(v)) if home
          return frame_address(reg, @stack[v]) if @stack.key?(v)
          return symbol_address(reg, *@symbol[v]) if @symbol.key?(v) && @remade.include?(v)
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
          return Regalloc::GATES if @pinned.include?(v)

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
          when "i64", "f64" then @asm.mov reg, home unless reg.equal?(home)
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

        # A small frame is made by one `stp` that also moves sp; a large
        # one keeps the pair where `stp` alone puts it, above the whole
        # frame, and moves sp the frame below, so the pair's own `PAIR`
        # bytes at the bottom go unused.
        def prologue
          if small_frame?
            @asm.stp X29, X30, [SP, -@frame], :!
          else
            @asm.stp X29, X30, [SP, -PAIR], :!
          end
          @asm.mov X29, SP
          sub_sp(@frame) unless small_frame?
          saved_registers(:stp, :str)
          entry = @f.blocks.first
          # Eight is where the registers run out and the ABI starts pushing
          # arguments onto the stack. Nothing reaches it: every lowering
          # keeps a signature to eight, and the whole runtime -- 4732
          # functions -- sits at eight parameters and eight call arguments
          # and never above. So this refuses rather than growing a stack
          # argument path no program would take.
          raise Refused, "#{@f.name}: more than eight parameters" if entry.params.size > IR::REGISTER_ARGS

          ints, floats = entry.params.partition { |_, t| t != "f64" }.map { |list| list.map(&:first) }
          # The integer parameters arrive in x0.. and a home may be one
          # of those registers, so they move as one parallel copy. The
          # floats move after them: a float's home may be an argument
          # register too, one an integer had yet to leave.
          move_registers(ints.map { |v| [place(v), v] }, ints.each_index.map { |n| Registers.x(n) })
          floats.each_with_index do |v, n|
            @asm.fmov X9, Registers.d(n)
            store_param(v, X9)
          end
        end

        # Parallel moves between registers and values: each `[to, v]` of
        # `dests` takes the source at the same index of `srcs`, where a
        # source is a value or a register, and `to` is a register or the
        # value whose place takes it. No destination is written while a
        # pending copy still reads it; a cycle is broken through
        # `SCRATCH[1]`.
        def move_registers(dests, srcs)
          pending = {}
          reads = Hash.new(0)
          dests.each_with_index do |(to, v), n|
            src = srcs[n]
            from = src.is_a?(Register) ? src : place(src)
            next if to == from && (v.nil? || src.is_a?(Register) || type_of(v) == type_of(src))

            pending[to] = [v, src]
            reads[from] += 1
          end
          ready = pending.keys.reject { |p| reads[p].positive? }
          loop do
            while (p = ready.pop)
              v, src = pending.delete(p)
              move_register(p, v, src)
              from = src.is_a?(Register) ? src : place(src)
              reads[from] -= 1
              ready << from if reads[from].zero? && pending.key?(from)
            end
            break if pending.empty?

            start = pending.keys.first
            v, src = pending.delete(start)
            src.is_a?(Register) ? @asm.mov(SCRATCH[1], src) : load_value(src, SCRATCH[1])
            at = src.is_a?(Register) ? src : place(src)
            while at != start && pending.key?(at)
              d, s = pending.delete(at)
              move_register(at, d, s)
              at = s.is_a?(Register) ? s : place(s)
            end
            v.nil? ? @asm.mov(start, SCRATCH[1]) : store_value(v, SCRATCH[1])
          end
        end

        # One move of `move_registers`: into the register `to`, or into
        # the home of the value `v`.
        def move_register(to, v, src)
          if v.nil?
            src.is_a?(Register) ? @asm.mov(to, src) : load_value(src, to)
          elsif src.is_a?(Register)
            store_param(v, src)
          else
            store_value(v, value_in(src, SCRATCH[0]))
          end
        end

        # Two immediates reach 16 MiB less one page; a frame past that is
        # refused by name rather than cut short.
        def sub_sp(n)
          raise Refused, "#{@f.name} needs a frame of #{n} bytes, past the 16 MiB sub sp reaches" if n >= 1 << 24

          @asm.sub SP, SP, n >> 12, lsl: 12 if n >= 4096
          @asm.sub SP, SP, n & 0xFFF if (n & 0xFFF) != 0
        end

        # The saved registers to or from their places, two at a time
        # where the pair form reaches (its offset is seven signed bits of
        # eights), one at a time past that.
        def saved_registers(pair, single)
          @saved_at.each_slice(2) do |(r1, off), (r2, _)|
            if r2 && off <= 504
              @asm.public_send(pair, r1, r2, [SP, off])
            else
              base, at = address(off, 8)
              @asm.public_send(single, r1, [base, at])
              @asm.public_send(single, r2, [base, at + 8]) if r2
            end
          end
        end

        # A function with one return has its epilogue there; one with
        # more shares a single epilogue every return branches to, and the
        # last of them, ending the last block, falls into it.
        def emit_return(i)
          unless i.args.empty?
            if (d = @doubles[i.args[0]])
              @asm.fmov D0, d
            else
              load_value(i.args[0], X0)
              @asm.fmov D0, X0 if float?(i.args[0])
            end
          end
          return epilogue unless @epilogue

          @asm.b @epilogue unless @next.nil?
        end

        def epilogue
          saved_registers(:ldp, :ldr)
          if small_frame?
            @asm.ldp X29, X30, [SP], @frame
          else
            @asm.mov SP, X29
            @asm.ldp X29, X30, [SP], PAIR
          end
          @asm.ret
        end

        # --- instructions -------------------------------------------------

        # A float instruction's result waits in its d register until the
        # instruction is out, then goes to its home too.
        def emit(i)
          lower(i)
          return unless @pending_double

          v, d = @pending_double
          @pending_double = nil
          @asm.fmov X11, d
          store_value(v, X11)
          remember_double(v, d)
        end

        def lower(i)
          case i.op
          when :iconst
            return if @remade.include?(i.results[0])

            d = result_in(i.results[0], X9)
            materialize(d, i.args[0])
            store_value(i.results[0], d)
          when :load then emit_load(i)
          when :store
            return if @paired.include?(i)

            emit_store(i)
          when :stack_addr
            return if @remade.include?(i.results[0])

            frame_address(X9, @slot_at[Integer(i.args[0].delete_prefix("ss"))])
            store_value(i.results[0], X9)
          when :symbol_value
            return if @remade.include?(i.results[0])

            emit_symbol(i.results[0], global_of(i.args[0]).symbol, global_of(i.args[0]).colocated)
          when :gates
            return if @pinned.include?(i.results[0])

            d = result_in(i.results[0], X9)
            @asm.mov d, Regalloc::GATES
            store_value(i.results[0], d)
          when :gates_set, :gates_enter then @asm.mov Regalloc::GATES, value_in(i.args[0], X9)
          when :func_addr
            c = callee_of(i.args[0])
            emit_symbol(i.results[0], c.symbol, @defined.include?(c.symbol))
          when :call
            emit_call(i)
            forget_doubles
          when :call_indirect
            emit_call_indirect(i)
            forget_doubles
          when :icmp, :fcmp
            # The branch or select that follows reads the flags; there is
            # no boolean. A bit test reads the word instead: nothing here.
            if (reader = @fused[i])
              @fused[reader] = i.op == :icmp ? emit_compare(i) : emit_fcompare(i)
              return
            end
            return if @silent.include?(i.results[0])

            cond = i.op == :icmp ? emit_compare(i) : emit_fcompare(i)
            d = result_in(i.results[0], X11)
            @asm.cset d, cond
            store_value(i.results[0], d)
          when :iadd, :isub, :imul, :udiv, :sdiv, :band, :bor, :bxor, :ishl, :ushr, :sshr
            return if @silent.include?(i.results[0])

            if (at = @from_sp[i.results[0]])
              d = result_in(i.results[0], X11)
              frame_address(d, at)
              store_value(i.results[0], d)
              return
            end
            emit_binop(i)
          when :urem, :srem then emit_rem(i)
          when :ctz, :clz, :bswap then emit_bitop(i)
          when :popcnt then emit_popcnt(i)
          when :ireduce, :uextend
            # A narrower value reads the low bits of its slot; a wider one
            # needs the high bits clear, which the narrow load gives.
            load_value(i.args[0], X9)
            store_value(i.results[0], X9)
          when :sextend
            a = value_in(i.args[0], X9)
            type_of(i.args[0]) == "i8" ? @asm.sxtb(X9, w(a)) : @asm.sxtw(X9, w(a))
            store_value(i.results[0], X9)
          when :select then emit_select(i)
          when :sadd_overflow, :ssub_overflow then emit_overflow(i)
          when :smul_overflow then emit_mul_overflow(i)
          when *IR::Inst::FBINOPS
            a = double_in(i.args[0])
            b = double_in(i.args[1])
            @asm.public_send(i.op, double_out(i.results[0]), a, b)
          when *IR::Inst::FUNOPS
            a = double_in(i.args[0])
            @asm.public_send(FUNOPS.fetch(i.op), double_out(i.results[0]), a)
          when :fcvt_from_sint
            a = value_in(i.args[0], X9)
            @asm.scvtf double_out(i.results[0]), wide?(i.args[0]) ? a : Registers.w(a.to_i)
          when :fcvt_to_sint_sat
            @asm.fcvtzs X11, double_in(i.args[0])
            store_value(i.results[0], X11)
          when :bitcast
            # The same bits under another type: the d register that holds
            # them holds the result as well.
            load_value(i.args[0], X9)
            store_value(i.results[0], X9)
            remember_double(i.results[0], @doubles[i.args[0]]) if @doubles.key?(i.args[0])
          when :brif then emit_brif(i)
          when :jump then emit_jump(i)
          when :return then emit_return(i)
          else raise Refused, "#{@f.name}: no lowering for #{i.op}"
          end
        end

        # A branch to one of two blocks. A fused compare left the answer
        # in the flags; a bit test reads the word itself; else the branch
        # is on the boolean. The block that follows needs no branch:
        # control falls into it.
        def emit_brif(i)
          yes, no = i.targets.map(&:first)
          if (x, bit, op = @bit_tests[i])
            reg = value_in(x, X9)
            reg = w(reg) if bit < 32
            yes == @next ? branch_if(OPPOSITE.fetch(op), no, reg, bit) : branch_if(op, yes, reg, bit)
          elsif (cond = @fused[i])
            yes == @next ? branch_on(INVERSE.fetch(cond), no) : branch_on(cond, yes)
          else
            reg = reg_for(i.args[0], value_in(i.args[0], X9))
            yes == @next ? branch_if(:cbz, no, reg) : branch_if(:cbnz, yes, reg)
          end
          @asm.b @labels.fetch(no) unless yes == @next || no == @next
        end

        # `cbz`, `cbnz`, `tbz` or `tbnz` of `operands` to a block. A far
        # one branches the other way over a `b`, which reaches 128
        # megabytes to the megabyte of its own.
        def branch_if(op, target, *operands)
          return @asm.public_send(op, *operands, @labels.fetch(target)) unless @far

          @asm.public_send(OPPOSITE.fetch(op), *operands, 2)
          @asm.b @labels.fetch(target)
        end

        # `csel` on the flags a fused compare left, else on its own `cmp`
        # of the boolean. A constant zero operand is the zero register.
        def emit_select(i)
          c, a, b = i.args
          d = result_in(i.results[0], X12)
          cond = @fused[i]
          unless cond
            @asm.cmp reg_for(c, value_in(c, X9)), 0
            cond = :ne
          end
          @asm.csel reg_for(a, d), value_or_zero(a, X10), value_or_zero(b, X11), cond
          store_value(i.results[0], d)
        end

        # An operand's register, or the zero register when it is the
        # constant zero.
        def value_or_zero(v, scratch)
          return reg_for(v, scratch).zr if constant(v, type_of(v)) == 0

          reg_for(v, value_in(v, scratch))
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

        # The largest offset a pair reaches: seven signed bits of eights.
        PAIR_REACH = 504

        def emit_store(i)
          return emit_store_pair(i, @pairs[i]) if @pairs.key?(i)

          v = value_in(i.args[0], X9)
          case type_of(i.args[0])
          when "i64", "f64" then @asm.str v, through(i.args[1], X10, i.offset, 8)
          when "i32" then @asm.str w(v), through(i.args[1], X10, i.offset, 4)
          when "i8" then @asm.strb w(v), through(i.args[1], X10, i.offset, 1)
          end
        end

        # Two stores as one `stp` where the pair form reaches, and as two
        # `str` through one address where it does not.
        def emit_store_pair(first, second)
          a = value_in(first.args[0], X9)
          # One value, or one number, stored twice is read into one
          # register: most pairs are two nils.
          same = first.args[0] == second.args[0] ||
                 (constant(first.args[0], "i64") && constant(first.args[0], "i64") == constant(second.args[0], "i64"))
          b = same ? a : value_in(second.args[0], X12)
          base, off = through(first.args[1], X10, first.offset, 8)
          if off <= PAIR_REACH
            @asm.stp a, b, [base, off]
          else
            @asm.str a, [base, off]
            # sp is no base for `reach`: the register-form `add` reads
            # register 31 as xzr. `address` pages sp through x17.
            @asm.str b, base.equal?(SP) ? address(off + 8, 8) : reach(base, off + 8, 8)
          end
        end

        # The memory operand for `off` past the address `base` holds: sp
        # itself when `base` is a slot's address and the sum fits, else the
        # address in a register, read into `scratch` when it has none. A
        # base folded away (`@derived`) is its root and a constant more,
        # and one made as a value from sp (`@from_sp`) is read from sp
        # the same: the argument vector a send passes is read through
        # by the direct call's loads of the arguments.
        def through(base, scratch, off, width)
          root, k = @derived[base]
          if root
            base = root
            off += k
          end
          at = @stack[base] || @from_sp[base]
          return [SP, at + off] if at && immediate?(at + off, width)

          reach(value_in(base, scratch), off, width)
        end

        # A base and an offset one load or store can hold: the offset
        # scaled into twelve bits, else the whole address built in X11
        # first, which neither emitter above uses.
        def reach(base, off, width)
          return [base, off] if immediate?(off, width)

          materialize(X11, off)
          @asm.add X11, base, X11
          [X11, 0]
        end

        # A symbol's address: page plus offset for one this link defines,
        # through the GOT for an import.
        def emit_symbol(result, symbol, local)
          symbol_address(X9, symbol, local)
          store_value(result, X9)
        end

        # `reg = &symbol`: the page and the offset in it for a symbol of
        # this link, and the GOT's word for one of another.
        def symbol_address(reg, symbol, local)
          if local
            reloc(:page21, symbol)
            @asm.adrp reg, 0
            reloc(:pageoff12, symbol)
            @asm.add reg, reg, 0
          else
            reloc(:got_page21, symbol)
            @asm.adrp reg, 0
            reloc(:got_pageoff12, symbol)
            @asm.ldr reg, [reg, 0]
          end
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
        # its own order, as the ABI says. The floats go first, read out
        # of whatever register holds them; the integers move as one
        # parallel copy, since an argument may live in the register
        # another one wants.
        def load_args(args)
          ints = []
          floats = 0
          args.each do |v|
            if float?(v)
              if (d = @doubles[v])
                @asm.fmov Registers.d(floats), d
              else
                load_value(v, X9)
                @asm.fmov Registers.d(floats), X9
              end
              floats += 1
            else
              ints << v
            end
          end
          move_registers(ints.each_index.map { |n| [Registers.x(n), nil] }, ints)
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

        # The pointer goes to x16 before the arguments are in place: it
        # may live in a register an argument wants, and no argument load
        # touches x16.
        def emit_call_indirect(i)
          sig = sig_named(i.callee)
          ptr, *args = i.args
          raise Refused, "#{@f.name}: a call with more than eight arguments" if args.size > IR::REGISTER_ARGS

          load_value(ptr, X16)
          load_args(args)
          @asm.blr X16
          return if i.results.empty?

          store_result(i.results[0], sig.ret)
        end

        # `fcmp`, and the condition to read its flags by.
        def emit_fcompare(i)
          a = double_in(i.args[0])
          b = double_in(i.args[1])
          @asm.fcmp a, b
          FCONDS.fetch(i.cond)
        end

        # --- doubles ------------------------------------------------------

        # An f64 value lives in its home as bits; on its way through a
        # float instruction it passes through a d register, and stays
        # there for the rest of its block (`@doubles`) so the next float
        # instruction reading it moves nothing. The registers go round in
        # turn, and a value whose register comes round again is simply
        # read from its home next time.

        # The d register holding `v`, moved there from its home when it
        # is in none.
        def double_in(v)
          @doubles[v] || begin
            d = next_double
            @asm.fmov d, value_in(v, X9)
            remember_double(v, d)
          end
        end

        # The d register a float instruction writes `v` into. `emit`
        # stores it to `v`'s home once the instruction is out.
        def double_out(v)
          d = next_double
          @pending_double = [v, d]
          d
        end

        def next_double
          d = DOUBLES[@double_turn]
          @double_turn = (@double_turn + 1) % DOUBLES.size
          @doubles.delete_if { |_, held| held.equal?(d) }
          d
        end

        def remember_double(v, d)
          @doubles[v] = d
        end

        def forget_doubles
          @doubles = {}
          @double_turn = 0
        end

        # `cmp`, and the arm64 condition to read its flags by. A constant
        # of twelve bits is the immediate form and takes no register: the
        # check `Zr::Function#checked` makes after every call is `cmp x, #52`.
        # A constant on the left goes to the right, and the condition turns
        # round with it.
        def emit_compare(i)
          if (x, mask = @mask_tests[i])
            @asm.tst reg_for(x, value_in(x, X9)), mask
            return CONDS.fetch(i.cond)
          end

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

        # `clz` is its own instruction, `ctz` the bits reversed and then
        # `clz`, `bswap` is `rev`.
        def emit_bitop(i)
          dest = result_in(i.results[0], X11)
          d, a = [dest, value_in(i.args[0], X9)].map { |x| reg_for(i.args[0], x) }
          case i.op
          when :clz then @asm.clz d, a
          when :bswap then @asm.rev d, a
          when :ctz
            @asm.rbit d, a
            @asm.clz d, d
          end
          store_value(i.results[0], dest)
        end

        # The set bits, counted a byte at a time in a d register: the
        # word moved in (`fmov s, w` for an i32, which clears the rest),
        # each byte's count (`cnt`), their sum in the low byte (`addv`),
        # and the register read back whole.
        def emit_popcnt(i)
          @asm.fmov COUNTER, reg_for(i.args[0], value_in(i.args[0], X9))
          @asm.cnt COUNTER, COUNTER
          @asm.addv COUNTER, COUNTER
          d = result_in(i.results[0], X11)
          @asm.fmov d, COUNTER
          store_value(i.results[0], d)
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
          d, a, b = [dest, value_in(i.args[0], X9), value_in(i.args[1], X10)].map { |x| reg_for(i.args[0], x) }
          i.op == :sadd_overflow ? @asm.adds(d, a, b) : @asm.subs(d, a, b)
          store_value(i.results[0], dest)
          # The branch or select that follows reads the flags.
          if (reader = @fused[i])
            @fused[reader] = :vs
            return
          end
          flag = result_in(i.results[1], X12)
          @asm.cset flag, :vs
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
          store_value(i.results[0], X11)
          if (reader = @fused[i])
            @fused[reader] = :ne
            return
          end
          @asm.cset X12, :ne
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
        def place(v) = @reg[v] || @home.fetch(v) { @remade.include?(v) ? v : @pinned.include?(v) ? Regalloc::GATES : raise(KeyError, v) }

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
