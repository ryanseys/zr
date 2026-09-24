# frozen_string_literal: true

module Zr
  VERSION = "0.1.0"

  # The ruby zr runs on and answers for, the one `.ruby-version` pins.
  # It runs the compiler, its standard library is the one a program
  # requires (its gems at the versions lib/zr/libraries.rb pins, and
  # vendor/lib), the generated tables were read off it, and every answer
  # the tests hold zr to came from it.
  RUBY = "4.0.6"
end
