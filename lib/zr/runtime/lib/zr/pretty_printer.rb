# frozen_string_literal: true

# The load that CRuby's prelude makes on the first call to Kernel#pp:
# ruby's own pp.rb, from the pinned gem, included without changes. A
# program that calls pp by name includes this file before its body. The
# load waits for that first call, so pp.rb joins $LOADED_FEATURES only then.
Kernel.send(:pretty_printer=, -> { require "pp" })
