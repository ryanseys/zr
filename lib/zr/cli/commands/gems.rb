# frozen_string_literal: true

require_relative "../command"
require_relative "../options"
require_relative "../refusals"

module Zr
  module CLI
    module Commands
      # `zr gems [--gem ...] [--gemfile PATH] [--target TRIPLE] [--json] [FILE]`:
      # every gem that a build can read, or with FILE, the gems that FILE's
      # build reads.
      class Gems < Command
        # A table: one row for each gem, and the version range of a port's C.
        #: (Array[Manifest::Row] rows) -> String
        def self.table(rows)
          return "no gems\n" if rows.empty?

          width = [rows.map { |row| row.name.size }.max, 4].max
          lines = rows.map do |row|
            port = Library::Ports::ALL[row.name]
            note = port && row.source != "stdlib" ? "  C: zr's port, #{port.compat}" : ""
            format("%-#{width}s  %-10s %s%s", row.name, row.version, row.source, note).rstrip
          end
          "#{format("%-#{width}s  %-10s %s", "NAME", "VERSION", "SOURCE")}\n#{lines.join("\n")}\n"
        end

        #: () -> bool
        def reads_help? = true

        #: (Array[String] argv) -> void
        def run(argv)
          require "json"
          require_relative "../../manifest"
          json = !argv.delete("--json").nil?
          opts = Options.parse(name, argv)
          gem_set = Options.gem_set(opts)
          rows = if opts[:input]
                   Errors.file!(opts[:input])
                   of_file(opts[:input], gem_set, Options.target_for(opts[:triple], opts[:emit], name))
                 else
                   Manifest.all(gem_set)
                 end
          json ? puts(JSON.generate(rows.map(&:to_h))) : print(Gems.table(rows))
        end

        private

        # The gems that the build of `input` reads. A refused form stops as a
        # build does.
        #: (String input, GemSet gem_set, Target target) -> Array[Manifest::Row]
        def of_file(input, gem_set, target)
          require_relative "../../runtime"
          support = EvalSupport.for(target)
          hir = Hir.build(File.read(input), input, prebuilt: support, target: target, gem_set: gem_set)
          Manifest.of_program(hir, support, gem_set)
        rescue Refused => e
          warn Refusals.refusal_report(e)
          exit REFUSED
        end
      end
    end
  end
end
