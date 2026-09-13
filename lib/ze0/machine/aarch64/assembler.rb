# frozen_string_literal: true

require_relative "registers"

module Ze0
  module Machine
    module Aarch64
      # An arm64 encoder: the instructions the two backends emit, and
      # nothing else. An instruction is a word, or an object that answers
      # `encode` with its own index once every label has a place.
      #
      # A label holds an instruction index, not a byte offset, so a branch
      # encodes its distance as `target - here`.
      class Assembler
        include Registers

        class Refused < StandardError; end

        CONDITIONS = {
          eq: 0b0000, ne: 0b0001, cs: 0b0010, hs: 0b0010, cc: 0b0011, lo: 0b0011,
          mi: 0b0100, pl: 0b0101, vs: 0b0110, vc: 0b0111, hi: 0b1000, ls: 0b1001,
          ge: 0b1010, lt: 0b1011, gt: 0b1100, le: 0b1101, al: 0b1110
        }.freeze
        SHIFTS = { lsl: 0b00, lsr: 0b01, asr: 0b10 }.freeze

        class Label
          attr_reader :name, :offset

          def initialize(name)
            @name = name
            @offset = nil
          end

          def set_offset(offset)
            @offset = offset
            self
          end

          def to_i = @offset || raise(Refused, "the label #{@name} has no place")
        end

        # A branch whose distance is known only when every instruction has
        # an index.
        Branch = Struct.new(:base, :label, :shift, :bits) do
          def encode(at)
            base | (Assembler.signed(label.to_i - at, bits) << shift)
          end
        end

        # `[N, immr, imms]` for a logical immediate, or nil for a value
        # arm64 cannot name in one word.
        #
        # The only constants `AND`, `ORR` and `EOR` take are a run of
        # ones, rotated, in an element of 2, 4, 8, 16, 32 or 64 bits that
        # repeats to fill the register -- 0x5555555555555555 is one, 5 is
        # not. All ones and no ones are excluded: every element would
        # encode them, so the encoding gives their place to `N`.
        #
        # Memoized, and one table a width rather than one keyed by both:
        # a compiler asks the same handful of questions about the same
        # handful of masks a few million times, and a pair key would
        # make an Array at every one of them. A value that is no bitmask
        # memoizes as nil and is not asked again.
        def self.bitmask(value, width)
          (width == 64 ? BITMASK64 : BITMASK32)[value]
        end

        BITMASK64 = Hash.new { |memo, value| memo[value] = encode_bitmask(value, 64) }
        BITMASK32 = Hash.new { |memo, value| memo[value] = encode_bitmask(value, 32) }

        def self.encode_bitmask(value, width)
          full = (1 << width) - 1
          value &= full
          return nil if value.zero? || value == full

          # The smallest element that repeats: halve while the two halves
          # of the element agree.
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

          # The rotation that brings the run down to bit zero, if the
          # element is one run at all: `x & (x + 1)` is zero exactly for
          # a value that is all ones below some bit and nothing above.
          rotation = (0...size).find { |r| (t = rotated(value, r, size, element)) & (t + 1) == 0 }
          return nil if rotation.nil?

          # `immr` says how far to rotate the run right to make the value,
          # which is the other way round from how it was found.
          length = rotated(value, rotation, size, element).bit_length
          [size == 64 ? 1 : 0, (size - rotation) % size, (~(size - 1) << 1 & 0x3F) | (length - 1)]
        end

        def self.rotated(value, by, size, element) = ((value >> by) | (value << (size - by))) & element

        def self.signed(value, bits)
          limit = 1 << (bits - 1)
          raise Refused, "#{value} does not fit a signed #{bits}-bit field" unless value.between?(-limit, limit - 1)

          value & ((1 << bits) - 1)
        end

        def initialize
          @insns = []
        end

        def make_label(name) = Label.new(name)

        def put_label(label)
          label.set_offset(@insns.length)
          self
        end

        # The byte offset the next instruction takes, which is where a
        # relocation on it points.
        def patch_location
          yield @insns.length * 4
        end

        def <<(word)
          @insns << word
          self
        end

        def to_binary
          @insns.map.with_index { |w, at| w.is_a?(Integer) ? w : w.encode(at) }.pack("L<*")
        end

        # --- arithmetic ---------------------------------------------------

        def add(d, n, m, lsl: 0) = addsub(0, 0, d, n, m, lsl)
        def adds(d, n, m) = addsub(0, 1, d, n, m, 0)
        def sub(d, n, m, lsl: 0) = addsub(1, 0, d, n, m, lsl)
        def subs(d, n, m, shift: :lsl, amount: 0) = addsub(1, 1, d, n, m, 0, shift, amount)
        def cmp(n, m, shift: :lsl, amount: 0) = subs(n.zr, n, m, shift: shift, amount: amount)

        def mul(d, n, m) = madd(d, n, m, d.zr)
        def madd(d, n, m, a) = multiply(0, d, n, m, a)
        def msub(d, n, m, a) = multiply(1, d, n, m, a)
        def smulh(d, n, m) = emit(0x9B40_7C00 | m.to_i << 16 | n.to_i << 5 | d.to_i)
        def udiv(d, n, m) = divide(0, d, n, m)
        def sdiv(d, n, m) = divide(1, d, n, m)

        # --- bits ---------------------------------------------------------

        def and(d, n, m) = logical(0b00, d, n, m)
        def orr(d, n, m) = logical(0b01, d, n, m)
        def eor(d, n, m) = logical(0b10, d, n, m)
        # A register amount shifts by whatever it holds; an Integer one
        # is a bitfield move, which is what arm64 calls these by. The
        # signatures are the gem's, so `aarch64_test` holds both forms to
        # the ARM specification.
        def lsl(d, n, m) = m.is_a?(Integer) ? ubfm(d, n, (d.size - shift(d, m)) % d.size, d.size - 1 - m) : variable_shift(0b00, d, n, m)
        def lsr(d, n, m) = m.is_a?(Integer) ? ubfm(d, n, shift(d, m), d.size - 1) : variable_shift(0b01, d, n, m)
        def asr(d, n, m) = m.is_a?(Integer) ? sbfm(d, n, shift(d, m), d.size - 1) : variable_shift(0b10, d, n, m)

        # `SXTB` and `SXTW` are `SBFM` over a fixed range of bits, and
        # `UXTB` is `UBFM` over the same range.
        def sxtb(d, n) = sbfm(d, n, 0, 7)
        def sxtw(d, n) = sbfm(d, n, 0, 31)
        def uxtb(d, n) = ubfm(d, n, 0, 7)

        # --- moves --------------------------------------------------------

        # The stack pointer has no place in a logical instruction, so a move
        # that names it is an add of nothing.
        def mov(d, m)
          d.sp? || m.sp? ? addsub(0, 0, d, m, 0, 0) : logical(0b01, d, d.zr, m)
        end

        def movz(d, value, lsl: 0) = move_wide(0b10, d, value, lsl)
        def movn(d, value, lsl: 0) = move_wide(0b00, d, value, lsl)
        def movk(d, value, lsl: 0) = move_wide(0b11, d, value, lsl)

        # --- conditions ---------------------------------------------------

        def csel(d, n, m, cond)
          emit(0x1A80_0000 | d.sf << 31 | m.to_i << 16 | condition(cond) << 12 | n.to_i << 5 | d.to_i)
        end

        # `CSET d, cond` is `CSINC d, zr, zr` on the opposite condition.
        def cset(d, cond)
          zr = d.zr.to_i
          emit(0x1A80_0400 | d.sf << 31 | zr << 16 | (condition(cond) ^ 1) << 12 | zr << 5 | d.to_i)
        end

        # --- memory -------------------------------------------------------

        def ldr(rt, address) = load_store(rt.wide? ? 0b11 : 0b10, 1, rt, address)
        def str(rt, address) = load_store(rt.wide? ? 0b11 : 0b10, 0, rt, address)
        def ldrb(rt, address) = load_store(0b00, 1, rt, address)
        def strb(rt, address) = load_store(0b00, 0, rt, address)
        def ldp(rt1, rt2, address, imm = nil) = pair(1, rt1, rt2, address, imm)
        def stp(rt1, rt2, address, imm = nil) = pair(0, rt1, rt2, address, imm)

        # --- control ------------------------------------------------------

        # `B` to a label, or `B.cond` when a condition is named. The
        # signature is the gem's, so `aarch64_test` holds the encoding to
        # the ARM specification like every other one.
        def b(label, cond: nil)
          return branch(0x1400_0000, label, 0, 26) if cond.nil?

          branch(0x5400_0000 | condition(cond), label, 5, 19)
        end
        def bl(label) = branch(0x9400_0000, label, 0, 26)
        def blr(n) = emit(0xD63F_0000 | n.to_i << 5)
        def ret(n = X30) = emit(0xD65F_0000 | n.to_i << 5)
        def cbz(rt, label) = branch(0x3400_0000 | rt.sf << 31 | rt.to_i, label, 5, 19)
        def cbnz(rt, label) = branch(0x3500_0000 | rt.sf << 31 | rt.to_i, label, 5, 19)

        # The page a relocation fills in, so the encoded one is zero.
        def adrp(d, page)
          page = Integer(page)
          emit(0x9000_0000 | (page & 0b11) << 29 | (page >> 2 & 0x7FFFF) << 5 | d.to_i)
        end

        private

        def emit(word)
          @insns << word
          self
        end

        # Every caller inside the repo already holds the Symbol the table
        # is keyed by, and this runs once an instruction: `:eq.to_s.downcase.to_sym`
        # made two Strings and interned one of them, for every `cset` and
        # every conditional branch the backend wrote.
        def condition(cond)
          CONDITIONS.fetch(cond) { CONDITIONS.fetch(cond.to_s.downcase.to_sym) }
        end

        def unsigned(value, bits)
          raise Refused, "#{value} does not fit a #{bits}-bit field" unless value.between?(0, (1 << bits) - 1)

          value
        end

        # An Integer third operand is an immediate, shifted left twelve when
        # `lsl` says so; a register operand takes an optional shift.
        def addsub(op, s, d, n, m, lsl, shift = :lsl, amount = 0)
          if m.is_a?(Integer)
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
        # The Integer branch has to come first and has to be here.
        # `Integer#to_i` answers, so without it `and d, a, 7` encoded as
        # `and d, a, x7` and said nothing.
        def logical(opc, d, n, m)
          return logical_immediate(opc, d, n, m) if m.is_a?(Integer)

          emit(0x0A00_0000 | d.sf << 31 | opc << 29 | m.to_i << 16 | n.to_i << 5 | d.to_i)
        end

        def logical_immediate(opc, d, n, m)
          bit, immr, imms = self.class.bitmask(m, d.size) || raise(Refused, "#{m} is not a bitmask immediate")
          emit(0x1200_0000 | d.sf << 31 | opc << 29 | bit << 22 | immr << 16 | imms << 10 | n.to_i << 5 | d.to_i)
        end

        # A shift out of the register is not a shift arm64 can name:
        # the field is as wide as the register and holds nothing else.
        def shift(d, m)
          raise Refused, "a shift of #{m} in #{d.size} bits" unless m.between?(0, d.size - 1)

          m
        end

        def variable_shift(op2, d, n, m)
          emit(0x1AC0_2000 | d.sf << 31 | m.to_i << 16 | op2 << 10 | n.to_i << 5 | d.to_i)
        end

        def multiply(sub, d, n, m, a)
          emit(0x1B00_0000 | d.sf << 31 | m.to_i << 16 | sub << 15 | a.to_i << 10 | n.to_i << 5 | d.to_i)
        end

        def divide(signed, d, n, m)
          emit(0x1AC0_0800 | d.sf << 31 | m.to_i << 16 | signed << 10 | n.to_i << 5 | d.to_i)
        end

        def move_wide(opc, d, value, lsl)
          emit(0x1280_0000 | d.sf << 31 | opc << 29 | (lsl / 16) << 21 | unsigned(value, 16) << 5 | d.to_i)
        end

        def sbfm(d, n, immr, imms) = bitfield(0b00, d, n, immr, imms)
        def ubfm(d, n, immr, imms) = bitfield(0b10, d, n, immr, imms)

        # The N bit repeats the operand size, as every bitfield form does.
        def bitfield(opc, d, n, immr, imms)
          emit(0x1300_0000 | d.sf << 31 | opc << 29 | d.sf << 22 | unsigned(immr, 6) << 16 |
               unsigned(imms, 6) << 10 | n.to_i << 5 | d.to_i)
        end

        # The unsigned-offset form: the offset counts whole accesses.
        def load_store(size, load, rt, address)
          base, off = address
          off = off.to_i
          scale = 1 << size
          raise Refused, "an offset of #{off} for a #{scale}-byte access" unless off >= 0 && (off % scale).zero?

          emit(0x3900_0000 | size << 30 | load << 22 | unsigned(off / scale, 12) << 10 | base.to_i << 5 | rt.to_i)
        end

        # `imm` is `:!` for the pre-indexed form and a number for the
        # post-indexed one; without it the offset in `address` is a plain one.
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

          emit(0x2800_0000 | (rt1.wide? ? 0b10 : 0b00) << 30 | variant << 23 | load << 22 |
               self.class.signed(off / scale, 7) << 15 | rt2.to_i << 10 | base.to_i << 5 | rt1.to_i)
        end

        def branch(base, label, shift, bits)
          return emit(base | self.class.signed(Integer(label), bits) << shift) if label.is_a?(Integer)

          emit(Branch.new(base, label, shift, bits))
        end
      end
    end
  end
end
