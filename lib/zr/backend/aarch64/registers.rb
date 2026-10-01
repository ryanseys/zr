# frozen_string_literal: true

module Zr
  module Backend
    module Aarch64
      # The general-purpose registers, and the SIMD&FP registers as
      # doubles. Register 31 reads as the stack pointer in one family of
      # encodings and as the zero register in the other, so the two are
      # separate objects that share a number.
      module Registers
        class Register
          attr_reader :to_i

          def initialize(number, wide:, sp: false, float: false)
            @to_i = number
            @wide = wide
            @sp = sp
            @float = float
            freeze
          end

          def wide? = @wide
          def sp? = @sp
          def float? = @float
          def sf = @wide ? 1 : 0
          def size = @wide ? 64 : 32
          def zr = @wide ? XZR : WZR
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
        def x(i) = const_get(:"X#{i}")
        def w(i) = const_get(:"W#{i}")
        def d(i) = const_get(:"D#{i}")

        SP = Register.new(31, wide: true, sp: true)
        WSP = Register.new(31, wide: false, sp: true)
        XZR = Register.new(31, wide: true)
        WZR = Register.new(31, wide: false)
      end
    end
  end
end
