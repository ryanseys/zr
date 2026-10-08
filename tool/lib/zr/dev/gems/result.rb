# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # What a trial found for one gem: its tier (TIERS, or `skipped`),
      # the kind of failure (nil for a gem that loads), a short detail,
      # the path of the full log, and the CScan::Scan of each C extension
      # among the gem and the gems that it needs.
      Result = Data.define(:name, :version, :source, :tier, :kind, :detail, :log, :scans) do
        def initialize(scans: [], **) = super

        # The place of the tier in TIERS; a skipped gem is below them all.
        def rank = TIERS.index(tier) || -1

        # Whether the gem got as far as a trial can take it: it loads, or
        # it builds in a trial that runs nothing.
        def passed?(run: true) = rank >= TIERS.index(run ? :loads : :builds)

        # One line for a sweep: `loads     rack 3.1.8`.
        def line = format("%-9s %s %s%s", tier, name, version, kind ? "  #{kind}" : "")
      end
    end
  end
end
