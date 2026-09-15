# frozen_string_literal: true

require_relative "registers"
require_relative "assembler"
require_relative "../../obj/model"

module Ze0
  module Backend
    module Aarch64
      # The functions no dialect can write: machine code assembled here and
      # delivered as raw bytes on every road.
      module Stub
        include Registers

        # The context `zr_switch` saves and restores: the callee-saved
        # registers x19..x28, the frame pair x29 and x30, sp, and d8..d15.
        CONTEXT = { x19: 0, x21: 16, x23: 32, x25: 48, x27: 64, x29: 80, x30: 88, sp: 96, d8: 104 }.freeze
        CONTEXT_BYTES = 176

        module_function

        # `zr_switch(from: Ptr, to: Ptr)`: park this stack in `from`, resume
        # the one `to` holds. A fresh context needs only x30 (where to start)
        # and sp (its stack top).
        def switch(assembler: Assembler)
          a = assembler.new
          pairs = [[X19, X20], [X21, X22], [X23, X24], [X25, X26], [X27, X28], [X29, X30]]
          doubles = [[D8, D9], [D10, D11], [D12, D13], [D14, D15]]
          pairs.each_with_index { |(p, q), i| a.stp p, q, [X0, 16 * i] }
          a.mov X9, SP
          doubles.each_with_index { |(p, q), i| a.stp p, q, [X0, CONTEXT[:d8] + (16 * i)] }
          a.str X9, [X0, CONTEXT[:sp]]
          pairs.each_with_index { |(p, q), i| a.ldp p, q, [X1, 16 * i] }
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
