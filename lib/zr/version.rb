# frozen_string_literal: true

module Zr
  VERSION = "0.1.0"

  # The ruby version that zr runs on and matches, as pinned in
  # `.ruby-version`. This ruby runs the compiler. Its standard library is
  # the one a program requires (its gems at the versions that
  # lib/zr/libraries.rb pins, and vendor/lib). The generated tables come
  # from it, and the tests check zr against its output.
  RUBY = "4.0.6"
  # The release date and the CRuby revision of that ruby. The generators
  # read CRuby's sources at this revision (`tool/lib/zr/dev/sources.rb`),
  # and `runtime/core/env.rb` gives the same values to a program
  # (`test/unit/layout_test.rb` checks that they agree).
  RUBY_RELEASE_DATE = "2026-07-14"
  RUBY_REVISION = "03b6d3f8898a28604fe6cb00eae3226b821168f4"
end
