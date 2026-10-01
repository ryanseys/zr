# frozen_string_literal: true

require "date"
require_relative "../../../../../lib/zr/paths"

module Zr
  module Dev
    module Gems
      # The rows of a sweep, one for each gem, sorted by name, as a TSV
      # file with a header. gems/compat.tsv is the committed one. An update
      # replaces the row of each gem that it tried, and keeps the others.
      class Table
        include Enumerable

        COLUMNS = %i[gem version source tier kind detail zr_commit date downloads].freeze
        Row = Data.define(*COLUMNS)

        # The longest detail that a row keeps; the log has the rest.
        DETAIL = 200

        attr_reader :path

        def self.compat = Dev.path("gems/compat.tsv")

        def initialize(path)
          @path = path
          @rows = {}
          return unless File.file?(path)

          File.foreach(path, chomp: true).drop(1).reject(&:empty?).each do |line|
            fields = line.split("\t", -1).map { |field| Table.unquote(field) }
            row = Row.new(**COLUMNS.zip(fields.fill("", fields.size...COLUMNS.size)).to_h)
            @rows[row.gem] = row
          end
        end

        def each(&) = @rows.values.sort_by(&:gem).each(&)

        def [](name) = @rows[name]

        def size = @rows.size

        # Adds or replaces the row of the result's gem.
        def add(result, commit:, downloads: nil, date: Date.today.iso8601)
          @rows[result.name] = Row.new(gem: result.name, version: result.version, source: result.source, tier: result.tier.to_s,
                                       kind: result.kind.to_s, detail: Table.clean(result.detail), zr_commit: commit, date: date,
                                       downloads: downloads.to_s)
        end

        def write
          lines = [COLUMNS.join("\t"), *map { |row| row.to_h.values.map { |field| Table.quote(field) }.join("\t") }]
          FileUtils.mkdir_p(File.dirname(@path))
          Paths.write_atomic(@path, "#{lines.join("\n")}\n")
        end

        # A field as a TSV reader (GitHub's, a spreadsheet's) reads it: in
        # double quotes, each one doubled, when it has a double quote. A
        # field never has a tab or a line break (Table.clean).
        def self.quote(field) = field.include?('"') ? %("#{field.gsub('"', '""')}") : field

        def self.unquote(field) = field.start_with?('"') && field.end_with?('"') && field.size > 1 ? field[1..-2].gsub('""', '"') : field

        # The detail on one line, without tabs, and at most DETAIL long.
        def self.clean(text)
          line = text.to_s.gsub(/\s+/, " ").strip
          line.size > DETAIL ? "#{line[0, DETAIL - 3]}..." : line
        end

        # The commit that the tree is at, for a row.
        def self.commit
          Dev.revision(length: 12).to_s
        end
      end
    end
  end
end
