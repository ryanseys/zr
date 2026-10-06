# frozen_string_literal: true

# `require_relative` resolves here, not at run time: the target's
# statements are spliced in at the call's position, once per file.
# A second require of the same path adds nothing.
require_relative "require_relative/shared"
require_relative "require_relative/shared"

# Each file's top level is its own scope, so all three `mark`s are
# different names and this one is untouched by the two spliced in above.
mark = "main"

module Spliced
  # Reopened from another file: one class row, one body per `module`
  # statement, and the constants of both.
  VERSION = 2

  def self.report = "#{Helper.help} #{VERSION} #{Deeper::EXTRA}"
end

p mark, SHARED_MARK, DEEPER_MARK
p Spliced.report
p Spliced::Helper.help
p Spliced::MARK, Spliced::VERSION, Spliced::Deeper::EXTRA
p Spliced.constants.sort
p Spliced::Helper.singleton_methods.sort

begin
  Spliced::Helper.boom
rescue ArgumentError => e
  # A `def` names the file it was WRITTEN in, not the one being compiled.
  p e.message, e.backtrace.first
end

p Spliced::Helper.method(:help).source_location.first

# A `require` no root carries names a feature the runtime already holds.
# The backend registers the classes it gates, CONCEALED, and the call
# opens the gate where it stands. The answer is folded as ruby folds it.
p require("json")
p require("json")
p JSON.name, JSON.instance_of?(Module)
p require("digest")
p Digest.name
