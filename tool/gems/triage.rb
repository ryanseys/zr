# frozen_string_literal: true

require_relative "../lib/zr/dev/gems"

module Zr
  module Dev
    module Commands
      class Gems
        # `zr-dev gems triage`: the causes that stop gems, the one that
        # stops the most gems first, with the downloads of those gems.
        # `triage KIND` gives each gem of the kinds that start with KIND,
        # with its detail.
        #
        #   zr-dev gems triage                  every cause
        #   zr-dev gems triage cext             each gem with a C extension
        #   zr-dev gems triage missing-require
        class Triage < Base
          summary "The failures of a table, grouped by cause"
          usage "[KIND] [--file TSV]"

          # The gems that a line of the summary names.
          SHOWN = 4

          def defaults = @file = nil

          def options(o) = o.on("--file TSV", "read TSV, not gems/compat.tsv") { |v| @file = v }

          def run(argv)
            fail!("give at most one kind") if argv.size > 1
            table = Dev::Gems::Table.new(@file || Dev::Gems::Table.compat)
            fail!("#{Dev.rel(table.path)} has no rows; run `zr-dev gems sweep --save`") if table.size.zero?

            groups = Dev::Gems::Triage.new(table).groups(argv.first)
            if groups.empty?
              puts argv.empty? ? "no failures in #{Dev.rel(table.path)}" : "no failures of kind #{argv.first}"
              return true
            end
            argv.empty? ? summary(groups, table) : details(groups)
            true
          end

          def summary(groups, table)
            width = groups.map { |group| group.kind.size }.max
            puts format("%5s  %14s  %-#{width}s  %s", "gems", "downloads", "kind", "gems (most downloaded first)")
            groups.each do |group|
              names = group.gems
              more = names.size > SHOWN ? ", +#{names.size - SHOWN}" : ""
              puts format("%5d  %14s  %-#{width}s  %s", group.rows.size, Triage.number(group.downloads), group.kind,
                          names.first(SHOWN).join(", ") + more)
            end
            failing = groups.sum { |group| group.rows.size }
            puts "", "#{failing} of #{table.size} gems do not load"
          end

          def details(groups)
            groups.each do |group|
              puts "#{group.kind} (#{group.rows.size} gems)"
              group.gems.each do |gem|
                row = group.rows.find { |r| r.gem == gem }
                puts "  #{row.gem} #{row.version}: #{row.detail}"
              end
            end
          end

          # 1234567 as "1,234,567".
          def self.number(n) = n.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end
      end
    end
  end
end
