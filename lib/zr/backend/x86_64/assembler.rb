# frozen_string_literal: true

require_relative "registers"
require_relative "../../refused"

module Zr
  module Backend
    module X86_64
      # An x86-64 encoder for only the forms that the codegen and the
      # stubs emit. Code is a byte string; a label is a byte offset, and
      # every branch to a label takes a 32-bit displacement, which
      # `to_binary` fills in once each label has its place.
      #
      # A memory operand is `[base, disp]` or `[base, disp, index, scale]`
      # with 64-bit registers and a signed 32-bit displacement. A form
      # whose name ends in `_rip` addresses `[rip + disp32]`: the caller's
      # block gets the offset of the displacement, where a relocation goes.
      class Assembler
        # @rbs @code: String
        # @rbs @fixups: Array[[Integer, Label, Label?]]

        include Registers

        class Refused < StandardError
          include Zr::Refusal
        end
        # A branch whose target is out of reach. Every branch here takes
        # 32 bits, so a function would need 2 GiB of code.
        class OutOfReach < Refused; end

        # The condition codes, as the low nibble of `jcc`, `setcc` and
        # `cmovcc`.
        CONDITIONS = {
          o: 0x0, no: 0x1, b: 0x2, ae: 0x3, e: 0x4, ne: 0x5, be: 0x6, a: 0x7,
          s: 0x8, ns: 0x9, p: 0xA, np: 0xB, l: 0xC, ge: 0xD, le: 0xE, g: 0xF
        }.freeze #: Hash[Symbol, Integer]

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

        #: () -> void
        def initialize
          @code = +"".b
          @fixups = []
        end

        #: (String name) -> Label
        def make_label(name) = Label.new(name)

        #: (Label label) -> self
        def put_label(label)
          label.at_offset(@code.bytesize)
          self
        end

        # The byte offset of the next byte.
        #: [T] () { (Integer) -> T } -> T
        def patch_location
          yield @code.bytesize
        end

        #: () -> Integer
        def size = @code.bytesize

        #: () -> String
        def to_binary
          out = @code.dup
          @fixups.each do |at, label, base|
            value = base ? label.to_i - base.to_i : label.to_i - (at + 4)
            out[at, 4] = [value].pack("l<")
          end
          out
        end

        # --- moves --------------------------------------------------------

        # `mov d, s` between registers of one width, or from an xmm
        # register to a general one and back (`movq`).
        #: (Registers::Register d, Registers::Register s) -> self
        def mov(d, s)
          return movq(d, s) if d.float? || s.float?
          return self if d.equal?(s)

          rr(d.byte? ? [0x88] : [0x89], s, d, w: d.wide?, byte: d.byte?)
        end

        # `d = n`: a 32-bit move for a value that fits 32 unsigned bits,
        # which clears the high half; a sign-extended 32-bit move; or
        # `movabs`. None of them writes the flags.
        #: (Registers::Register d, Integer n) -> self
        def mov_imm(d, n)
          n &= (1 << 64) - 1
          if n < 1 << 32
            rex(false, 0, 0, d.to_i)
            byte(0xB8 + (d.to_i & 7))
            imm32(n)
          elsif n >= (1 << 64) - (1 << 31)
            rr([0xC7], 0, d, w: true)
            imm32(n - (1 << 64))
          else
            rex(true, 0, 0, d.to_i)
            byte(0xB8 + (d.to_i & 7))
            @code << [n].pack("Q<")
            self
          end
        end

        # A load of `d`'s width; an 8-bit load zero-extends into the 32-bit
        # register.
        #: (Registers::Register d, untyped mem) -> self
        def ld(d, mem)
          return movsd_load(d, mem) if d.float?
          return rm([0x0F, 0xB6], d, mem, w: false) if d.byte?

          rm([0x8B], d, mem, w: d.wide?)
        end

        #: (untyped mem, Registers::Register s) -> self
        def store(mem, s)
          return movsd_store(mem, s) if s.float?

          rm(s.byte? ? [0x88] : [0x89], s, mem, w: s.wide?, byte: s.byte?)
        end

        # `mov qword [mem], simm32`.
        #: (untyped mem, Integer n) -> self
        def store_imm(mem, n)
          rm([0xC7], 0, mem, w: true)
          imm32(n)
        end

        #: (Registers::Register d, untyped mem) -> self
        def lea(d, mem) = rm([0x8D], d, mem, w: true)

        # `movzx d32, s8`.
        #: (Registers::Register d, Registers::Register s) -> self
        def movzx8(d, s) = rr([0x0F, 0xB6], d, s, w: false, byte: true)
        # `movsx d64, s8` and `movsxd d64, s32`.
        #: (Registers::Register d, Registers::Register s) -> self
        def movsx8(d, s) = rr([0x0F, 0xBE], d, s, w: true, byte: true)
        #: (Registers::Register d, Registers::Register s) -> self
        def movsxd(d, s) = rr([0x63], d, s, w: true)
        # `movsxd d64, dword [mem]`.
        #: (Registers::Register d, untyped mem) -> self
        def movsxd_load(d, mem) = rm([0x63], d, mem, w: true)

        # `lea d, [rip + disp32]`.
        #: (Registers::Register d) { (Integer) -> void } -> self
        def lea_rip(d, &) = rip([0x8D], d, w: true, &)
        # `mov d, [rip + disp32]`.
        #: (Registers::Register d) { (Integer) -> void } -> self
        def load_rip(d, &) = rip([0x8B], d, w: d.wide?, &)

        # --- arithmetic ---------------------------------------------------

        # The opcode of the r/m, reg form and the /digit of the immediate form.
        ALU = { add: [0x01, 0], or: [0x09, 1], and: [0x21, 4],
                sub: [0x29, 5], xor: [0x31, 6], cmp: [0x39, 7] }.freeze #: Hash[Symbol, [Integer, Integer]]

        ALU.each do |op, (opcode, digit)|
          # `op d, s` of two registers (8-bit ones too), or of a register
          # and a signed 32-bit immediate.
          define_method(op) do |d, s|
            if s.is_a?(Integer)
              if s.between?(-128, 127)
                rr([0x83], digit, d, w: d.wide?)
                byte(s & 0xFF)
              else
                rr([0x81], digit, d, w: d.wide?)
                imm32(s)
              end
            elsif d.byte?
              rr([opcode - 1], s, d, w: false, byte: true)
            else
              rr([opcode], s, d, w: d.wide?)
            end
          end
        end

        #: (Registers::Register d, Registers::Register | Integer s) -> self
        def tst(d, s)
          return rr([0x85], s, d, w: d.wide?) unless s.is_a?(Integer)

          rr([0xF7], 0, d, w: d.wide?)
          imm32(s)
        end

        # `imul d, s` or `imul d, s, imm32`.
        #: (Registers::Register d, Registers::Register s, ?Integer? k) -> self
        def imul(d, s, k = nil)
          return rr([0x0F, 0xAF], d, s, w: d.wide?) unless k

          rr([0x69], d, s, w: d.wide?)
          imm32(k)
        end

        SHIFTS = { shl: 4, shr: 5, sar: 7 }.freeze #: Hash[Symbol, Integer]

        SHIFTS.each do |op, digit|
          # A shift by an immediate, or by `cl` with `:cl`.
          define_method(op) do |d, by|
            if by == :cl
              rr([0xD3], digit, d, w: d.wide?)
            else
              rr([0xC1], digit, d, w: d.wide?)
              byte(by)
            end
          end
        end

        #: (Registers::Register d) -> self
        def neg(d) = rr([0xF7], 3, d, w: d.wide?)
        # `div s` and `idiv s`: rdx:rax by `s`.
        #: (Registers::Register s) -> self
        def div(s) = rr([0xF7], 6, s, w: s.wide?)
        #: (Registers::Register s) -> self
        def idiv(s) = rr([0xF7], 7, s, w: s.wide?)
        # The sign of rax into rdx, at 64 (`cqo`) or 32 (`cdq`) bits.
        #: (bool wide) -> self
        def sign_extend_rax(wide)
          byte(0x48) if wide
          byte(0x99)
        end

        # --- bits ---------------------------------------------------------

        BIT_TESTS = { bt: 4, bts: 5, btr: 6, btc: 7 }.freeze #: Hash[Symbol, Integer]

        BIT_TESTS.each do |op, digit|
          # A test of bit `n` into CF, and a set, clear or flip of it.
          define_method(op) do |d, n|
            rr([0x0F, 0xBA], digit, d, w: d.wide?)
            byte(n)
          end
        end

        #: (Registers::Register d, Registers::Register s) -> self
        def bsf(d, s) = rr([0x0F, 0xBC], d, s, w: d.wide?)
        #: (Registers::Register d, Registers::Register s) -> self
        def bsr(d, s) = rr([0x0F, 0xBD], d, s, w: d.wide?)
        #: (Registers::Register d, Registers::Register s) -> self
        def popcnt(d, s) = rr([0x0F, 0xB8], d, s, w: d.wide?, prefix: 0xF3)

        #: (Registers::Register d) -> self
        def bswap(d)
          rex(d.wide?, 0, 0, d.to_i)
          bytes(0x0F, 0xC8 + (d.to_i & 7))
        end

        # `cmovcc d, s`.
        #: (Symbol cond, Registers::Register d, Registers::Register s) -> self
        def cmov(cond, d, s) = rr([0x0F, 0x40 | CONDITIONS.fetch(cond)], d, s, w: d.wide?)

        # `setcc d8`.
        #: (Symbol cond, Registers::Register d) -> self
        def set(cond, d) = rr([0x0F, 0x90 | CONDITIONS.fetch(cond)], 0, d.b, w: false, byte: true)

        # --- branches -----------------------------------------------------

        #: (Label label) -> self
        def jmp(label)
          byte(0xE9)
          rel32(label)
        end

        #: (Symbol cond, Label label) -> self
        def j(cond, label)
          bytes(0x0F, 0x80 | CONDITIONS.fetch(cond))
          rel32(label)
        end

        # `call rel32` to a symbol: the block gets the displacement's offset.
        #: () { (Integer) -> void } -> self
        def call_rel
          byte(0xE8)
          yield @code.bytesize
          imm32(0)
        end

        #: (Registers::Register s) -> self
        def call_reg(s) = rr([0xFF], 2, s, w: false)
        #: (Registers::Register s) -> self
        def jmp_reg(s) = rr([0xFF], 4, s, w: false)
        #: () -> self
        def ret = byte(0xC3)

        #: (Registers::Register s) -> self
        def push(s)
          rex(false, 0, 0, s.to_i)
          byte(0x50 + (s.to_i & 7))
        end

        #: (Registers::Register d) -> self
        def pop(d)
          rex(false, 0, 0, d.to_i)
          byte(0x58 + (d.to_i & 7))
        end

        # One word of a jump table: the distance from `base` to `label`.
        #: (Label label, Label base) -> self
        def table_word(label, base)
          @fixups << [@code.bytesize, label, base]
          imm32(0)
        end

        # `lea d, [rip + label]`.
        #: (Registers::Register d, Label label) -> self
        def lea_label(d, label)
          rex(true, d.to_i, 0, 0)
          bytes(0x8D, 0x05 | ((d.to_i & 7) << 3))
          rel32(label)
        end

        # --- floats -------------------------------------------------------

        # `movq` between a general register and an xmm register.
        #: (Registers::Register d, Registers::Register s) -> self
        def movq(d, s)
          return rr([0x0F, 0x6E], d, s, w: true, prefix: 0x66) if d.float?

          rr([0x0F, 0x7E], s, d, w: true, prefix: 0x66)
        end

        SSE = { addsd: 0x58, mulsd: 0x59, subsd: 0x5C, divsd: 0x5E, sqrtsd: 0x51 }.freeze #: Hash[Symbol, Integer]

        SSE.each do |op, opcode|
          define_method(op) { |d, s| rr([0x0F, opcode], d, s, w: false, prefix: 0xF2) }
        end

        #: (Registers::Register a, Registers::Register b) -> self
        def ucomisd(a, b) = rr([0x0F, 0x2E], a, b, w: false, prefix: 0x66)
        # `cvtsi2sd xmm, r`, from a 64- or 32-bit register.
        #: (Registers::Register d, Registers::Register s) -> self
        def cvtsi2sd(d, s) = rr([0x0F, 0x2A], d, s, w: s.wide?, prefix: 0xF2)
        # `cvttsd2si r64, xmm`.
        #: (Registers::Register d, Registers::Register s) -> self
        def cvttsd2si(d, s) = rr([0x0F, 0x2C], d, s, w: true, prefix: 0xF2)

        # `roundsd d, s, mode`: 8 to nearest even, 9 down, 10 up, 11 toward
        # zero, each without the precision exception.
        #: (Registers::Register d, Registers::Register s, Integer mode) -> self
        def roundsd(d, s, mode)
          rr([0x0F, 0x3A, 0x0B], d, s, w: false, prefix: 0x66)
          byte(mode)
        end

        #: (Registers::Register d, untyped mem) -> self
        def movsd_load(d, mem) = rm([0x0F, 0x10], d, mem, w: false, prefix: 0xF2)
        #: (untyped mem, Registers::Register s) -> self
        def movsd_store(mem, s) = rm([0x0F, 0x11], s, mem, w: false, prefix: 0xF2)

        # `stmxcsr [mem]`, `ldmxcsr [mem]`, `fnstcw [mem]` and `fldcw [mem]`.
        #: (untyped mem) -> self
        def stmxcsr(mem) = rm([0x0F, 0xAE], 3, mem, w: false)
        #: (untyped mem) -> self
        def ldmxcsr(mem) = rm([0x0F, 0xAE], 2, mem, w: false)
        #: (untyped mem) -> self
        def fnstcw(mem) = rm([0xD9], 7, mem, w: false)
        #: (untyped mem) -> self
        def fldcw(mem) = rm([0xD9], 5, mem, w: false)

        private

        #: (Integer b) -> self
        def byte(b)
          @code << (b & 0xFF)
          self
        end

        #: (*Integer list) -> self
        def bytes(*list)
          list.each { |b| @code << b }
          self
        end

        #: (Integer n) -> self
        def imm32(n)
          raise Refused, "#{n} does not fit 32 bits" unless n.between?(-(1 << 31), (1 << 32) - 1)

          @code << [n & 0xFFFF_FFFF].pack("L<")
          self
        end

        #: (Label label) -> self
        def rel32(label)
          @fixups << [@code.bytesize, label, nil]
          imm32(0)
        end

        # A REX prefix when one is needed: a 64-bit operand, a register
        # from r8 up in a field, or (`byte`) spl, bpl, sil or dil. An
        # empty REX before a form with no byte register changes nothing.
        #: (bool w, Integer r, Integer x, Integer b, ?byte: bool) -> void
        def rex(w, r, x, b, byte: false)
          bits = (w ? 8 : 0) | ((r >> 3) << 2) | ((x >> 3) << 1) | (b >> 3)
          @code << (0x40 | bits) if bits.positive? || (byte && (r.between?(4, 7) || b.between?(4, 7)))
        end

        # A register-direct form: `reg` (a register or a /digit) in ModRM's
        # reg field and the register `rm` in its r/m field.
        #: (Array[Integer] opcode, Registers::Register | Integer reg, Registers::Register rm, w: bool, ?byte: bool, ?prefix: Integer?) -> self
        def rr(opcode, reg, rm, w:, byte: false, prefix: nil)
          r = reg.is_a?(Integer) ? reg : reg.to_i
          @code << prefix if prefix
          rex(w, r, 0, rm.to_i, byte: byte)
          opcode.each { |o| @code << o }
          @code << (0xC0 | ((r & 7) << 3) | (rm.to_i & 7))
          self
        end

        # A memory form: `reg` in ModRM's reg field, and `[base + disp]` or
        # `[base + index * scale + disp]`.
        #: (Array[Integer] opcode, Registers::Register | Integer reg, untyped mem, w: bool, ?byte: bool, ?prefix: Integer?) -> self
        def rm(opcode, reg, mem, w:, byte: false, prefix: nil)
          base, disp, index, scale = mem
          r = reg.is_a?(Integer) ? reg : reg.to_i
          x = index ? index.to_i : 0
          @code << prefix if prefix
          rex(w, r, x, base.to_i, byte: byte)
          opcode.each { |o| @code << o }
          b = base.to_i & 7
          mod = if disp.zero? && b != 5 then 0
                elsif disp.between?(-128, 127) then 1
                else 2
                end
          if index || b == 4
            @code << ((mod << 6) | ((r & 7) << 3) | 4)
            ss = { nil => 0, 1 => 0, 2 => 1, 4 => 2, 8 => 3 }.fetch(scale)
            @code << ((ss << 6) | (index ? (x & 7) << 3 : 4 << 3) | b)
          else
            @code << ((mod << 6) | ((r & 7) << 3) | b)
          end
          if mod == 1
            @code << (disp & 0xFF)
          elsif mod == 2
            imm32(disp)
          end
          self
        end

        # A `[rip + disp32]` form. The block gets the displacement's offset,
        # which is the instruction's last four bytes.
        #: (Array[Integer] opcode, Registers::Register reg, w: bool) { (Integer) -> void } -> self
        def rip(opcode, reg, w:)
          rex(w, reg.to_i, 0, 0)
          opcode.each { |o| @code << o }
          @code << (0x05 | ((reg.to_i & 7) << 3))
          yield @code.bytesize
          imm32(0)
        end
      end
    end
  end
end
