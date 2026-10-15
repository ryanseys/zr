# frozen_string_literal: true

require_relative "function"
require_relative "../config"
require_relative "../timing"
require_relative "gvn"
require_relative "licm"
require_relative "statics"
require_relative "switches"
require_relative "threads"
require_relative "types"
require_relative "verify"
require_relative "passes/renaming"
require_relative "passes/fold"
require_relative "passes/forward"
require_relative "passes/chains"
require_relative "passes/blocks"
require_relative "passes/dce"
require_relative "passes/inline"

module Zr
  module IR
    # The passes that each emitter runs on a function before assembly. They
    # run in one order from one place, so the aarch64 backend, the wasm
    # backend and eval support all get the same IR.
    #
    # Each pass keeps these invariants: a value has one definition, and the
    # definition dominates its uses. The entry block stays first and keeps
    # its parameters. Each block ends in a terminator. A `brif` has no
    # arguments. A store to a record slot is never removed, because the
    # collector reads it as a root.
    module Passes
      module_function

      # Inlines the small leaf functions of the unit into their callers,
      # before the pipeline runs on each function.
      #: (Array[Function] functions) -> Array[Function]
      def inline(functions) = Inline.run(functions)

      # The pipeline, in order.
      #
      # `Fold` runs two times, because `Forward` finds constants that the
      # first fold cannot see. Without the second fold, the runtime object is
      # 223 KB larger; the pass costs 0.6 s of the 9.3 s build of that object.
      # `Statics` runs after `Forward`, so it does not see the slot loads, and
      # before `Chains`, so its gate test splits into the branch chain. `GVN`
      # runs after `Statics` to number its new values. `LICM` runs last, so a
      # loop has one copy of each value. `Threads` runs after `Chains`, whose
      # split tests it can skip. `Switches` runs after both, on the tests
      # that are left, and `Blocks` drops the blocks they leave.
      #
      # With timing on, each pass adds its seconds to its tally, the two
      # folds to one.
      PIPELINE = [Fold, Forward, Statics, GVN, LICM, Fold, Chains, Threads, Switches, Blocks, DCE].freeze

      #: (Function f) -> Function
      def run(f)
        PIPELINE.each { |pass| Timing.tally(pass) { pass.run(f) } }
        f
      end

      # Runs the pipeline and then the checks, and returns the IR for an
      # emitter. The dominance and type checks (`Verify::Strict`) are slow,
      # so a build runs them only when `ZR_VERIFY=1`; the cheap checks
      # always run.
      #: (Function f, ?strict: bool) -> Function
      def prepare(f, strict: Config.current.verify?)
        run(f)
        Timing.tally(Verify) { Verify.check(f, strict: strict) }
      end
    end
  end
end
