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

module Zr
  module Hir
    # The program that `source` builds: `Build.program` says how.
    # @rbs (String source, String file, ?roots: Array[String], ?eval_support: bool, ?prebuilt: untyped, ?line: Integer,
    #        ?scopes: Array[Array[Symbol]]?, ?method: Array[[Symbol, Symbol?]]?, ?activations: Integer?, ?target: Target,
    #        ?trace: bool, ?gem_set: GemSet?, ?gate: bool | Symbol, ?switches: Switches, ?using: Integer?, ?def_base: Integer?,
    #        ?extensions: Build::Loader::_Extensions) -> Program
    def self.build(...) = Build.program(...)
  end
end
