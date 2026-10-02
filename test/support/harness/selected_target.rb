# frozen_string_literal: true

require_relative "../../../lib/zr/target"

module Zr
  module Harness
    # The target that this run selected: the host's target, or the one
    # that `ZR_TARGET` names, as in the
    # cross-target CI jobs. An unknown triple raises an error here, not
    # later. It loads only `Target`, so test/support/built.rb, which
    # every unit test loads, does not load the command line.
    def self.selected_target
      triple = ENV.fetch("ZR_TARGET", nil)
      return Target.default if triple.nil? || triple.empty?

      Target.fetch(triple) or raise ArgumentError, "no target #{triple}; `zr targets` names them"
    end
  end
end
