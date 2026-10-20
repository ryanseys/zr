# frozen_string_literal: true

# The ruby that zr runs on and matches: the one that `.ruby-version` pins.
# `zr-dev gen ruby_version` records it here (RUBY_PIN, RUBY, RUBY_REVISION
# and the rest). This ruby runs the compiler. A program's standard library
# is zr's copy of this ruby's own (vendor/ruby, lib/zr/library/roots.rb), the
# generated tables come from it, and the tests check zr against its output.
require_relative "ruby_version"

module Zr
  VERSION = "0.1.0"

  # The docs of this version, at its release tag, so that a link that zr
  # prints matches what it does.
  DOCS_URL = "https://github.com/ryanseys/zr/blob/v#{VERSION}/docs".freeze
  # Where to report a defect.
  ISSUES_URL = "https://github.com/ryanseys/zr/issues"

  # The oldest ruby that runs zr: Ruby 4. The host ruby runs only the
  # compiler: a program's output is RUBY's whatever ruby runs zr.
  RUBY_MINIMUM = "4.0"
  # The series of ruby that CI runs zr on (test/unit/ci_rubies_test.rb).
  # A ruby of another series runs zr with a warning.
  RUBY_TESTED = %w[4.0 4.1].freeze

  # RUBY_DESCRIPTION of a program built for `platform`, which `zr -v`
  # prints as ruby does (lib/zr/runtime/core/ruby_version.rb).
  #: (String platform) -> String
  def self.ruby_description(platform) = "#{RUBY_DESCRIPTION_HEAD} [#{platform}]"
end

module Zr
  # Whether zr runs on a ruby of `version`: RUBY_MINIMUM or later. The host
  # ruby only runs the compiler. A program's library is zr's own
  # (vendor/ruby), so the host's version changes nothing that a program
  # sees.
  def self.supported_ruby?(version) = (segments(version) <=> segments(RUBY_MINIMUM)) >= 0

  # Whether `version` is of a series that zr is tested with
  # (RUBY_TESTED): it runs zr with no warning.
  #: (String version) -> bool
  def self.tested_ruby?(version) = RUBY_TESTED.include?(segments(version).first(2).join("."))

  # Whether the running ruby is the pinned one itself, the only ruby that
  # writes zr's tables and expected outputs: the same version, patch level
  # and revision, so a preview does not pass for its release.
  #: () -> bool
  def self.pinned_ruby? = ::RUBY_VERSION == RUBY && ::RUBY_PATCHLEVEL == RUBY_PATCHLEVEL && ::RUBY_REVISION == RUBY_REVISION

  def self.segments(version) = version.split(".").map(&:to_i)
  private_class_method :segments
end
