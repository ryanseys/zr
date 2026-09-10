# frozen_string_literal: true

require_relative "aarch64"
require_relative "../obj/model"

module Ze0
  module Machine
    # The functions no dialect can write: machine code assembled here and
    # delivered as raw bytes on every road.
    module Stub
      include Aarch64::Registers

      # The context `zr_switch` saves and restores: the callee-saved
      # registers x19..x28, the frame pair x29 and x30, sp, and d8..d15.
      CONTEXT = { x19: 0, x21: 16, x23: 32, x25: 48, x27: 64, x29: 80, x30: 88, sp: 96, d8: 104 }.freeze
      CONTEXT_BYTES = 176

      module_function

      # `zr_switch(from: Ptr, to: Ptr)`: park this stack in `from`, resume
      # the one `to` holds. A fresh context needs only x30 (where to start)
      # and sp (its stack top).
      def switch(assembler: Aarch64::Assembler)
        a = assembler.new
        pairs = [[X19, X20], [X21, X22], [X23, X24], [X25, X26], [X27, X28], [X29, X30]]
        pairs.each_with_index { |(p, q), i| a.stp p, q, [X0, 16 * i] }
        a.mov X9, SP
        a.str X9, [X0, CONTEXT[:sp]]
        pairs.each_with_index { |(p, q), i| a.ldp p, q, [X1, 16 * i] }
        a.ldr X9, [X1, CONTEXT[:sp]]
        a.mov SP, X9
        a.ret
        words = a.to_binary.unpack("L<*")
        # The FP pairs, encoded here: the encoder has no SIMD registers.
        fp = 4.times.map { |i| [fp_pair(true, 8 + (2 * i), 0, CONTEXT[:d8] + (16 * i))] }.flatten
        fp += 4.times.map { |i| [fp_pair(false, 8 + (2 * i), 1, CONTEXT[:d8] + (16 * i))] }.flatten
        code = words[0, 7] + fp[0, 4] + words[7, 9] + fp[4, 4] + [words.last]
        Obj::Function.new("zr_switch", code.pack("L<*"), align: 4)
      end

      # `stp`/`ldp` of `d<n>, d<n+1>, [x<base>, #off]`, signed offset.
      def fp_pair(store, n, base, off)
        (store ? 0x6D000000 : 0x6D400000) | ((off / 8) << 15) | ((n + 1) << 10) | (base << 5) | n
      end

      ALL = { "zr_switch" => [[:Ptr, :Ptr], :Void] }.freeze
    end
  end
end
