# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # A loop that encloses the code being lowered: its head (the test,
      # and the target of `next`), its body (the target of `redo`), its
      # exit block (the target of `break`, which takes the loop's value),
      # and the number of regions open at its start. A jump out of the
      # loop runs the ensures of the regions above that depth.
      Loop = Data.define(:head, :body, :done, :depth)
    end
  end
end
