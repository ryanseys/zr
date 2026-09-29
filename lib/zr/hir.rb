# frozen_string_literal: true

require_relative "hir/features"
require_relative "hir/node"
require_relative "hir/spots"
require_relative "hir/build"
require_relative "hir/patterns"
require_relative "hir/escape"
require_relative "hir/dump"

module Zr
  module Hir
    def self.build(source, file, roots: [], eval_support: true, prebuilt: nil, line: 1, scopes: nil, method: nil, activations: nil,
                   target: Target.default, trace: false, gem_set: nil)
      Build.program(source, file, roots: roots, eval_support: eval_support, prebuilt: prebuilt, line: line, scopes: scopes, method: method, activations: activations,
                                  target: target, trace: trace, gem_set: gem_set)
    end
  end
end
