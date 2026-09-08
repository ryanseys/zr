# frozen_string_literal: true

# A required file's top level is its own scope: this `mark` and the one
# in the file that required it are two names with two slots.
mark = "deeper"

module Spliced
  module Deeper
    EXTRA = "+"
  end
end

DEEPER_MARK = mark
