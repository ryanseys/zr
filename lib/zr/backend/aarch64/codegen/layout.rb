# frozen_string_literal: true

require_relative "../../../bytes"

module Zr
  module Backend
    module Aarch64
      class Codegen
        # The layout of a function: its types, the plans that pick the
        # instruction forms, the frame slots and the home of each value.

        private

        # The blocks in the order of their code: the others in their own
        # order, then the cold ones (`IR::Block#cold`), so that a common path
        # falls through and fetches no taken branch over a slow path. A block
        # is also cold when every block that jumps to it is cold. The entry
        # stays first. The registers do not depend on this order: each value
        # keeps one register or one home for its whole life.
        #: () -> Array[IR::Block]
        def laid_out
          entry = @f.entry_block
          before = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[String]]
          @f.blocks.each { |b| b.insts.last&.targets&.each { |(to, _)| before[to] << b.name } }
          cold = Set.new(@f.blocks.select { |b| b.cold && !b.equal?(entry) }.map(&:name))
          # Most blocks come after the blocks that jump to them, so one pass
          # in order finds most of them, and a loop's head needs another.
          loop do
            grew = false
            @f.blocks.each do |b|
              next if b.equal?(entry) || cold.include?(b.name) || before[b.name].empty?
              next unless before[b.name].all? { |p| cold.include?(p) }

              cold << b.name
              grew = true
            end
            break unless grew
          end
          hot, slow = @f.blocks.partition { |b| !cold.include?(b.name) }
          hot + slow
        end

        #: () -> Hash[String, String?]
        def assign_types
          @types = IR::Types.new(@f)
          @types.all
        rescue IR::Types::Refused => e
          raise Refused, e.message, cause: e
        end

        # Every value that the backend reads has a type.
        #: (String v) -> String
        def type_of(v)
          @types.of(v) #: String
        rescue IR::Types::Refused => e
          raise Refused, e.message, cause: e
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
        # The first instruction after `n` of `insts` that is not neutral to
        # the flags: the one that reads them, if any does. It counts an
        # index, so no compare copies the rest of its block.
        #: (Array[IR::Inst] insts, Integer n) -> IR::Inst?
        def flag_reader(insts, n)
          j = n + 1
          j += 1 while j < insts.size && FLAG_NEUTRAL.include?(insts[j].op)
          insts[j]
        end

        #: () -> void
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

              reader = flag_reader(insts, n)
              next unless reader && (reader.op == :brif || reader.op == :select) && reader.args[0] == r

              # In both cases the boolean is never made, so it has no home.
              @silent << r
              if cmp.op == :icmp && reader.op == :brif && (test = bit_test(cmp))
                @bit_tests[reader] = test
                @silent << cmp.args.find { |a| @def_of[a]&.op == :band }
                @via[r] = test[0]
              else
                @fused[cmp] = reader
                next unless cmp.op == :icmp && (test = mask_test(cmp, n.positive? ? insts[n - 1] : nil))

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
        FLAG_SETTERS = %i[sadd_overflow ssub_overflow smul_overflow].to_set.freeze #: Set[IR::op]

        # Two word stores to the same base, the second 8 bytes after the
        # first, with no emitted instruction between them, become one `stp`.
        # The nil fills after every send and in every prologue are runs of
        # these. `@pairs` maps the first store to the second. `@paired`
        # contains the second stores, which emit nothing.
        #: () -> void
        def plan_pairs
          @pairs = {}
          @paired = Set.new
          @f.blocks.each do |b|
            b.insts.reject { |i| @silent.include?(i.results[0]) }.each_cons(2) do |first, second|
              next unless first && second && first.op == :store && second.op == :store && !@paired.include?(first)
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
        #: (IR::Inst cmp) -> [String, Integer, Symbol]?
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
        # `tst` in place of an `and` and a `cmp`. The mask can also be a
        # second word (a value), when the `band` is `prev`, the instruction
        # just before the compare. Then the second word is still in its
        # place at the compare, though the `band` was its last read.
        #: (IR::Inst cmp, IR::Inst? prev) -> [String, Integer | String]?
        def mask_test(cmp, prev)
          return unless cmp.cond == "eq" || cmp.cond == "ne"

          m, z = cmp.args
          m, z = z, m if @const.key?(m)
          return unless constant(z, type_of(m)) == 0 && @uses[m] == 1 && @def_of[m]&.op == :band

          x, k = @def_of[m].args
          x, k = k, x if @const.key?(x)
          return if @const.key?(x)

          mask = constant(k, type_of(x))
          return [x, mask] if mask && Assembler.bitmask(mask, wide?(x) ? 64 : 32)

          [x, k] if prev.equal?(@def_of[m]) && type_of(k) == type_of(x)
        end

        # A `gates` value is the gate word at the time of the read. A later
        # instruction that uses the value must see that word, not the current
        # contents of the register. When every read is in the defining block
        # and before anything that can change the register (a call, because a
        # callee can set a gate, or a write to the register), each read uses
        # `x28` directly (`@pinned`). It then has no register, no home, and no
        # code at its definition, and a bit test of it is one `tbz` of `x28`.
        # Any other `gates` value is copied from the register at its definition.
        #: () -> void
        def plan_pinned
          @pinned = Set.new
          @f.blocks.each do |b|
            open = {} #: Hash[String, Integer]
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
        #: () -> void
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
        #: () -> void
        def plan_slots
          off = PAIR
          @slot_at = @f.slots.map do |s|
            off = Bytes.align(off, [s.align, 8].max)
            at = off
            off += s.bytes
            at
          end
          @slots_end = Bytes.align(off, 8)
          @stack = {}
          @va_list = nil
          @f.blocks.each do |b|
            b.insts.each do |i|
              @va_list = i if i.op == :va_list
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
        #: () -> void
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
        #: () -> void
        def plan_addresses
          @derived = {}
          @via = {}
          @silent = @remade | @pinned
          memory = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[[Integer, Integer]]]
          # `[value, base, root, k]` for each sum: its own base, and the
          # first base of its chain with the sum of the constants.
          sums = [] #: Array[[String, String, String, Integer]]
          chain = {} #: Hash[String, [String, Integer]]
          @f.blocks.each do |b|
            b.insts.each do |i|
              case i.op
              when :load then memory[i.args[0]] << [i.offset, WIDTHS.fetch(i.type)]
              when :store then memory[i.args[1]] << [i.offset, WIDTHS.fetch(type_of(i.args[0]))]
              when :iadd
                base, k = summed(i)
                next unless base && k

                if (link = chain[base])
                  root, j = link
                  k += j
                else
                  root = base
                end
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
        #: (IR::Inst i) -> [String, Integer]?
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
        #: (String root, Integer off, Integer width) -> bool
        def reaches?(root, off, width)
          at = @stack[root]
          off += at if at
          immediate?(off, width)
        end

        #: (Integer off, Integer width) -> bool
        def immediate?(off, width) = off >= 0 && (off % width).zero? && off / width <= 4095

        # The number of bytes that a load or store of each type moves.
        WIDTHS = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze #: Hash[String, Integer]

        # The `i8` values whose register has zeros above the byte. An operation
        # can read these directly from their home.
        #
        # A register home contains a whole word, and most bytes have unknown
        # bits above them (a narrowing keeps the old word, and a call returns
        # only its low byte), so a read needs a `uxtb`. A `cset`, a byte load
        # and a small constant write zeros above the byte, and so do `and`,
        # `orr` and `eor` of two such bytes. Most bytes in a kernel function
        # are of this kind: every `&&` and `||` of tests joins two of them.
        #: () -> void
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
        #: (untyped v, String type) -> Integer?
        def constant(v, type)
          k = @const[v]
          k && k & WIDTH_MASK.fetch(type, 0xFFFF_FFFF_FFFF_FFFF)
        end

        #: () -> void
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
          # uses, so the frame has a place for each one. A function that
          # foreign code enters saves all of them, x28 too: then the
          # values that C keeps in them are in this frame, where the
          # collector's scan of the C frames reads them
          # (`zr_mark_task`).
          @saved_at = {}
          saved = @reg.values.uniq.select { |r| Regalloc.callee?(r) }
          saved = (saved + Regalloc::CALLEE + [Regalloc::GATES]).uniq if @enters
          saved.sort_by(&:to_i).each do |r|
            @saved_at[r] = off
            off += 8
          end
          @frame = Bytes.align(off, 16)
        end

        # The bytes of the x29 pair at the bottom of the frame.
        PAIR = 16
        # The largest frame that one pre-indexed `stp` makes and one
        # post-indexed `ldp` removes. Seven signed bits in units of 8 reach
        # 504, and a frame is a multiple of 16.
        SMALL = 496

        #: () -> bool
        def small_frame? = @frame <= SMALL

        # Every name in a function's instructions is defined in it.
        #: (String? fn) -> IR::Sig
        def sig_of(fn) = @types.sig_of(fn)
        #: (String? sig) -> IR::Sig
        def sig_named(sig) = @types.sig_named(sig)
        #: (String? fn) -> IR::Callee
        def callee_of(fn) = @types.callee_named(fn) #: IR::Callee
        #: (String gv) -> IR::Global
        def global_of(gv) = @types.global_named(gv) #: IR::Global
        #: (String name) -> IR::Block
        def block_named(name) = @types.block_named(name)
      end
    end
  end
end
