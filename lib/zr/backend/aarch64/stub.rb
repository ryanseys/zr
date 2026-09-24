# frozen_string_literal: true

require_relative "registers"
require_relative "assembler"
require_relative "../../obj/model"

module Zr
  module Backend
    module Aarch64
      # The functions that the machine dialect cannot express. This file
      # assembles their machine code and gives it as raw bytes to every target path.
      module Stub
        include Registers

        # The context `zr_switch` saves and restores: the callee-saved
        # registers x19..x27, the frame pair x29 and x30, sp, and d8..d15.
        # Not x28: it contains the gate word. The gate word belongs to the
        # whole program, not to one stack. Thus a switch does not change it,
        # and a resumed stack sees the current gates.
        CONTEXT = { x19: 0, x21: 16, x23: 32, x25: 48, x27: 64, x29: 80, x30: 88, sp: 96, d8: 104 }.freeze
        CONTEXT_BYTES = 176

        module_function

        # `zr_switch(from: Ptr, to: Ptr)`: saves this stack in `from`, and
        # resumes the stack in `to`. A new context needs only x30 (the start
        # address) and sp (its stack top).
        def switch(assembler: Assembler)
          a = assembler.new
          pairs = [[X19, X20], [X21, X22], [X23, X24], [X25, X26], [X29, X30]]
          at = [0, 16, 32, 48, CONTEXT[:x29]]
          doubles = [[D8, D9], [D10, D11], [D12, D13], [D14, D15]]
          pairs.each_with_index { |(p, q), i| a.stp p, q, [X0, at[i]] }
          a.str X27, [X0, CONTEXT[:x27]]
          a.mov X9, SP
          doubles.each_with_index { |(p, q), i| a.stp p, q, [X0, CONTEXT[:d8] + (16 * i)] }
          a.str X9, [X0, CONTEXT[:sp]]
          pairs.each_with_index { |(p, q), i| a.ldp p, q, [X1, at[i]] }
          a.ldr X27, [X1, CONTEXT[:x27]]
          a.ldr X9, [X1, CONTEXT[:sp]]
          a.mov SP, X9
          doubles.each_with_index { |(p, q), i| a.ldp p, q, [X1, CONTEXT[:d8] + (16 * i)] }
          a.ret
          Obj::Function.new("zr_switch", a.to_binary, align: 4)
        end

        ALL = { "zr_switch" => [[:Ptr, :Ptr], :Void] }.freeze
      end
    end
  end
end
