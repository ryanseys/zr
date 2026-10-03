# frozen_string_literal: true

require_relative "registers"
require_relative "../../refused"

module Zr
  module Backend
    module Aarch64
      # An arm64 encoder for only the instructions that the two backends
      # emit. An instruction is a word, or an object whose `encode` takes its
      # own index and returns a word after every label has a position.
      #
      # A label contains an instruction index, not a byte offset, so a branch
      # encodes its distance as `target - here`.
      class Assembler
        # @rbs @insns: Array[word]

        # @rbs skip -- in sig/zr/backend/aarch64/registers.rbs
        include Registers

        class Refused < StandardError
          include Zr::Refusal
        end
        # A branch whose target is out of the range of its field.
        class OutOfReach < Refused; end

        CONDITIONS = {
          eq: 0b0000, ne: 0b0001, cs: 0b0010, hs: 0b0010, cc: 0b0011, lo: 0b0011,
          mi: 0b0100, pl: 0b0101, vs: 0b0110, vc: 0b0111, hi: 0b1000, ls: 0b1001,
          ge: 0b1010, lt: 0b1011, gt: 0b1100, le: 0b1101, al: 0b1110
        }.freeze #: Hash[Symbol, Integer]
        SHIFTS = { lsl: 0b00, lsr: 0b01, asr: 0b10 }.freeze #: Hash[Symbol, Integer]

        class Label
          attr_reader :name #: String
          attr_reader :offset #: Integer?

          #: (String name) -> void
          def initialize(name)
            @name = name
            @offset = nil
          end

          #: (Integer offset) -> self
          def at_offset(offset)
            @offset = offset
            self
          end

          #: () -> Integer
          def to_i = @offset || raise(Refused, "the label #{@name} has no place")
        end

        # A branch whose distance is known only when every instruction has
        # an index.
        #
        # The fields of these records are typed in
        # sig/zr/backend/aarch64/assembler.rbs, the methods here.
        # @rbs skip
        Branch = Data.define(:base, :label, :shift, :bits)

        class Branch
          #: (Integer at) -> Integer
          def encode(at)
            distance = label.to_i - at
            limit = 1 << (bits - 1)
            raise OutOfReach, "#{label.name} is #{distance} words away, past a signed #{bits}-bit field" unless distance.between?(-limit, limit - 1)

            base | (Assembler.signed(distance, bits) << shift)
          end
        end

        # `ADR`: a register gets the address of a label, which is within
        # 1 MB of the instruction.
        # @rbs skip
        Adr = Data.define(:d, :label)

        class Adr
          #: (Integer at) -> Integer
          def encode(at)
            bytes = Assembler.signed((label.to_i - at) * 4, 21)
            0x1000_0000 | (bytes & 0b11) << 29 | (bytes >> 2) << 5 | d.to_i
          end
        end

        # One word of a jump table: the distance in bytes from the table's
        # start (`base`) to `label`, signed.
        # @rbs skip
        TableWord = Data.define(:label, :base)

        class TableWord
          #: (Integer _at) -> Integer
          def encode(_at) = Assembler.signed((label.to_i - base.to_i) * 4, 32)
        end

        # Returns `[N, immr, imms]` for a logical immediate, or nil for a
        # value that arm64 cannot encode in one instruction.
        #
        # The only constants `AND`, `ORR` and `EOR` take are a run of
        # ones, rotated, in an element of 2, 4, 8, 16, 32 or 64 bits that
        # repeats to fill the register. 0x5555555555555555 is one, 5 is
        # not. All ones and all zeros are excluded: every element size would
        # encode them, so the encoding uses that space for `N`.
        #
        # Memoized, with one table for each width, not one table keyed by
        # both. A compile makes the same few calls on the same few masks
        # millions of times, and a pair key makes an Array for each call.
        # A value that is not a bitmask memoizes as nil.
        #: (Integer value, Integer width) -> [Integer, Integer, Integer]?
        def self.bitmask(value, width)
          (width == 64 ? BITMASK64 : BITMASK32)[value]
        end

        # Steep types the key of a `Hash.new` block as `Hash::_Key`, not
        # the key type of the constant.
        BITMASK64 = Hash.new do |memo, value|
          memo[value] = encode_bitmask(value, 64) # steep:ignore ArgumentTypeMismatch
        end #: Hash[Integer, [Integer, Integer, Integer]?]
        BITMASK32 = Hash.new do |memo, value|
          memo[value] = encode_bitmask(value, 32) # steep:ignore ArgumentTypeMismatch
        end #: Hash[Integer, [Integer, Integer, Integer]?]

        #: (Integer value, Integer width) -> [Integer, Integer, Integer]?
        def self.encode_bitmask(value, width)
          full = (1 << width) - 1
          value &= full
          return nil if value.zero? || value == full

          # The smallest element that repeats: halve while the two halves
          # of the element are equal.
          size = width
          while size > 2
            half = size / 2
            low = value & ((1 << half) - 1)
            break if low != (value >> half) & ((1 << half) - 1)

            value = low
            size = half
          end
          element = (1 << size) - 1
          return nil if value.zero? || value == element

          # The rotation that moves the run down to bit zero, if the element
          # is one run: `x & (x + 1)` is zero only for a value that is all
          # ones below a bit and all zeros above it.
          rotation = (0...size).find { |r| (t = rotated(value, r, size, element)) & (t + 1) == 0 }
          return nil if rotation.nil?

          # `immr` gives the right rotation of the run that makes the value.
          # This is the opposite direction of the search above.
          length = rotated(value, rotation, size, element).bit_length
          [size == 64 ? 1 : 0, (size - rotation) % size, (~(size - 1) << 1 & 0x3F) | (length - 1)]
        end

        #: (Integer value, Integer by, Integer size, Integer element) -> Integer
        def self.rotated(value, by, size, element) = ((value >> by) | (value << (size - by))) & element

        #: (Integer value, Integer bits) -> Integer
        def self.signed(value, bits)
          limit = 1 << (bits - 1)
          raise Refused, "#{value} does not fit a signed #{bits}-bit field" unless value.between?(-limit, limit - 1)

          value & ((1 << bits) - 1)
        end

        #: () -> void
        def initialize
          @insns = []
        end

        #: (String name) -> Label
        def make_label(name) = Label.new(name)

        #: (Label label) -> self
        def put_label(label)
          label.at_offset(@insns.length)
          self
        end

        # The byte offset of the next instruction. A relocation on that
        # instruction points here.
        #: [T] () { (Integer) -> T } -> T
        def patch_location
          yield @insns.length * 4
        end

        #: () -> String
        def to_binary
          @insns.map.with_index { |w, at| w.is_a?(Integer) ? w : w.encode(at) }.pack("L<*")
        end

        # --- arithmetic ---------------------------------------------------

        #: (Registers::Register d, Registers::Register n, operand m, ?lsl: Integer) -> self
        def add(d, n, m, lsl: 0) = addsub(0, 0, d, n, m, lsl)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def adds(d, n, m) = addsub(0, 1, d, n, m, 0)
        #: (Registers::Register d, Registers::Register n, operand m, ?lsl: Integer) -> self
        def sub(d, n, m, lsl: 0) = addsub(1, 0, d, n, m, lsl)
        #: (Registers::Register d, Registers::Register n, operand m, ?shift: Symbol, ?amount: Integer) -> self
        def subs(d, n, m, shift: :lsl, amount: 0) = addsub(1, 1, d, n, m, 0, shift, amount)
        #: (Registers::Register n, operand m, ?shift: Symbol, ?amount: Integer) -> self
        def cmp(n, m, shift: :lsl, amount: 0) = subs(n.zr, n, m, shift: shift, amount: amount)

        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def mul(d, n, m) = madd(d, n, m, d.zr)
        #: (Registers::Register d, Registers::Register n, Registers::Register m, Registers::Register a) -> self
        def madd(d, n, m, a) = multiply(0, d, n, m, a)
        #: (Registers::Register d, Registers::Register n, Registers::Register m, Registers::Register a) -> self
        def msub(d, n, m, a) = multiply(1, d, n, m, a)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def smulh(d, n, m) = emit(0x9B40_7C00 | m.to_i << 16 | n.to_i << 5 | d.to_i)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def udiv(d, n, m) = divide(0, d, n, m)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def sdiv(d, n, m) = divide(1, d, n, m)

        # --- bits ---------------------------------------------------------

        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def and(d, n, m) = logical(0b00, d, n, m)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def orr(d, n, m) = logical(0b01, d, n, m)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def eor(d, n, m) = logical(0b10, d, n, m)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def ands(d, n, m) = logical(0b11, d, n, m)
        #: (Registers::Register n, operand m) -> self
        def tst(n, m) = ands(n.zr, n, m)
        # A register amount shifts by the value in the register. An Integer
        # amount is a bitfield move, which is the arm64 name for these forms.
        # The signatures are the same as the gem's, so `aarch64_test` checks
        # both forms against the ARM specification.
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def lsl(d, n, m) = m.is_a?(Integer) ? ubfm(d, n, (d.size - shift(d, m)) % d.size, d.size - 1 - m) : variable_shift(0b00, d, n, m)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def lsr(d, n, m) = m.is_a?(Integer) ? ubfm(d, n, shift(d, m), d.size - 1) : variable_shift(0b01, d, n, m)
        #: (Registers::Register d, Registers::Register n, operand m) -> self
        def asr(d, n, m) = m.is_a?(Integer) ? sbfm(d, n, shift(d, m), d.size - 1) : variable_shift(0b10, d, n, m)

        # `SXTB` and `SXTW` are `SBFM` over a fixed range of bits, and
        # `UXTB` is `UBFM` over the same range.
        #: (Registers::Register d, Registers::Register n) -> self
        def sxtb(d, n) = sbfm(d, n, 0, 7)
        #: (Registers::Register d, Registers::Register n) -> self
        def sxtw(d, n) = sbfm(d, n, 0, 31)
        #: (Registers::Register d, Registers::Register n) -> self
        def uxtb(d, n) = ubfm(d, n, 0, 7)

        # --- bits ---------------------------------------------------------

        # The one-source forms: the bits reversed, the bytes reversed
        # (`rev` of a w register turns four, of an x register eight), and
        # the leading zeros counted.
        #: (Registers::Register d, Registers::Register n) -> self
        def rbit(d, n) = one_source(0b000000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def rev(d, n) = one_source(d.wide? ? 0b000011 : 0b000010, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def clz(d, n) = one_source(0b000100, d, n)
        #: (Integer opcode, Registers::Register d, Registers::Register n) -> self
        def one_source(opcode, d, n) = emit(0x5AC0_0000 | d.sf << 31 | opcode << 10 | n.to_i << 5 | d.to_i)

        # `cnt v.8b, v.8b` counts the set bits of each of a double's eight
        # bytes; `addv b, v.8b` sums them into the low byte and clears
        # the rest of the register.
        #: (Registers::Register d, Registers::Register n) -> self
        def cnt(d, n) = emit(0x0E20_5800 | n.to_i << 5 | d.to_i)
        #: (Registers::Register d, Registers::Register n) -> self
        def addv(d, n) = emit(0x0E31_B800 | n.to_i << 5 | d.to_i)

        # --- moves --------------------------------------------------------

        # A logical instruction cannot use the stack pointer, so a move that
        # uses sp is an add of zero.
        #: (Registers::Register d, Registers::Register m) -> self
        def mov(d, m)
          d.sp? || m.sp? ? addsub(0, 0, d, m, 0, 0) : logical(0b01, d, d.zr, m)
        end

        #: (Registers::Register d, Integer value, ?lsl: Integer) -> self
        def movz(d, value, lsl: 0) = move_wide(0b10, d, value, lsl)
        #: (Registers::Register d, Integer value, ?lsl: Integer) -> self
        def movn(d, value, lsl: 0) = move_wide(0b00, d, value, lsl)
        #: (Registers::Register d, Integer value, ?lsl: Integer) -> self
        def movk(d, value, lsl: 0) = move_wide(0b11, d, value, lsl)

        # --- conditions ---------------------------------------------------

        #: (Registers::Register d, Registers::Register n, Registers::Register m, Symbol cond) -> self
        def csel(d, n, m, cond)
          emit(0x1A80_0000 | d.sf << 31 | m.to_i << 16 | condition(cond) << 12 | n.to_i << 5 | d.to_i)
        end

        # `CSET d, cond` is `CSINC d, zr, zr` on the opposite condition.
        #: (Registers::Register d, Symbol cond) -> self
        def cset(d, cond)
          zr = d.zr.to_i
          emit(0x1A80_0400 | d.sf << 31 | zr << 16 | (condition(cond) ^ 1) << 12 | zr << 5 | d.to_i)
        end

        # --- SIMD&FP, doubles only ----------------------------------------

        # `fmov d, x`, `fmov x, d` or `fmov d, d`: the registers select the form.
        # `fmov d, x` and `fmov s, w` (the rest of the register cleared),
        # `fmov d, d` and `fmov x, d`.
        #: (Registers::Register d, Registers::Register n) -> self
        def fmov(d, n)
          if d.float? && n.float? then emit(0x1E60_4000 | n.to_i << 5 | d.to_i)
          elsif d.float? then emit((n.wide? ? 0x9E67_0000 : 0x1E27_0000) | n.to_i << 5 | d.to_i)
          else emit(0x9E66_0000 | n.to_i << 5 | d.to_i)
          end
        end
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def fadd(d, n, m) = float3(0x1E60_2800, d, n, m)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def fsub(d, n, m) = float3(0x1E60_3800, d, n, m)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def fmul(d, n, m) = float3(0x1E60_0800, d, n, m)
        #: (Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def fdiv(d, n, m) = float3(0x1E60_1800, d, n, m)
        #: (Registers::Register d, Registers::Register n) -> self
        def fneg(d, n) = float2(0x1E61_4000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def fabs(d, n) = float2(0x1E60_C000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def fsqrt(d, n) = float2(0x1E61_C000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def frintm(d, n) = float2(0x1E65_4000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def frintp(d, n) = float2(0x1E64_C000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def frintz(d, n) = float2(0x1E65_C000, d, n)
        #: (Registers::Register d, Registers::Register n) -> self
        def frintn(d, n) = float2(0x1E64_4000, d, n)
        #: (Registers::Register n, Registers::Register m) -> self
        def fcmp(n, m) = emit(0x1E60_2000 | m.to_i << 16 | n.to_i << 5)
        # `scvtf d, x` or `scvtf d, w`: the integer register's width selects the form.
        #: (Registers::Register d, Registers::Register n) -> self
        def scvtf(d, n) = emit((n.wide? ? 0x9E62_0000 : 0x1E62_0000) | n.to_i << 5 | d.to_i)
        #: (Registers::Register d, Registers::Register n) -> self
        def fcvtzs(d, n) = emit(0x9E78_0000 | n.to_i << 5 | d.to_i)

        # --- memory -------------------------------------------------------

        #: (Registers::Register rt, address address) -> self
        def ldr(rt, address) = rt.float? ? float_load_store(1, rt, address) : load_store(gp_size(rt), 1, rt, address)
        #: (Registers::Register rt, address address) -> self
        def str(rt, address) = rt.float? ? float_load_store(0, rt, address) : load_store(gp_size(rt), 0, rt, address)
        # The size field of a load or a store of a general register.
        #: (Registers::Register rt) -> Integer
        def gp_size(rt) = rt.wide? ? 0b11 : 0b10
        #: (Registers::Register rt, address address) -> self
        def ldrb(rt, address) = load_store(0b00, 1, rt, address)
        #: (Registers::Register rt, address address) -> self
        def strb(rt, address) = load_store(0b00, 0, rt, address)
        # `ldrsw xt, [xn, xm, lsl #2]`: a signed word of a table, at index `xm`.
        #: (Registers::Register rt, Registers::Register n, Registers::Register m) -> self
        def ldrsw_index(rt, n, m) = emit(0xB8A0_7800 | m.to_i << 16 | n.to_i << 5 | rt.to_i)
        #: (Registers::Register rt1, Registers::Register rt2, address address, ?(Integer | :!)? imm) -> self
        def ldp(rt1, rt2, address, imm = nil) = pair(1, rt1, rt2, address, imm)
        #: (Registers::Register rt1, Registers::Register rt2, address address, ?(Integer | :!)? imm) -> self
        def stp(rt1, rt2, address, imm = nil) = pair(0, rt1, rt2, address, imm)

        # --- control ------------------------------------------------------

        # `B` to a label, or `B.cond` when a condition is given. The
        # signature is the same as the gem's, so `aarch64_test` checks the
        # encoding against the ARM specification.
        #: (target label, ?cond: Symbol?) -> self
        def b(label, cond: nil)
          return branch(0x1400_0000, label, 0, 26) if cond.nil?

          branch(0x5400_0000 | condition(cond), label, 5, 19)
        end
        #: (target label) -> self
        def bl(label) = branch(0x9400_0000, label, 0, 26)
        #: (Registers::Register n) -> self
        def blr(n) = emit(0xD63F_0000 | n.to_i << 5)
        #: (Registers::Register n) -> self
        def br(n) = emit(0xD61F_0000 | n.to_i << 5)
        #: (Registers::Register d, Label label) -> self
        def adr(d, label) = emit(Adr.new(d, label))
        #: (Label label, Label base) -> self
        def table_word(label, base) = emit(TableWord.new(label, base))
        #: (?Registers::Register n) -> self
        def ret(n = X30) = emit(0xD65F_0000 | n.to_i << 5)
        #: (Registers::Register rt, target label) -> self
        def cbz(rt, label) = branch(0x3400_0000 | rt.sf << 31 | rt.to_i, label, 5, 19)
        #: (Registers::Register rt, target label) -> self
        def cbnz(rt, label) = branch(0x3500_0000 | rt.sf << 31 | rt.to_i, label, 5, 19)
        # `tbz`/`tbnz rt, #bit, label`: the bit's high digit is the width bit.
        #: (Registers::Register rt, Integer bit, target label) -> self
        def tbz(rt, bit, label) = test_bit(0x3600_0000, rt, bit, label)
        #: (Registers::Register rt, Integer bit, target label) -> self
        def tbnz(rt, bit, label) = test_bit(0x3700_0000, rt, bit, label)

        # A relocation fills in the page, so the encoded page is zero.
        #: (Registers::Register d, Integer page) -> self
        def adrp(d, page)
          page = Integer(page)
          emit(0x9000_0000 | (page & 0b11) << 29 | (page >> 2 & 0x7FFFF) << 5 | d.to_i)
        end

        private

        #: (word word) -> self
        def emit(word)
          @insns << word
          self
        end

        # Every caller in the repository gives the Symbol key of the table.
        # This runs once per instruction, so it reads the Symbol first and
        # converts the name only as a fallback: `:eq.to_s.downcase.to_sym`
        # makes two Strings for each `cset` and each conditional branch.
        #: (Symbol cond) -> Integer
        def condition(cond)
          CONDITIONS.fetch(cond) { CONDITIONS.fetch(cond.to_s.downcase.to_sym) }
        end

        #: (Integer value, Integer bits) -> Integer
        def unsigned(value, bits)
          raise Refused, "#{value} does not fit a #{bits}-bit field" unless value.between?(0, (1 << bits) - 1)

          value
        end

        # An Integer third operand is an immediate, shifted left twelve when
        # `lsl` is set. A register operand takes an optional shift.
        # An immediate operand shifts by 0 or by 12, the only shift that
        # the instruction has.
        #: (Integer op, Integer s, Registers::Register d, Registers::Register n, operand m, Integer lsl, ?Symbol shift, ?Integer amount) -> self
        def addsub(op, s, d, n, m, lsl, shift = :lsl, amount = 0)
          if m.is_a?(Integer)
            raise Refused, "an immediate add or sub shifts by 0 or 12, not #{lsl}" unless [0, 12].include?(lsl)

            emit(0x1100_0000 | d.sf << 31 | op << 30 | s << 29 | (lsl.zero? ? 0 : 1) << 22 |
                 unsigned(m, 12) << 10 | n.to_i << 5 | d.to_i)
          else
            emit(0x0B00_0000 | d.sf << 31 | op << 30 | s << 29 | SHIFTS.fetch(shift) << 22 |
                 m.to_i << 16 | unsigned(amount, 6) << 10 | n.to_i << 5 | d.to_i)
          end
        end

        # A register third operand, or a bitmask immediate, which is a
        # different instruction family with the same name.
        #
        # The Integer branch must come first and must be here.
        # `Integer#to_i` exists, so without this branch `and d, a, 7`
        # encodes as `and d, a, x7` with no error.
        #: (Integer opc, Registers::Register d, Registers::Register n, operand m) -> self
        def logical(opc, d, n, m)
          return logical_immediate(opc, d, n, m) if m.is_a?(Integer)

          emit(0x0A00_0000 | d.sf << 31 | opc << 29 | m.to_i << 16 | n.to_i << 5 | d.to_i)
        end

        #: (Integer opc, Registers::Register d, Registers::Register n, Integer m) -> self
        def logical_immediate(opc, d, n, m)
          bit, immr, imms = self.class.bitmask(m, d.size) || raise(Refused, "#{m} is not a bitmask immediate")
          emit(0x1200_0000 | d.sf << 31 | opc << 29 | bit << 22 | immr << 16 | imms << 10 | n.to_i << 5 | d.to_i)
        end

        # arm64 cannot encode a shift larger than the register: the
        # field has the width of the register and contains nothing else.
        #: (Registers::Register d, Integer m) -> Integer
        def shift(d, m)
          raise Refused, "a shift of #{m} in #{d.size} bits" unless m.between?(0, d.size - 1)

          m
        end

        #: (Integer op2, Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def variable_shift(op2, d, n, m)
          emit(0x1AC0_2000 | d.sf << 31 | m.to_i << 16 | op2 << 10 | n.to_i << 5 | d.to_i)
        end

        #: (Integer sub, Registers::Register d, Registers::Register n, Registers::Register m, Registers::Register a) -> self
        def multiply(sub, d, n, m, a)
          emit(0x1B00_0000 | d.sf << 31 | m.to_i << 16 | sub << 15 | a.to_i << 10 | n.to_i << 5 | d.to_i)
        end

        #: (Integer signed, Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def divide(signed, d, n, m)
          emit(0x1AC0_0800 | d.sf << 31 | m.to_i << 16 | signed << 10 | n.to_i << 5 | d.to_i)
        end

        #: (Integer opc, Registers::Register d, Integer value, Integer lsl) -> self
        def move_wide(opc, d, value, lsl)
          emit(0x1280_0000 | d.sf << 31 | opc << 29 | (lsl / 16) << 21 | unsigned(value, 16) << 5 | d.to_i)
        end

        #: (Registers::Register d, Registers::Register n, Integer immr, Integer imms) -> self
        def sbfm(d, n, immr, imms) = bitfield(0b00, d, n, immr, imms)
        #: (Registers::Register d, Registers::Register n, Integer immr, Integer imms) -> self
        def ubfm(d, n, immr, imms) = bitfield(0b10, d, n, immr, imms)

        # The N bit repeats the operand size, as every bitfield form does.
        #: (Integer opc, Registers::Register d, Registers::Register n, Integer immr, Integer imms) -> self
        def bitfield(opc, d, n, immr, imms)
          emit(0x1300_0000 | d.sf << 31 | opc << 29 | d.sf << 22 | unsigned(immr, 6) << 16 |
               unsigned(imms, 6) << 10 | n.to_i << 5 | d.to_i)
        end

        #: (Integer base, Registers::Register d, Registers::Register n, Registers::Register m) -> self
        def float3(base, d, n, m) = emit(base | m.to_i << 16 | n.to_i << 5 | d.to_i)
        #: (Integer base, Registers::Register d, Registers::Register n) -> self
        def float2(base, d, n) = emit(base | n.to_i << 5 | d.to_i)

        # `ldr`/`str d, [base, #off]`, the offset unsigned and scaled by 8.
        #: (Integer load, Registers::Register rt, address address) -> self
        def float_load_store(load, rt, address)
          base, off = address
          off = off.to_i
          raise Refused, "an offset of #{off} for an 8-byte access" unless off >= 0 && (off % 8).zero?

          emit(0xFD00_0000 | load << 22 | unsigned(off / 8, 12) << 10 | base.to_i << 5 | rt.to_i)
        end

        # The unsigned-offset form: the offset counts whole accesses.
        #: (Integer size, Integer load, Registers::Register rt, address address) -> self
        def load_store(size, load, rt, address)
          base, off = address
          off = off.to_i
          scale = 1 << size
          raise Refused, "an offset of #{off} for a #{scale}-byte access" unless off >= 0 && (off % scale).zero?

          emit(0x3900_0000 | size << 30 | load << 22 | unsigned(off / scale, 12) << 10 | base.to_i << 5 | rt.to_i)
        end

        # `imm` is `:!` for the pre-indexed form and a number for the
        # post-indexed one; without it the offset in `address` is a plain one.
        #: (Integer load, Registers::Register rt1, Registers::Register rt2, address address, (Integer | :!)? imm) -> self
        def pair(load, rt1, rt2, address, imm)
          base, off = address
          variant = 0b010
          case imm
          when nil then nil
          when :! then variant = 0b011
          else
            variant = 0b001
            off = imm
          end
          scale = rt1.wide? ? 8 : 4
          off = off.to_i
          raise Refused, "an offset of #{off} for a #{scale}-byte pair" unless (off % scale).zero?

          # A pair of doubles: the same three forms, with `V` set and `opc` 01.
          if rt1.float?
            return emit(0x6C00_0000 | variant << 23 | load << 22 |
                        self.class.signed(off / scale, 7) << 15 | rt2.to_i << 10 | base.to_i << 5 | rt1.to_i)
          end

          emit(0x2800_0000 | (rt1.wide? ? 0b10 : 0b00) << 30 | variant << 23 | load << 22 |
               self.class.signed(off / scale, 7) << 15 | rt2.to_i << 10 | base.to_i << 5 | rt1.to_i)
        end

        #: (Integer base, Registers::Register rt, Integer bit, target label) -> self
        def test_bit(base, rt, bit, label)
          raise Refused, "a test of bit #{bit}" unless bit.between?(0, 63)

          branch(base | (bit >> 5) << 31 | (bit & 31) << 19 | rt.to_i, label, 5, 14)
        end

        #: (Integer base, target label, Integer shift, Integer bits) -> self
        def branch(base, label, shift, bits)
          return emit(base | self.class.signed(Integer(label), bits) << shift) if label.is_a?(Integer)

          emit(Branch.new(base, label, shift, bits))
        end
      end
    end
  end
end
