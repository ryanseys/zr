# frozen_string_literal: true

require_relative "hir/features"
require_relative "hir/node"
require_relative "hir/build"
require_relative "hir/patterns"
require_relative "hir/dump"

module Ze0
  module Hir
    def self.build(source, file, roots: [], road: true)
      Build.program(source, file, roots: roots, road: road)
    end
  end
end
