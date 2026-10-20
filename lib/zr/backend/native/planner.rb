# frozen_string_literal: true

require_relative "../../bytes"
require_relative "../../ir/inst"
require_relative "../../ir/types"

module Zr
  module Backend
    module Native
      # The layout of a function that every machine backend shares: its
      # types, the plans that pick the instruction forms, the frame slots
      # and the home of each value. A backend's Codegen includes it and
      # answers the hooks:
      #
      # - `flag_neutral?(op)`: the lowering of `op` leaves the flags as
      #   they are, so a compare's flags stay valid across it;
      # - `logical_immediate?(mask, bits)`: one flag-setting `and` takes
      #   `mask` as an immediate;
      # - `materialized(n)`: the instructions that make the constant `n`;
      # - `immediate?(off, width)`: one load or store of `width` bytes
      #   encodes `off` past its base;
      # - `slot_address?(off)`: one instruction makes `sp + off`;
      # - `frame_base`: the bytes below the first slot;
      # - `callee_saves(used)`: the callee-saved registers that the
      #   frame saves, in their order, given the registers the function uses;
      # - `wide?(v)`: `v` is 64 bits wide.
      #
      # It also reads `@pinned`, the values that the backend reads from a
      # fixed register and that have no code at their definition. The
      # backend's registers and its `Refused` have its own types, which a
      # shared module cannot name: the registers are untyped here, and a
      # line that names `self.class::Refused` has `steep:ignore`.
      # @rbs module-self: _Layout
      module Planner
        # @rbs @f: IR::Function
        # @rbs @types: IR::Types
        # @rbs @fused: Hash[IR::Inst, untyped]
        # @rbs @bit_tests: Hash[IR::Inst, [String, Integer, Symbol]]
        # @rbs @mask_tests: Hash[IR::Inst, [String, Integer | String]]
        # @rbs @uses: Hash[String, Integer]
        # @rbs @def_of: Hash[String, IR::Inst]
        # @rbs @returns: Integer
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
        # @rbs @home: Hash[String, Integer]
        # @rbs @frame: Integer
        # The backend's own registers.
        # @rbs @reg: Hash[String, untyped]
        # @rbs @saved_at: Hash[untyped, Integer]

        # The bits that an operand of each type gives to an instruction:
        # the width that its load gives it.
        WIDTH_MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze #: Hash[String, Integer]
        # The number of bytes that a load or store of each type moves.
        WIDTHS = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze #: Hash[String, Integer]
        # The instructions whose second result is a flag that they also set
        # in the flags: the overflow checks. Their branch reads the overflow
        # flag directly when nothing is between them.
        FLAG_SETTERS = %i[sadd_overflow ssub_overflow smul_overflow].to_set.freeze #: Set[IR::op]

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
          cold = Set.new(@f.blocks.filter_map { |b| b.name if b.cold && !b.equal?(entry) })
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
          raise self.class::Refused, e.message, cause: e # steep:ignore UnknownConstant
        end

        # Every value that the backend reads has a type.
        #: (String v) -> String
        def type_of(v)
          @types.of(v) #: String
        rescue IR::Types::Refused => e
          raise self.class::Refused, e.message, cause: e # steep:ignore UnknownConstant
        end

        # The first instruction after `n` of `insts` that is not neutral to
        # the flags: the one that reads them, if any does. It counts an
        # index, so no compare copies the rest of its block.
        #: (Array[IR::Inst] insts, Integer n) -> IR::Inst?
        def flag_reader(insts, n)
          j = n + 1
          j += 1 while j < insts.size && flag_neutral?(insts[j].op)
          insts[j]
        end

        # An `icmp` whose only use is a `brif` or a `select` in the same block,
        # with no flag write between them, needs no boolean. The compare sets
        # the flags and the branch or select reads them.
        #
        # Without this, the pair costs a compare, a set, a byte store, a byte
        # load, a zero extension and a branch on zero. `Zr::Lower::Function#checked`
        # writes this pair after every call in a compiled Ruby method, so most
        # branches in the program have this shape. The stack check at the
        # start of every Ruby function has a load between the two.
        #
        # A branch on one bit of a word (`brif (band x, 2^n) != 0`) tests
        # the bit of the word (`@bit_tests`). The `band` and the compare emit
        # nothing (`@silent`), and the allocator keeps the word live to the
        # branch (`@via`).
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

                # The test reads the word, so the `band` is never made.
                @mask_tests[cmp] = test
                m = cmp.args.find { |a| @def_of[a]&.op == :band }
                @silent << m
                @via[m] = test[0]
              end
            end
          end
        end

        # Returns `[word, bit, branch]` when `cmp` tests one bit of a word:
        # it compares a `band` of the word and a power of two with zero, and
        # nothing else reads the `band`. The branch is `:tbnz` when it is
        # taken for a set bit and `:tbz` when it is taken for a clear one.
        #: (IR::Inst cmp) -> [String, Integer, Symbol]?
        def bit_test(cmp)
          return unless (x, mask = banded(cmp))
          return unless mask&.positive? && (mask & (mask - 1)).zero?

          [x, mask.bit_length - 1, cmp.cond == "ne" ? :tbnz : :tbz]
        end

        # Returns `[word, mask]` when `cmp` tests whether any of some bits of
        # a word are set: a `band` of the word and a mask that one
        # flag-setting `and` takes as an immediate, compared with zero, and
        # nothing else reads the `band`. The mask can also be a second word
        # (a value), when the `band` is `prev`, the instruction just before
        # the compare. Then the second word is still in its place at the
        # compare, though the `band` was its last read.
        #: (IR::Inst cmp, IR::Inst? prev) -> [String, Integer | String]?
        def mask_test(cmp, prev)
          return unless (x, mask, k, band = banded(cmp))
          return [x, mask] if mask && logical_immediate?(mask, wide?(x) ? 64 : 32)

          [x, k] if prev.equal?(band) && type_of(k) == type_of(x)
        end

        # Returns `[word, mask, k, band]` when `cmp` compares with zero a
        # `band` that nothing else reads, of a word and `k`: `mask` is `k`'s
        # number when it is a constant.
        #: (IR::Inst cmp) -> [String, Integer?, String, IR::Inst]?
        def banded(cmp)
          return unless cmp.cond == "eq" || cmp.cond == "ne"

          m, z = cmp.args
          m, z = z, m if @const.key?(m)
          return unless constant(z, type_of(m)) == 0 && @uses[m] == 1 && @def_of[m]&.op == :band

          band = @def_of[m]
          x, k = band.args
          x, k = k, x if @const.key?(x)
          return if @const.key?(x)

          [x, constant(k, type_of(x)), k, band]
        end

        # Counts the reads of each value, by an instruction or by a jump
        # that gives it to a block. A value read once or never gets a
        # different plan from a value read many times.
        #: () -> void
        def count_uses
          @uses = Hash.new(0)
          @def_of = {}
          @returns = 0
          # Whether foreign code calls this function. Such a function sets
          # up the gates and restores them before it returns.
          @enters = false
          @f.blocks.each do |b|
            b.insts.each do |i|
              @def_of[i.results[0]] = i if i.results[0]
              @returns += 1 if i.op == :return
              @enters = true if i.op == :gates_enter
              i.args.each { |a| @uses[a] += 1 if IR.value?(a) }
              i.targets&.each { |(_, args)| args.each { |a| @uses[a] += 1 if IR.value?(a) } }
            end
          end
        end

        # The offset of each slot above sp. Slots come first in the frame,
        # after `frame_base`, so the offsets are known before any value has
        # a home.
        #
        # A slot's address is made at each read, as for a small constant
        # (`@stack`). `IR::Function#hoisted` puts every `stack_addr` in the
        # entry block, so otherwise each one uses a register for the whole
        # function, and the frame saves and restores it. A load or store
        # through a slot address uses sp directly and makes nothing.
        #: () -> void
        def plan_slots
          off = frame_base
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
              @stack[i.results[0]] = at if slot_address?(at)
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
        # it as an immediate makes nothing. Example: the line words that
        # `Zr::Lower::Function` stores before every send are each read once,
        # and `IR::Function#hoisted` puts them in the entry block, where each
        # one otherwise uses a register for the whole function. A constant
        # that is read many times and takes several instructions is made once.
        #
        # A symbol's address that is read once is also made at its read.
        # `IR::Function#hoisted` puts it in the entry block, where it
        # otherwise uses a callee-saved register for the whole function. An
        # address read more than once keeps its register: a send reads its
        # site's cell five times before the call, and making the address at
        # each read makes `fib` 6% slower.
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
        # stores that use it: one load from `[base + k + off]` in place of an
        # `iadd` into a register. The `iadd` then emits nothing (`@silent`),
        # and the allocator keeps its base live at each read (`@via`). A
        # chain of such additions folds to its first base with the sum of
        # the constants.
        #
        # An addition folds only when every use is a load or store through it,
        # and every offset fits the immediate. Otherwise it is made as a
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
              # one addition from sp, which reads nothing of the chain. The
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
          return nil if k.nil? || constant(a, "i64") || !IR.value?(a)

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

        # The `i8` values whose register has zeros above the byte. An operation
        # can read these directly from their home.
        #
        # A register home contains a whole word, and most bytes have unknown
        # bits above them (a narrowing keeps the old word, and a call returns
        # only its low byte), so a read needs a zero extension. A flag set, a
        # byte load and a small constant write zeros above the byte, and so
        # do `band`, `bor` and `bxor` of two such bytes. Most bytes in a
        # kernel function are of this kind: every `&&` and `||` of tests
        # joins two of them.
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

        # A frame home for each value with no register and no plan, then a
        # place for each callee-saved register that the frame saves.
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
          @saved_at = {}
          callee_saves(@reg.values.uniq).each do |r|
            @saved_at[r] = off
            off += 8
          end
          @frame = Bytes.align(off, 16)
        end

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
