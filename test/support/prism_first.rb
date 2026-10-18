# frozen_string_literal: true

require_relative "../../lib/zr/library/ports"

module Zr
  module Test
    # minitest's path expander requires prism before a test file loads,
    # and a process keeps the first prism that it loads (lib/zr/parse.rb).
    # Ruby's own prism serves the tests when it is zr's vendored one, as
    # a ruby of the pin's revision carries it. A bundle can carry instead
    # a released prism gem with the same version but older nodes (the
    # rubygems.org prism 1.9.0 has no NoBlockParameterNode). Then zr's
    # prism goes first on the load path, as lib/zr/parse.rb puts it.
    module PrismFirst
      LIB = Library::Ports.lib("prism")
      SHIM = File.expand_path("../../lib/zr/prism_shim", __dir__)

      module_function

      #: () -> void
      def ensure!
        $LOAD_PATH.unshift(LIB, SHIM) unless same?(File.join(LIB, "prism/node.rb"))
      end

      # Whether the prism/node.rb that a require finds has the bytes of
      # zr's.
      #: (String ours) -> bool
      def same?(ours)
        _, theirs = $LOAD_PATH.resolve_feature_path("prism/node")
        return false unless theirs && File.size(theirs) == File.size(ours)

        File.binread(theirs) == File.binread(ours)
      end
    end
  end
end
