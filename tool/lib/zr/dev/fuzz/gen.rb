# frozen_string_literal: true

require_relative "swarm"
require_relative "gen/values"
require_relative "gen/statements"
require_relative "gen/packs"
require_relative "gen/catalog"
require_relative "gen/writer"

module Zr
  module Dev
    module Fuzz
      module Gen
        # The program of `seed`, and its swarm. `only` limits the packs.
        def self.program(seed, only: nil)
          writer = Writer.new(seed, only: only)
          [writer.program, writer.swarm]
        end

        # A piece of code that stands alone, for the mutator to put in a
        # seed: one value printed, or the error that it raised.
        def self.snippet(seed)
          writer = Writer.new(seed)
          expr = writer.value(writer.pick(TYPES), 2)
          "def __opaque(x) = x\nbegin\n  p(#{expr})\nrescue => e\n  p e\nend"
        end
      end

      # Programs that the generator writes, one seed each. The seeds of a
      # run come from its rng, so a run with the same seed writes the same
      # programs.
      class GenSource
        def initialize(only: nil)
          @only = only
        end

        def next_candidate(rng)
          seed = rng.rand(2**31)
          source, swarm = Gen.program(seed, only: @only)
          Candidate.new(source: source, origin: "gen", meta: { gen_seed: seed, packs: swarm.packs })
        end
      end
    end
  end
end
