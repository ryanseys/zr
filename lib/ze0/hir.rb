# frozen_string_literal: true

require_relative "hir/node"
require_relative "hir/build"
require_relative "hir/dump"

module Ze0
  module Hir
    def self.build(source, file, roots: [])
      Build.program(source, file, roots: roots)
    end
  end
end
