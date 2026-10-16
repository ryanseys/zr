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
    # @rbs (String source, String file, ?BuildOptions options, ?roots: Array[String], ?program: bool, ?prebuilt: untyped,
    #        ?line: Integer, ?scopes: Array[Array[Symbol]]?, ?method: Array[[Symbol, Symbol?]]?, ?activations: Integer?,
    #        ?using: Integer?, ?def_base: Integer?, ?branch_base: Integer?, ?extensions: Build::Loader::_Extensions) -> Program
    def self.build(...) = Build.program(...)
  end
end
