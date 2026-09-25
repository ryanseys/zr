# frozen_string_literal: true


require_relative "../../backend"
require_relative "registers"
require_relative "assembler"
require_relative "../../ir/function"
require_relative "../../ir/types"
require_relative "regalloc"
require_relative "../../obj/model"
require_relative "../../bytes"

module Zr
  module Backend
    module Aarch64
      # Compiles an `IR::Function` to an `Obj::Function` of Apple arm64
      # machine code, with a relocation for each symbol that it refers to.
      #
      # A value is in the register that `Regalloc` gives it, or else in an
      # 8-byte frame slot. These are made at each read and have no home: a
      # constant that one instruction makes or that is read once, a slot's
      # address, and a base plus a constant. An instruction loads frame
      # operands into x9..x12, computes in a register, and stores a frame
      # result from a register. A compare that one branch or select reads
      # leaves its result in the flags.
      #
      # The frame is `[x29, x30) [slots) [values) [saved callee registers)`,
      # addressed from sp with unsigned scaled offsets (x17 contains a page
      # base when an offset does not fit). A frame of 496 bytes or less uses
      # one pre-indexed `stp` and one post-indexed `ldp`. A larger frame keeps
      # the x29 pair at its top and uses `sub sp` below it. x29 keeps the
      # frame chain, x18 is never used, and sp stays 16-byte aligned.
      #
      # Encodings come from `Backend::Aarch64`. This class records each
      # relocation at the instruction's offset.
      class Codegen
        include Registers

        # The two registers that `parallel_copy` moves values through. An
        # instruction that needs more uses x11 and x12. x13 to x15 belong to
        # the allocator, in `Regalloc::CALLER`.
        SCRATCH = [X9, X10].freeze
        # Maps IR condition codes to arm64 condition codes.
        CONDS = {
          "eq" => :eq, "ne" => :ne, "slt" => :lt, "sle" => :le, "sgt" => :gt, "sge" => :ge,
          "ult" => :lo, "ule" => :ls, "ugt" => :hi, "uge" => :hs
        }.freeze
        # Float comparisons after fcmp: NaN on either side sets C and V and
        # clears N and Z. Every condition except `ne` then reads as false.
        FCONDS = { "eq" => :eq, "ne" => :ne, "lt" => :mi, "le" => :ls, "gt" => :gt, "ge" => :ge }.freeze
        # The condition that is true for `b op a` when the IR gives `a op b`.
        SWAPPED = {
          "eq" => "eq", "ne" => "ne", "slt" => "sgt", "sle" => "sge", "sgt" => "slt", "sge" => "sle",
          "ult" => "ugt", "ule" => "uge", "ugt" => "ult", "uge" => "ule"
        }.freeze
        # The bits that an operand of each type gives to an instruction:
        # the width that its load gives it.
        WIDTH_MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
        # The condition that is true only when the other is false. arm64
        # numbers them in pairs, so this is the code with its low bit
        # inverted, written out so that it is easy to read.
        INVERSE = {
          eq: :ne, ne: :eq, lt: :ge, ge: :lt, le: :gt, gt: :le,
          lo: :hs, hs: :lo, ls: :hi, hi: :ls, mi: :pl, pl: :mi, vs: :vc, vc: :vs
        }.freeze
        # The branch that is taken when the other is not taken.
        OPPOSITE = { cbz: :cbnz, cbnz: :cbz, tbz: :tbnz, tbnz: :tbz }.freeze
        # The opcodes whose lowering does not change NZCV. A compare's flags
        # stay valid across them until the branch or select that reads the
        # flags. A compare, a select with its own `cmp`, an overflow check and
        # a call all write the flags. A terminator ends the block.
        FLAG_NEUTRAL = (%i[iconst load store stack_addr symbol_value func_addr ireduce uextend sextend bitcast
                           fcvt_from_sint fcvt_to_sint_sat gates] +
                        IR::Inst::BINOPS + IR::Inst::BITOPS + IR::Inst::FBINOPS + IR::Inst::FUNOPS).to_set.freeze

        # The mnemonics of the one-operand float instructions.
        FUNOPS = { fneg: :fneg, fabs: :fabs, sqrt: :fsqrt, floor: :frintm,
                   ceil: :frintp, trunc: :frintz, nearest: :frintn }.freeze
        # The d registers that keep an f64 value from the instruction that
        # makes or loads it to its reads in the same block. They are
        # caller-saved, so a call clears them, and they are never saved.
        DOUBLES = [D16, D17, D18, D19, D20, D21, D22, D23].freeze
        # The register that `popcnt` counts in. It is not in `DOUBLES`, so
        # it does not replace a value there.
        COUNTER = D24

        class Refused < Backend::Refused; end

        # The assembler that the compile used. A caller that gave its own
        # assembler reads the listing from it.
        attr_reader :asm

        # `defined`: every symbol that this unit defines. It sets whether a
        # symbol is reached directly or through the GOT. It is a Set, because
        # a unit has thousands of symbols and each function checks it once per
        # symbol. `to_set` on a Set returns the same Set, so it costs nothing.
        # `far`: every conditional branch can reach past the 1 MB range of a
        # conditional branch. Only a function that large pays for it.
        # `allocate: false` keeps every value in its frame home. This is the
        # reference for the allocator: both modes must give the same result,
        # and the tests check it.
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
          # A conditional branch cannot reach its block. Compile the
          # function again, with every such branch in the far form.
          raise if @far

          # The code and plans of this attempt are as large as the function,
          # and nothing reads them again. Release them before the second attempt.
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

        # An `icmp` whose only use is a `brif` or a `select` in the same block,
        # with no flag write between them, needs no boolean. The compare sets
        # the flags and the branch or select reads them.
        #
        # Without this, the pair costs `cmp`, `cset`, a byte store, a byte
        # load, a `uxtb` and a `cbz`. `Zr::Lower::Function#checked` writes this
        # pair after every call in a compiled Ruby method, so most branches in
        # the program have this shape. The stack check at the start of every
        # Ruby function has a load between the two.
        #
        # A branch on one bit of a word (`brif (band x, 2^n) != 0`) is a `tbz`
        # or `tbnz` on the word. The `band` and the compare emit nothing
        # (`@silent`), and the allocator keeps the word live to the branch (`@via`).
        def plan_fusion
          @fused = {}
          @bit_tests = {}
          @mask_tests = {}
          @f.blocks.each do |b|
            # An instruction that emits nothing does not separate a compare
            # from its reader.
            insts = b.insts.reject { |i| @silent.include?(i.results[0]) }
            insts.each_with_index do |cmp, n|
              r = FLAG_SETTERS.include?(cmp.op) ? cmp.results[1] : cmp.results[0]
              next unless (cmp.op == :icmp || cmp.op == :fcmp || FLAG_SETTERS.include?(cmp.op)) && @uses[r] == 1

              reader = insts[(n + 1)..].find { |i| !FLAG_NEUTRAL.include?(i.op) }
              next unless reader && (reader.op == :brif || reader.op == :select) && reader.args[0] == r

              # In both cases the boolean is never made, so it has no home.
              @silent << r
              if cmp.op == :icmp && reader.op == :brif && (test = bit_test(cmp))
                @bit_tests[reader] = test
                @silent << cmp.args.find { |a| @def_of[a]&.op == :band }
                @via[r] = test[0]
              else
                @fused[cmp] = reader
                next unless cmp.op == :icmp && (test = mask_test(cmp))

                # `tst` reads the word, so the `band` is never made.
                @mask_tests[cmp] = test
                m = cmp.args.find { |a| @def_of[a]&.op == :band }
                @silent << m
                @via[m] = test[0]
              end
            end
          end
        end

        # The instructions whose second result is a flag that they also set
        # in NZCV: the overflow checks. Their branch reads `vs` directly when
        # nothing is between them (`emit_overflow`).
        FLAG_SETTERS = %i[sadd_overflow ssub_overflow smul_overflow].to_set.freeze

        # Two word stores to the same base, the second 8 bytes after the
        # first, with no emitted instruction between them, become one `stp`.
        # The nil fills after every send and in every prologue are runs of
        # these. `@pairs` maps the first store to the second. `@paired`
        # contains the second stores, which emit nothing.
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

        # Returns `[word, bit, branch]` when `cmp` tests one bit of a word:
        # it compares a `band` of the word and a power of two with zero, and
        # nothing else reads the `band`.
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

        # Returns `[word, mask]` when `cmp` tests whether any of some bits of
        # a word are set: a `band` of the word and a bitmask immediate,
        # compared with zero, and nothing else reads the `band`. This is one
        # `tst` in place of an `and` and a `cmp`.
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

        # A `gates` value is the gate word at the time of the read. A later
        # instruction that uses the value must see that word, not the current
        # contents of the register. When every read is in the defining block
        # and before anything that can change the register (a call, because a
        # callee can set a gate, or a write to the register), each read uses
        # `x28` directly (`@pinned`). It then has no register, no home, and no
        # code at its definition, and a bit test of it is one `tbz` of `x28`.
        # Any other `gates` value is copied from the register at its definition.
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

        # Counts the reads of each value, by an instruction or by a jump
        # that gives it to a block. A value read once or never gets a
        # different plan from a value read many times.
        def count_uses
          @uses = Hash.new(0)
          @def_of = {}
          @returns = 0
          # Whether foreign code calls this function. Such a function loads
          # the gate register and restores it before it returns.
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

        # The offset of each slot above sp. Slots come first in the frame,
        # after the x29 pair, so the offsets are known before any value has a home.
        #
        # A slot's address is made at each read, as for a small constant
        # (`@stack`). `IR::Function#hoisted` puts every `stack_addr` in the
        # entry block, so otherwise each one uses a register for the whole
        # function, and the frame saves and restores it. A load or store
        # through a slot address uses sp directly and makes nothing.
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

        # Maps every `iconst` to its value. A value is defined once, so its
        # number is known at each use, and an instruction with an immediate
        # form can use the number in place of a register.
        #
        # A constant is made at each read and nowhere else (`@remade`) when
        # one instruction makes it, or when it is read at most once. It has no
        # register, no slot, and no code at its definition. A read that takes
        # it as an immediate makes nothing. Another read pays a `movz` in place
        # of an `ldr`. A constant read nowhere costs nothing. Example: the line
        # words that `Zr::Lower::Function` stores before every send are each
        # read once, and `IR::Function#hoisted` puts them in the entry block,
        # where each one otherwise uses a register for the whole function. A
        # constant that is read many times and takes several instructions is
        # made once.
        #
        # A symbol's address that is read once (`adrp` and `add`, or a GOT
        # load) is also made at its read. `IR::Function#hoisted` puts it in the
        # entry block, where it otherwise uses a callee-saved register for the
        # whole function. An address read more than once keeps its register:
        # a send reads its site's cell five times before the call, and making
        # the address at each read makes `fib` 6% slower.
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

        # Folds an address that is a base plus a constant into the loads and
        # stores that use it: `ldr x, [base, #k + off]` in place of an `iadd`
        # into a register. The `iadd` then emits nothing (`@silent`), and the
        # allocator keeps its base live at each read (`@via`). A chain of such
        # additions folds to its first base with the sum of the constants.
        #
        # An addition folds only when every use is a load or store through it,
        # and every offset fits the scaled immediate. Otherwise it is made as a
        # value and its reads use it. Examples: the record slots where
        # `Zr::Lower::Function` puts a send's arguments, and a struct field
        # that a kernel def reads (an `iadd` of the pointer and the offset).
        def plan_addresses
          @derived = {}
          @via = {}
          @silent = @remade | @pinned
          memory = Hash.new { |h, k| h[k] = [] }
          # `[value, base, root, k]` for each sum: its own base, and the
          # first base of its chain with the sum of the constants.
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
          # A read that an addition does not fold into still uses it as a
          # value. A later addition that folds releases its base, so the
          # outer additions of a chain are decided first.
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
              # Read as a value, but it is a slot address plus a constant:
              # one `add` from sp, which reads nothing of the chain. The
              # argument vector that `Zr::Lower::Function` gives a send is one.
              @from_sp[v] = at + k
              other[base] -= 1
            end
          end
        end

        # Returns `[base, k]` for an `iadd` of a value and a signed
        # constant, or nil for any other addition.
        def summed(i)
          return nil unless type_of(i.results[0]) == "i64"

          a, b = i.args
          a, b = b, a if constant(a, "i64") && !constant(b, "i64")
          k = constant(b, "i64")
          return nil if k.nil? || constant(a, "i64") || !Regalloc.value?(a)

          [a, k >= 1 << 63 ? k - (1 << 64) : k]
        end

        # Whether one load or store of `width` bytes can encode `off` past
        # `root`: from sp when `root` is a slot's address, or else from the
        # register that contains `root`.
        def reaches?(root, off, width)
          at = @stack[root]
          off += at if at
          immediate?(off, width)
        end

        def immediate?(off, width) = off >= 0 && (off % width).zero? && off / width <= 4095

        # The number of bytes that a load or store of each type moves.
        WIDTHS = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze

        # The `i8` values whose register has zeros above the byte. An operation
        # can read these directly from their home.
        #
        # A register home contains a whole word, and most bytes have unknown
        # bits above them (a narrowing keeps the old word, and a call returns
        # only its low byte), so a read needs a `uxtb`. A `cset`, a byte load
        # and a small constant write zeros above the byte, and so do `and`,
        # `orr` and `eor` of two such bytes. Most bytes in a kernel function
        # are of this kind: every `&&` and `||` of tests joins two of them.
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

        # The value of `v` at the width of `type`, when `v` is a constant.
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
          # The function must restore each callee-saved register that it
          # uses, so the frame has a place for each one.
          @saved_at = {}
          saved = @reg.values.uniq.select { |r| Regalloc.callee?(r) }
          saved << Regalloc::GATES if @enters
          saved.sort_by(&:to_i).each do |r|
            @saved_at[r] = off
            off += 8
          end
          @frame = align(off, 16)
        end

        def align(n, a) = Bytes.align(n, a)

        # The bytes of the x29 pair at the bottom of the frame.
        PAIR = 16
        # The largest frame that one pre-indexed `stp` makes and one
        # post-indexed `ldp` removes. Seven signed bits in units of 8 reach
        # 504, and a frame is a multiple of 16.
        SMALL = 496

        def small_frame? = @frame <= SMALL

        def sig_of(fn) = @types.sig_of(fn)
        def sig_named(sig) = @types.sig_named(sig)
        def callee_of(fn) = @types.callee_named(fn)
        def global_of(gv) = @types.global_named(gv)
        def block_named(name) = @types.block_named(name)

        # --- frame access -------------------------------------------------

        # Returns `[base, offset]` for `off` from sp, with an offset that fits
        # a scaled immediate of `width` bytes. When it does not fit, x17
        # contains a page base.
        #
        # x17, not a scratch register: an instruction can call this while its
        # scratch registers contain its operands (`parallel_copy` keeps a
        # broken cycle's value in x10 across several stores). A page base in
        # a scratch register would overwrite the value to store. x16 and x17
        # are the linker's veneer registers. They are dead across every call
        # and the backend uses them nowhere else.
        def address(off, width)
          return [SP, off] if off % width == 0 && off / width <= 4095

          hi = off & ~0xFFF
          @asm.add X17, SP, hi >> 12, lsl: 12
          [X17, off & 0xFFF]
        end

        # `reg = sp + off`: one `add` for an offset of 12 bits, two for a larger one.
        def frame_address(reg, off)
          return @asm.add(reg, SP, off) if off <= 4095

          @asm.add reg, SP, off >> 12, lsl: 12
          @asm.add reg, reg, off & 0xFFF unless (off & 0xFFF).zero?
        end

        # An f64 value is in its slot as bits and moves through the
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

        # The register to read an operand from: its register home, or else
        # `scratch` after a load.
        #
        # Only operands use this. A result always goes to a scratch register
        # and is stored from there. Otherwise, an instruction that writes its
        # destination before it reads all sources can overwrite an operand
        # in the same register.
        #
        # An `i8` is read directly only when it is `@clean`. Its home contains
        # the whole word, and a w-register read gives the bits above the
        # byte to a 32-bit operation.
        def value_in(v, scratch)
          return Regalloc::GATES if @pinned.include?(v)

          home = @reg[v]
          return home if home && (type_of(v) != "i8" || @clean.include?(v))

          load_value(v, scratch)
          scratch
        end

        # The register for a result: its register home, or else a scratch
        # register to store from.
        #
        # Use this only in an instruction that reads every operand before it
        # writes its destination. An instruction that reads an operand after
        # that (`emit_rem`, `emit_mul_overflow`) finds the operand overwritten.
        def result_in(v, scratch) = @reg[v] || scratch

        # A register home contains the whole word, so a narrower value uses
        # its low bits, the same bits that the narrow load gives.
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

        # One `stp` makes a small frame and also moves sp. A large frame
        # keeps the pair where `stp` puts it, above the whole frame, and
        # moves sp down by the frame size. The `PAIR` bytes at the bottom
        # are then not used.
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
          # After eight arguments, the ABI puts arguments on the stack. Every
          # lowering keeps a signature to eight, and the whole runtime (4732
          # functions) has at most eight parameters and eight call arguments.
          # Thus this refuses, in place of a stack argument path that no
          # program uses.
          raise Refused, "#{@f.name}: more than eight parameters" if entry.params.size > IR::REGISTER_ARGS

          ints, floats = entry.params.partition { |_, t| t != "f64" }.map { |list| list.map(&:first) }
          # The integer parameters arrive in x0.., and a home can be one of
          # those registers, so they move as one parallel copy. The floats
          # move after them, because a float's home can also be an argument
          # register that an integer has not left yet.
          move_registers(ints.map { |v| [place(v), v] }, ints.each_index.map { |n| Registers.x(n) })
          floats.each_with_index do |v, n|
            @asm.fmov X9, Registers.d(n)
            store_param(v, X9)
          end
        end

        # Parallel moves between registers and values. Each `[to, v]` of
        # `dests` gets the source at the same index of `srcs`. A source is a
        # value or a register, and `to` is a register or the value whose place
        # gets it. No destination is written while a pending copy reads it.
        # `SCRATCH[1]` breaks a cycle.
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

        # One move of `move_registers`: to the register `to`, or to the
        # home of the value `v`.
        def move_register(to, v, src)
          if v.nil?
            src.is_a?(Register) ? @asm.mov(to, src) : load_value(src, to)
          elsif src.is_a?(Register)
            store_param(v, src)
          else
            store_value(v, value_in(src, SCRATCH[0]))
          end
        end

        # Two immediates reach 16 MiB less one page. A larger frame is a
        # refusal, with a message that gives the function, not a truncated frame.
        def sub_sp(n)
          raise Refused, "#{@f.name} needs a frame of #{n} bytes, past the 16 MiB sub sp reaches" if n >= 1 << 24

          @asm.sub SP, SP, n >> 12, lsl: 12 if n >= 4096
          @asm.sub SP, SP, n & 0xFFF if (n & 0xFFF) != 0
        end

        # Moves the saved registers to or from their places, two at a time
        # where the pair form reaches (its offset is seven signed bits in
        # units of 8), and one at a time after that.
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

        # A function with one return has its epilogue at that return. A
        # function with more returns shares one epilogue. Each return branches
        # to it, except the last, which ends the last block and falls into it.
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

        # A float instruction's result stays in its d register until the
        # instruction is emitted. Then it is also stored to its home.
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
            # The next branch or select reads the flags, so there is no
            # boolean. A bit test reads the word, so it emits nothing here.
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
            # A narrower value reads the low bits of its slot. A wider value
            # needs zeros in the high bits, which the narrow load gives.
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
            # The same bits as another type: the d register that contains
            # them also contains the result.
            load_value(i.args[0], X9)
            store_value(i.results[0], X9)
            remember_double(i.results[0], @doubles[i.args[0]]) if @doubles.key?(i.args[0])
          when :brif then emit_brif(i)
          when :jump then emit_jump(i)
          when :return then emit_return(i)
          else raise Refused, "#{@f.name}: no lowering for #{i.op}"
          end
        end

        # A branch to one of two blocks. A fused compare puts the result in
        # the flags. A bit test reads the word. Otherwise the branch tests
        # the boolean. The next block needs no branch: control falls into it.
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
        # branch uses the opposite condition to skip over a `b`. A `b`
        # reaches 128 MB, and a conditional branch reaches 1 MB.
        def branch_if(op, target, *operands)
          return @asm.public_send(op, *operands, @labels.fetch(target)) unless @far

          @asm.public_send(OPPOSITE.fetch(op), *operands, 2)
          @asm.b @labels.fetch(target)
        end

        # `csel` on the flags of a fused compare, or else on its own `cmp`
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

        # `b.cond` to a block, on the flags of a fused compare. A far branch
        # uses the opposite condition to skip over a `b`, as in `branch_if`.
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

        # The largest offset that a pair reaches: seven signed bits in units of 8.
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

        # Two stores as one `stp` where the pair form reaches, or else as
        # two `str` through one address.
        def emit_store_pair(first, second)
          a = value_in(first.args[0], X9)
          # When both stores write the same value or number, read it into
          # one register. Most pairs are two nils.
          same = first.args[0] == second.args[0] ||
                 (constant(first.args[0], "i64") && constant(first.args[0], "i64") == constant(second.args[0], "i64"))
          b = same ? a : value_in(second.args[0], X12)
          base, off = through(first.args[1], X10, first.offset, 8)
          if off <= PAIR_REACH
            @asm.stp a, b, [base, off]
          else
            @asm.str a, [base, off]
            # sp cannot be a base for `reach`: the register-form `add` reads
            # register 31 as xzr. `address` puts the page of sp in x17.
            @asm.str b, base.equal?(SP) ? address(off + 8, 8) : reach(base, off + 8, 8)
          end
        end

        # The memory operand for `off` past the address in `base`. This is sp
        # when `base` is a slot's address and the sum fits. Otherwise it is
        # the address in a register, loaded into `scratch` when it has no
        # register. A folded base (`@derived`) is its root plus a constant. A
        # value made from sp (`@from_sp`) is also read from sp: the direct
        # call loads its arguments this way from a send's argument vector.
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

        # A base and an offset that one load or store can encode: the offset
        # scaled into 12 bits, or else the whole address made in X11 first.
        # The two methods above do not use X11.
        def reach(base, off, width)
          return [base, off] if immediate?(off, width)

          materialize(X11, off)
          @asm.add X11, base, X11
          [X11, 0]
        end

        # A symbol's address: page plus offset for a symbol that this link
        # defines, or through the GOT for an import.
        def emit_symbol(result, symbol, local)
          symbol_address(X9, symbol, local)
          store_value(result, X9)
        end

        # `reg = &symbol`: the page and the offset for a symbol of this link,
        # or the GOT word for a symbol of another link.
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

        # Integer arguments go in x0.. and float arguments in d0.., each in
        # its own order, as the ABI specifies. The floats go first, read from
        # their current registers. The integers move as one parallel copy,
        # because an argument can be in the register of another argument.
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

        # The pointer goes to x16 before the arguments move. It can be in
        # an argument register, and no argument load uses x16.
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

        # `fcmp`, and the condition that reads its flags.
        def emit_fcompare(i)
          a = double_in(i.args[0])
          b = double_in(i.args[1])
          @asm.fcmp a, b
          FCONDS.fetch(i.cond)
        end

        # --- doubles ------------------------------------------------------

        # An f64 value is in its home as bits. A float instruction moves it
        # into a d register, and it stays there for the rest of its block
        # (`@doubles`), so the next float instruction that reads it moves
        # nothing. The registers are used in rotation. When its register is
        # used again, the next read loads the value from its home.

        # The d register that contains `v`. It loads `v` from its home when
        # `v` is in no d register.
        def double_in(v)
          @doubles[v] || begin
            d = next_double
            @asm.fmov d, value_in(v, X9)
            remember_double(v, d)
          end
        end

        # The d register where a float instruction writes `v`. `emit` stores
        # it to the home of `v` after the instruction.
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

        # `cmp`, and the arm64 condition that reads its flags. A 12-bit
        # constant uses the immediate form and no register. The check that
        # `Zr::Lower::Function#checked` makes after every call is `cmp x, #52`.
        # A constant on the left moves to the right, and the condition swaps.
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

        # A binary operation. A constant operand is an immediate when the
        # instruction has an immediate form.
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

        # `clz` is one instruction. `ctz` is `rbit` then `clz`. `bswap` is `rev`.
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

        # Counts the set bits one byte at a time in a d register: move the
        # word in (`fmov s, w` for an i32, which clears the rest), count each
        # byte (`cnt`), add them into the low byte (`addv`), and read the
        # whole register back.
        def emit_popcnt(i)
          @asm.fmov COUNTER, reg_for(i.args[0], value_in(i.args[0], X9))
          @asm.cnt COUNTER, COUNTER
          @asm.addv COUNTER, COUNTER
          d = result_in(i.results[0], X11)
          @asm.fmov d, COUNTER
          store_value(i.results[0], d)
        end

        # `add`/`sub` of 12 bits, a shift by less than the register width, and
        # `and`/`orr`/`eor` of a bitmask immediate. Returns false, and emits
        # nothing, when the constant fits no form.
        #
        # The constant has the width of its type, the same as a load gives.
        # The instruction runs at the width of the register form, so the low
        # bits of the result are the same.
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

        # `a - (a / b) * b`, the arm64 form of a remainder.
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

        # Block arguments as a parallel copy: every destination gets the
        # value that its source had before the jump, in any copy order.
        # There is no limit on the number of arguments on an edge, because
        # the resolver keeps only one value in a `SCRATCH` register at a time.
        def emit_jump(i)
          name, args = i.targets[0]
          parallel_copy(block_named(name).params.map(&:first), args)
          @asm.b @labels.fetch(name) unless name == @next
        end

        # The location of a value between instructions: the register from
        # the allocator, or the offset of its frame slot. Two values share a
        # place only when they share a register, because each slot has its
        # own offset.
        #
        # A Register or an Integer, with no tag. A Register compares by
        # identity and is never equal to a number, so the two kinds cannot
        # be confused. This runs several times for every edge in the program,
        # so it must not make an Array.
        #
        # A constant made at its reads has no place and is never a
        # destination. Its name is in place of a location, and no Register or
        # Integer is equal to it.
        def place(v) = @reg[v] || @home.fetch(v) { @remade.include?(v) ? v : @pinned.include?(v) ? Regalloc::GATES : raise(KeyError, v) }

        # The copies of an edge, in an order where no destination is written
        # while a source must still be read from it.
        #
        # An argument that is already in its parameter's place (for example a
        # loop variable that the back edge passes without change) needs no
        # instruction. Another argument needs one load, `mov` or store. A
        # temporary is necessary only for a real cycle, where two parameters
        # swap places.
        #
        # The saving is small: the allocator gives out ten registers, so most
        # arguments and parameters are in the frame, and a slot-to-slot copy
        # still costs a load and a store. The saving is on edges where one end
        # has a register.
        #
        # `SCRATCH[0]` contains one copy and is dead after it. `SCRATCH[1]`
        # contains the value that a broken cycle moved out, and is live until
        # the last copy of that cycle.
        def parallel_copy(dests, srcs)
          pending = {}
          reads = Hash.new(0)
          dests.each_with_index do |d, n|
            s = srcs[n]
            to = place(d)
            from = place(s)
            # Already in place. The types must also be the same: a place
            # contains a whole word, and a narrower value is read at its own width.
            next if to == from && type_of(d) == type_of(s)

            pending[to] = [d, s]
            reads[from] += 1
          end
          drain(pending, reads)
          break_cycle(pending) until pending.empty?
        end

        # Emits every copy whose destination no pending copy reads, then
        # every copy that this frees, until only cycles are left.
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

        # After `drain`, only cycles are left: every remaining destination is
        # still read, and a copy reads one place, so the remaining places map
        # one to one onto themselves.
        #
        # Move the source of one copy into a scratch register. Then the rest
        # of its cycle can be emitted in order.
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

        # Copies one value to the place of another. A source with a register
        # home is stored directly from it. Only a slot source needs a load.
        def copy(dest, source) = store_value(dest, value_in(source, SCRATCH[0]))

        # The number of instructions that `materialize` uses for `n`.
        def materialized(n)
          n &= 0xFFFF_FFFF_FFFF_FFFF
          chunks = 4.times.map { |k| (n >> (16 * k)) & 0xFFFF }
          filler = chunks.count(0xFFFF) > chunks.count(0) ? 0xFFFF : 0
          [chunks.count { |c| c != filler }, 1].max
        end

        # `reg = n`, 16 bits at a time. A negative value starts from its
        # complement, so the high halves need no instruction.
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
