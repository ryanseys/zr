# frozen_string_literal: true

module Zr
  # prism finds the line of a byte offset with a binary search over the
  # line starts. The builder asks once or more for each node (5% of a
  # warm build of bundler), and reads the nodes mostly in source order.
  # So the line of the last answer, or the line after it, is almost
  # always the answer, and a binary search, prism's own, is left for the
  # rest. The answer is the same as prism's.
  # @rbs module-self: Prism::Source
  module LineCursor
    # @rbs @zr_line: Integer?

    # Public, as prism 1.9 at ruby 4.1's commit has it: its Ripper translation
    # calls it.
    #: (Integer byte_offset) -> Integer
    def find_line(byte_offset)
      return search(byte_offset) if frozen?

      starts = offsets
      at = @zr_line || 0
      if starts[at] <= byte_offset
        after = at + 1
        return at if after == starts.length || byte_offset < starts[after]
        return @zr_line = after if after + 1 == starts.length || byte_offset < starts[after + 1]
      end
      @zr_line = search(byte_offset)
    end

    private

    # prism's search: the last line that starts at or before the offset.
    # Not `super`: the prism gem on rubygems.org keeps its find_line
    # private, with no signature.
    #: (Integer byte_offset) -> Integer
    def search(byte_offset)
      (offsets.bsearch_index { |offset| offset > byte_offset } || offsets.length) - 1
    end
  end
end
