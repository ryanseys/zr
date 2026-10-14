# frozen_string_literal: true

require_relative "target"
require_relative "hir/switches"

module Zr
  # What steers the build of a program, from the command line to the
  # loader: the `target`; the `gem_set` whose gems come before zr's
  # standard library (lib/zr/gem_set.rb), or nil; the `gate` that stops
  # the build at a require that no root has (`Hir::Build#gate!`); whether
  # the program's trace events are armed from the start (`trace`); and
  # ruby's `switches` (`Hir::Switches`).
  # @rbs skip -- typed in sig/zr/build_options.rbs
  BuildOptions = Data.define(:target, :gem_set, :gate, :trace, :switches)

  class BuildOptions
    # A plain build for this host, with what a caller gives.
    #: (?target: Target, ?gem_set: GemSet?, ?gate: bool | Symbol, ?trace: bool, ?switches: Hir::Switches) -> void
    def initialize(target: Target.default, gem_set: nil, gate: false, trace: false, switches: Hir::Switches::NONE)
      super
    end
  end
end
