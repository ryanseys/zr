# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    module Commands
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
      class Gems < Group
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
            @build_only = false
          end

          def options(o)
            o.on("--corpus DIR", "find each gem first in DIR/<name> (default: $ZR_GEM_CORPUS)") { |v| @corpus = v }
            o.on("--offline", "fetch nothing: use the corpus and the gems in tmp/gems") { @offline = true }
            o.on("--build-only", "run no gem's code: gems from rubygems.org only, built and not run") { @build_only = true }
          end

          def trial(**) = Dev::Gems::Trial.new(resolver: resolver, run: !@build_only, **)

          def resolver = Dev::Gems::Resolver.new(store: Dev::Gems::FetchedGems.new, corpus: corpus, offline: @offline || false)

          def corpus
            dir = @corpus || ENV.fetch("ZR_GEM_CORPUS", "")
            return nil if dir.empty?

            fail!("--build-only takes no corpus: a corpus gem's .gemspec is Ruby that runs") if @build_only

            fail!("no corpus directory #{dir}") unless File.directory?(dir)
            Dev::Gems::Corpus.new(dir)
          end

          def request(word)
            request = Dev::Gems::Request.parse(word)
            fail!("--build-only takes no path: the gem's .gemspec is Ruby that runs") if @build_only && request.path
            request
          rescue ArgumentError => e
            fail!(e.message)
          end

          # The trials compare with the reference ruby
          # (tool/install_reference_gems.rb). A build-only trial runs no ruby.
          def reference!
            return if @build_only

            fail!("the reference ruby is not set up; run `ruby tool/install_reference_gems.rb`") unless Harness::Reference.ready?
          end

          # Puts the result's row, with the commit and the downloads, into
          # each table, and writes the tables.
          def record(tables, result)
            commit = Dev::Gems::Table.commit
            tables.each do |table|
              table.add(result, commit: commit, downloads: downloads[result.name])
              table.write
            end
          end

          def downloads = @downloads ||= Dev::Gems::Top.read
        end
      end
    end
  end
end
