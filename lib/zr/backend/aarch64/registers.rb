# frozen_string_literal: true

require_relative "../native/pools"

module Zr
  module Backend
    module Aarch64
      # The general-purpose registers, and the SIMD&FP registers as
      # doubles. Register 31 reads as the stack pointer in one family of
      # encodings and as the zero register in the other, so the two are
      # separate objects that share a number.
      module Registers
        class Register
          # @rbs @wide: bool
          # @rbs @sp: bool
          # @rbs @float: bool

          attr_reader :to_i #: Integer

          #: (Integer number, wide: bool, ?sp: bool, ?float: bool) -> void
          def initialize(number, wide:, sp: false, float: false)
            @to_i = number
            @wide = wide
            @sp = sp
            @float = float
            freeze
          end

          #: () -> bool
          def wide? = @wide
          #: () -> bool
          def sp? = @sp
          #: () -> bool
          def float? = @float
          #: () -> Integer
          def sf = @wide ? 1 : 0
          #: () -> Integer
          def size = @wide ? 64 : 32
          #: () -> Register
          def zr = @wide ? XZR : WZR
          #: () -> String
          def name
            return "D#{@to_i}" if @float
            return @wide ? "SP" : "WSP" if @sp
            return @wide ? "XZR" : "WZR" if @to_i == 31

            "#{@wide ? "X" : "W"}#{@to_i}"
          end

          alias inspect name
        end

        31.times do |i|
          const_set(:"X#{i}", Register.new(i, wide: true))
          const_set(:"W#{i}", Register.new(i, wide: false))
        end
        32.times { |i| const_set(:"D#{i}", Register.new(i, wide: true, float: true)) }

        module_function

        # The registers by number, for a loop that counts over slots.
        # const_get takes a computed name, so Steep cannot type it.
        #: (Integer i) -> Register
        def x(i) = const_get(:"X#{i}") # steep:ignore
        #: (Integer i) -> Register
        def w(i) = const_get(:"W#{i}") # steep:ignore
        #: (Integer i) -> Register
        def d(i) = const_get(:"D#{i}") # steep:ignore

        SP = Register.new(31, wide: true, sp: true)
        WSP = Register.new(31, wide: false, sp: true)
        XZR = Register.new(31, wide: true)
        WZR = Register.new(31, wide: false)

        # What the register allocator gives out (`Native::Regalloc`): the
        # callee-saved `x19`..`x27`, and the caller-saved ones that no
        # lowering keeps for itself, with the argument registers among
        # them. The codegen keeps `x9`..`x12` for scratch, `x16` and `x17`
        # are the linker's, and `x18` is the platform's.
        POOLS = Native::Pools.new(callee: [X19, X20, X21, X22, X23, X24, X25, X26, X27],
                                  caller: [X0, X1, X2, X3, X4, X5, X6, X7, X8, X13, X14, X15],
                                  args: [X0, X1, X2, X3, X4, X5, X6, X7]) #: Native::Pools
        # The program's gate word: a `gates` value reads it and gets no
        # register.
        GATES = X28 #: Register
      end
    end
  end
end
