# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"
require_relative "triage"

module Zr
  module Dev
    module Commands
      class Gems
        # `zr-dev gems top`: the most downloaded gems, each with its tier in
        # gems/compat.tsv. `--refresh` writes gems/top.tsv again from
        # packages.ecosyste.ms.
        class Top < Base
          summary "The most downloaded gems (gems/top.tsv)"
          usage "[--refresh] [--count N]"

          COUNT = 1000
          SHOWN = 25

          def defaults
            @refresh = false
            @count = nil
          end

          def options(o)
            o.on("--refresh", "write gems/top.tsv again from packages.ecosyste.ms") { @refresh = true }
            o.on("--count N", Integer, "gems to write (default #{COUNT}) or to show (default #{SHOWN})") { |v| @count = v }
          end

          def run(argv)
            fail!("takes no gems") unless argv.empty?
            if @refresh
              list = Dev::Gems::Top.fetch(@count || COUNT) { |got| warn "#{got} gems" if (got % 10_000).zero? }
              Dev::Gems::Top.write(list)
              puts "wrote #{Dev.rel(Dev::Gems::Top.path)}: #{list.size} gems"
              return true
            end

            list = Dev::Gems::Top.read
            fail!("no #{Dev.rel(Dev::Gems::Top.path)}; run `zr-dev gems top --refresh`") if list.empty?
            table = Dev::Gems::Table.new(Dev::Gems::Table.compat)
            list.first(@count || SHOWN).each_with_index do |(gem, downloads), i|
              row = table[gem]
              puts format("%4d  %-30s %14s  %s", i + 1, gem, Triage.number(downloads), row ? [row.tier, row.kind].reject(&:empty?).join(" ") : "-")
            end
            true
          end
        end
      end
    end
  end
end
