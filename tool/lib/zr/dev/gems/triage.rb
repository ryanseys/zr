# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # The failures of a table, grouped by kind: the gems that each cause
      # stops, and their downloads. The groups that stop the most gems
      # come first, so the list is an order in which to fix zr.
      class Triage
        Group = Data.define(:kind, :rows) do
          def downloads = rows.sum { |row| row.downloads.to_i }

          # The gems, most downloaded first.
          def gems = rows.sort_by { |row| [-row.downloads.to_i, row.gem] }.map(&:gem)
        end

        def initialize(table)
          @table = table
        end

        # Each group, the one that stops the most gems first. `kind` keeps
        # only the kinds that start with it (`cext` or `cext:ffi`).
        def groups(kind = nil)
          rows = @table.reject { |row| row.kind.empty? || (TIERS.index(row.tier.to_sym) || -1) >= TIERS.index(:loads) }
          rows = rows.select { |row| row.kind == kind || row.kind.start_with?(kind.end_with?(":") ? kind : "#{kind}:") } if kind
          rows.group_by(&:kind).map { |name, members| Group.new(kind: name, rows: members) }
              .sort_by { |group| [-group.rows.size, -group.downloads, group.kind] }
        end
      end
    end
  end
end
