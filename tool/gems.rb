# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # `zr-dev gems`: which gems zr compiles, and what stops the others.
    #
    #   zr-dev gems try rack                 one gem, with the full diff
    #   zr-dev gems try rack=3.1.8 --keep    that version; keep the work directory
    #   zr-dev gems sweep --top 100 --save   many gems, one line each, into gems/compat.tsv
    #   zr-dev gems triage                   the failures, grouped by cause
    #   zr-dev gems top --refresh            gems/top.tsv from packages.ecosyste.ms
    #
    # A gem is NAME (the newest release), NAME=VERSION, or the path of an
    # unpacked gem (a word with a `/`). `--corpus DIR` (or ZR_GEM_CORPUS)
    # finds each gem first in DIR/<name>. The tool never lists DIR, so a
    # corpus can hold every gem. docs/how-to/check-a-gem.md tells more.
    class GemCompat < Group
      summary "Check which gems zr compiles, and group what stops the others"

      commands({
        "try" => ["One gem: build a program that requires it, and compare it with ruby", -> { require_relative "gems/try"; Try }],
        "sweep" => ["Many gems, one line each, into a table", -> { require_relative "gems/sweep"; Sweep }],
        "triage" => ["The failures of a table, grouped by cause", -> { require_relative "gems/triage"; Triage }],
        "top" => ["The most downloaded gems (gems/top.tsv)", -> { require_relative "gems/top"; Top }]
      })

      # The options and the parts that each gems command shares.
      class Base < Command
        host_ruby!

        def defaults
          @corpus = nil
          @offline = false
        end

        def options(o)
          o.on("--corpus DIR", "find each gem first in DIR/<name> (default: $ZR_GEM_CORPUS)") { |v| @corpus = v }
          o.on("--offline", "fetch nothing: use the corpus and the gems in tmp/gems") { @offline = true }
        end

        def trial(**) = Gems::Trial.new(resolver: resolver, **)

        def resolver = Gems::Resolver.new(store: Gems::FetchedGems.new.tap(&:migrate), corpus: corpus, offline: @offline || false)

        def corpus
          dir = @corpus || ENV.fetch("ZR_GEM_CORPUS", "")
          return nil if dir.empty?

          fail!("no corpus directory #{dir}") unless File.directory?(dir)
          Gems::Corpus.new(dir)
        end

        def request(word)
          Gems::Request.parse(word)
        rescue ArgumentError => e
          fail!(e.message)
        end

        # The trials compare with the reference ruby
        # (tool/install_reference_gems.rb).
        def reference!
          fail!("the reference ruby is not set up; run `ruby tool/install_reference_gems.rb`") unless Harness::Reference.ready?
        end

        # Puts the result's row, with the commit and the downloads, into
        # each table, and writes the tables.
        def record(tables, result)
          commit = Gems::Table.commit
          tables.each do |table|
            table.add(result, commit: commit, downloads: downloads[result.name])
            table.write
          end
        end

        def downloads = @downloads ||= Gems::Top.read
      end
    end
  end
end
