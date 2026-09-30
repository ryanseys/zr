# frozen_string_literal: true

module Zr
  VERSION = "0.1.0"

  # The docs of this version, at its release tag, so that a link that zr
  # prints matches what it does.
  DOCS_URL = "https://github.com/ryanseys/zr/blob/v#{VERSION}/docs".freeze
  # Where to report a defect.
  ISSUES_URL = "https://github.com/ryanseys/zr/issues"

  # The ruby version that zr runs on and matches, as pinned in
  # `.ruby-version`. This ruby runs the compiler. A program's standard
  # library is zr's copy of this ruby's own (vendor/ruby, lib/zr/libraries.rb).
  # The generated tables come from it, and the tests check zr against its
  # output.
  RUBY = "4.0.7"
  # The release date and the CRuby revision of that ruby. The generators
  # read CRuby's sources at this revision (`tool/lib/zr/dev/sources.rb`),
  # and `runtime/core/env.rb` gives the same values to a program
  # (`test/unit/layout_test.rb` checks that they agree).
  RUBY_RELEASE_DATE = "2026-09-15"
  RUBY_REVISION = "229531a6cfbf07e3caef30dbac24a2a3f3fed482"
end

module Zr
  # Whether zr runs on a ruby of `version`: RUBY, or a later 4.0 release.
  # The host ruby only runs the compiler. A program's library is zr's own
  # (vendor/ruby), so a patch release of ruby changes nothing that a program
  # sees.
  def self.supported_ruby?(version)
    major, minor, patch = version.split(".").map(&:to_i)
    want = RUBY.split(".").map(&:to_i)
    [major, minor] == want.first(2) && patch.to_i >= want[2]
  end
end
