# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # A loop that encloses the code being lowered: its head (the test,
      # and the target of `next`), its body (the target of `redo`), its
      # exit block (the target of `break`, which takes the loop's value),
      # and the number of regions open at its start. A jump out of the
      # loop runs the ensures of the regions above that depth. An inline
      # `map` or `select` also has a step: the block that takes the value
      # of each run of the body (its last value, or the value of `next`)
      # and then goes to the head.
      Loop = Data.define(:head, :body, :done, :depth, :step) do
        def initialize(head:, body:, done:, depth:, step: nil) = super
      end
    end
  end
end
