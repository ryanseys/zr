# frozen_string_literal: true

module Zr
  VERSION = "0.1.0"

  # The ruby version that zr runs on and matches, as pinned in
  # `.ruby-version`. This ruby runs the compiler. Its standard library is
  # the one a program requires (its gems at the versions that
  # lib/zr/libraries.rb pins, and vendor/lib). The generated tables come
  # from it, and the tests check zr against its output.
  RUBY = "4.0.6"
end
