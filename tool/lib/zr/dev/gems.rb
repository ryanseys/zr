# frozen_string_literal: true

require_relative "../dev"

module Zr
  module Dev
    # The parts of the gem compat tool, `zr-dev gems` (tool/gems.rb). The
    # tool finds a gem and the gems that it needs (Resolver), refuses it
    # when zr cannot compile it (Rules), builds a program that requires
    # it, runs the program under ruby and as a zr binary (Trial), and
    # keeps one row for each gem (Table).
    #
    # The tool never runs a gem's code in its own process, and never runs
    # `gem install`: it unpacks each gem in Ruby (FetchedGems).
    module Gems
      # The fetched gems, the logs, the sweeps and the work directories.
      TMP = Dev.path("tmp/gems")
      # The committed files: compat.tsv, top.tsv and the overrides.
      HOME = Dev.path("gems")

      # The names that rubygems.org accepts.
      NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

      # The tiers, from the worst to the best. A gem that the tool did not
      # try (an override skips it, or ruby itself fails) is `skipped`.
      TIERS = %i[refused fails compiles loads verified].freeze

      # A gem that stops before its best tier: the tier that it got, the
      # kind of failure (`cext:ffi-yajl`, `build-error`), and a short
      # detail.
      class Failure < StandardError
        attr_reader :kind, :tier
        # The gem that the failure is of, when the tool found it.
        attr_accessor :subject

        def initialize(kind, detail, tier: :fails)
          super(detail.to_s)
          @kind = kind
          @tier = tier
        end
      end
    end
  end
end

require_relative "gems/request"
require_relative "gems/subject"
require_relative "gems/fetched_gems"
require_relative "gems/corpus"
require_relative "gems/resolver"
require_relative "gems/rules"
require_relative "gems/override"
require_relative "gems/result"
require_relative "gems/trial"
require_relative "gems/table"
require_relative "gems/top"
require_relative "gems/triage"
require_relative "gems/snapshot"
