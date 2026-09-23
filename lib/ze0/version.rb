# frozen_string_literal: true

module Ze0
  VERSION = "0.1.0"

  # The ruby ze0 runs on and answers for, the one `.ruby-version` pins.
  # It runs the compiler, its standard library is the one vendor/lib
  # holds, the generated tables were read off it, and every answer the
  # tests hold ze0 to came from it.
  RUBY = "4.0.6"
end
