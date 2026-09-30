# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # What a trial found for one gem: its tier (TIERS, or `skipped`),
      # the kind of failure (nil for a gem that loads), a short detail,
      # and the path of the full log.
      Result = Data.define(:name, :version, :source, :tier, :kind, :detail, :log) do
        # The place of the tier in TIERS; a skipped gem is below them all.
        def rank = TIERS.index(tier) || -1

        def passed? = rank >= TIERS.index(:loads)

        # One line for a sweep: `loads     rack 3.1.8`.
        def line = format("%-9s %s %s%s", tier, name, version, kind ? "  #{kind}" : "")
      end
    end
  end
end
