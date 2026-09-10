# frozen_string_literal: true

module Ze0
  module Machine
    module Aarch64
      # The general-purpose registers. Register 31 reads as the stack
      # pointer in one family of encodings and as the zero register in the
      # other, so the two are separate objects that share a number.
      module Registers
        class Register
          attr_reader :to_i

          def initialize(number, wide, sp)
            @to_i = number
            @wide = wide
            @sp = sp
            freeze
          end

          def wide? = @wide
          def sp? = @sp
          def sf = @wide ? 1 : 0
          def size = @wide ? 64 : 32
          def zr = @wide ? XZR : WZR
          def name
            return @wide ? "SP" : "WSP" if @sp
            return @wide ? "XZR" : "WZR" if @to_i == 31

            "#{@wide ? "X" : "W"}#{@to_i}"
          end

          alias inspect name
        end

        31.times do |i|
          const_set(:"X#{i}", Register.new(i, true, false))
          const_set(:"W#{i}", Register.new(i, false, false))
        end

        SP = Register.new(31, true, true)
        WSP = Register.new(31, false, true)
        XZR = Register.new(31, true, false)
        WZR = Register.new(31, false, false)
      end
    end
  end
end
