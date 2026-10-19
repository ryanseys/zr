# frozen_string_literal: true

require_relative "../native/pools"

module Zr
  module Backend
    module X86_64
      # The sixteen general-purpose registers at each width that the
      # codegen uses (64, 32 and 8 bits), and the sixteen xmm registers.
      # A register's number is its encoding: rax 0, rcx 1, rdx 2, rbx 3,
      # rsp 4, rbp 5, rsi 6, rdi 7, then r8..r15.
      module Registers
        class Register
          attr_reader :to_i #: Integer
          attr_reader :size #: Integer

          #: (Integer number, Integer size, ?float: bool) -> void
          def initialize(number, size, float: false)
            @to_i = number
            @size = size
            @float = float
            freeze
          end

          #: () -> bool
          def wide? = @size == 64
          #: () -> bool
          def float? = @float
          #: () -> bool
          def byte? = @size == 8
          # The register at 32 bits and at 8 bits.
          #: () -> Register
          def w = Registers::GPR32.fetch(@to_i)
          #: () -> Register
          def b = Registers::GPR8.fetch(@to_i)
          #: () -> Register
          def q = Registers::GPR64.fetch(@to_i)

          NAMES = %w[rax rcx rdx rbx rsp rbp rsi rdi].freeze #: Array[String]

          #: () -> String
          def name
            return "xmm#{@to_i}" if @float

            base = NAMES[@to_i]
            case @size
            when 64 then base || "r#{@to_i}"
            when 32 then base ? "e#{base[1..]}" : "r#{@to_i}d"
            else base ? %w[al cl dl bl spl bpl sil dil][@to_i] : "r#{@to_i}b"
            end
          end

          alias inspect name
        end

        GPR64 = Array.new(16) { |n| Register.new(n, 64) }.freeze #: Array[Register]
        GPR32 = Array.new(16) { |n| Register.new(n, 32) }.freeze #: Array[Register]
        GPR8 = Array.new(16) { |n| Register.new(n, 8) }.freeze #: Array[Register]
        XMM = Array.new(16) { |n| Register.new(n, 64, float: true) }.freeze #: Array[Register]

        RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15 = GPR64
        XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7 = XMM

        # The integer argument registers of the System V ABI, in order.
        ARGS = [RDI, RSI, RDX, RCX, R8, R9].freeze #: Array[Register]

        # What the register allocator gives out (`Native::Regalloc`): the
        # callee-saved rbx and r12..r15, and the caller-saved rdi, rsi, r8
        # and r9. The codegen keeps rax, rcx (shift counts), rdx (division)
        # and r10, r11 for itself, and rbp holds the frame.
        POOLS = Native::Pools.new(callee: [RBX, R12, R13, R14, R15], caller_saved: [RDI, RSI, R8, R9], args: ARGS) #: Native::Pools
      end
    end
  end
end
