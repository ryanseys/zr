# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # The features of one generated program (swarm testing, Groce et
      # al.): each program turns each pack on with a chance of about one
      # half, and gives each one that is on a weight of its own. A program
      # with fewer features goes deeper into the ones it has, and two
      # features that block each other each get programs without the
      # other.
      class Swarm
        # Each pack and the chance that a program has it. The core packs
        # (values, control) are always on.
        PACKS = {
          "values" => 1.0, "control" => 1.0, "methods" => 0.6, "blocks" => 0.6, "objects" => 0.5,
          "exceptions" => 0.5, "pattern" => 0.4, "meta" => 0.35, "eval" => 0.15, "fiber_thread" => 0.3,
          "collections" => 0.6, "strings" => 0.6, "numeric" => 0.5, "stdlib" => 0.25, "gc_pressure" => 0.15,
          "explore" => 0.3, "io" => 0.25, "process" => 0.15, "encoding" => 0.3, "trace" => 0.15, "ending" => 0.3
        }.freeze

        attr_reader :packs, :weights

        # `only`, when given, names the packs that may be on (the core
        # packs are on in any case).
        def initialize(rng, only: nil)
          @packs = PACKS.select { |name, chance| (only.nil? || only.include?(name) || chance >= 1.0) && rng.rand < chance }.keys
          @weights = @packs.to_h { |name| [name, rng.rand(1..10)] }
        end

        def on?(pack) = @packs.include?(pack)

        def to_h = { packs: @packs, weights: @weights }
      end
    end
  end
end
