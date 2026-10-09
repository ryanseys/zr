# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"

module Zr
  module Dev
    module Commands
      class Gems
        # `zr-dev gems try GEM`: tries one gem and tells each step, the
        # result, the diff and the path of the log.
        #
        # Exit status: 0 when the gem loads (or is verified), else 1.
        class Try < Base
          summary "One gem: build a program that requires it, and compare it with ruby"
          usage "GEM [--keep] [--save] [--corpus DIR] [--offline] [--build-only]"

          def defaults
            super
            @keep = false
            @save = false
          end

          def options(o)
            super
            o.on("--keep", "keep the work directory (tmp/gems/work)") { @keep = true }
            o.on("--save", "write the row into log/gems/compat.tsv") { @save = true }
          end

          def run(argv)
            fail!("give one gem: NAME, NAME=VERSION or a path with a /") unless argv.size == 1
            wanted = request(argv.first)
            reference!
            trial = trial(keep: @keep || false, say: ->(text) { puts text })
            result = trial.call(wanted)
            diff = File.read(result.log)[/^--- (probe|smoke)\.rb: .*?(?=^result: )/m]
            puts diff if diff
            puts result.line
            puts "  #{result.detail}" if result.detail
            puts "log: #{Dev.rel(result.log)}"
            if @save
              record([Dev::Gems::Table.new(Dev::Gems::Table.compat)], result)
              puts "wrote #{Dev.rel(Dev::Gems::Table.compat)}"
            end
            result.passed?(run: !@build_only)
          end
        end
      end
    end
  end
end
