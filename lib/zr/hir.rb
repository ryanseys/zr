# frozen_string_literal: true

require_relative "hir/features"
require_relative "hir/switches"
require_relative "hir/node"
require_relative "hir/core_def"
require_relative "hir/spots"
require_relative "hir/build"
require_relative "hir/build/patterns"
require_relative "hir/escape"
require_relative "hir/locals"
require_relative "hir/dump"

module Zr
  module Hir
    # @rbs source: String
    # @rbs file: String
    # @rbs roots: Array[String]
    # @rbs eval_support: bool
    # @rbs prebuilt: untyped
    # @rbs line: Integer
    # @rbs scopes: Array[Array[Symbol]]?
    # @rbs method: Array[[Symbol, Symbol?]]?
    # @rbs activations: Integer?
    # @rbs target: Target
    # @rbs trace: bool
    # @rbs gem_set: GemSet?
    # @rbs gate: bool | Symbol
    # @rbs switches: Switches
    # @rbs return: Program
    def self.build(source, file, roots: [], eval_support: true, prebuilt: nil, line: 1, scopes: nil, method: nil, activations: nil,
                   target: Target.default, trace: false, gem_set: nil, gate: false, switches: Switches::NONE, using: nil)
      Build.program(source, file, roots: roots, eval_support: eval_support, prebuilt: prebuilt, line: line, scopes: scopes, method: method, activations: activations,
                                  target: target, trace: trace, gem_set: gem_set, gate: gate, switches: switches, using: using)
    end
  end
end
