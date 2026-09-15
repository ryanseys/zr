# frozen_string_literal: true

require_relative "function"
require_relative "verify"

module Ze0
  module IR
    # The passes every emitter runs over a function before it is
    # assembled, in one order from one place, so the aarch64 backend, the
    # wasm backend and the eval road all see the same IR.
    #
    # What every pass keeps: a value is defined once and its definition
    # dominates its uses, the entry block stays first and keeps its
    # parameters, every block ends in a terminator, a `brif` carries no
    # arguments, and a store to a record slot is never removed, because
    # the collector reads it as a root.
    module Passes
      module_function

      # The pipeline, in order.
      def run(f)
        f
      end

      # The pipeline and then the checks: what an emitter takes. The
      # dominance and type checks cost a pass of their own, so a build
      # runs them only under `ZE0_VERIFY=1`; the checks that run the IR
      # against the interpreter always do.
      def prepare(f, strict: ENV["ZE0_VERIFY"] == "1")
        run(f)
        Verify.check(f, strict: strict)
      end
    end
  end
end
