# frozen_string_literal: true

require "set"

module Zr
  module Backend
    module Native
      # The registers that `Regalloc` gives out on one architecture. A
      # value that crosses a call gets one of `callee`, which a callee
      # saves; a value that crosses none gets one of `caller_saved` first. Each
      # pool lists its registers in the order that they go out, and a
      # freed register goes back to its place in that order. `args` are the
      # integer argument registers in order, where the entry block's
      # parameters arrive.
      class Pools
        # @rbs @saved: Set[register]
        # @rbs @rank: Hash[register, Integer]

        attr_reader :callee #: Array[register]
        attr_reader :caller_saved #: Array[register]
        attr_reader :args #: Array[register]

        #: (callee: Array[register], caller_saved: Array[register], args: Array[register]) -> void
        def initialize(callee:, caller_saved:, args:)
          @callee = callee.freeze
          @caller_saved = caller_saved.freeze
          @args = args.freeze
          @saved = callee.to_set.freeze
          @rank = callee.each_with_index.to_h.merge(caller_saved.each_with_index.to_h).freeze
          freeze
        end

        # Whether the callee saves `reg`.
        #: (register reg) -> bool
        def callee?(reg) = @saved.include?(reg)

        # The place of `reg` in its pool.
        #: (register reg) -> Integer
        def rank(reg) = @rank.fetch(reg)
      end
    end
  end
end
