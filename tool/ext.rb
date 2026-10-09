# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/ext/c_api"
require_relative "lib/zr/dev/ext_rank"
require_relative "lib/zr/dev/ext_compare"
require_relative "lib/zr/dev/gems/fetched_gems"

module Zr
  module Dev
    module Commands
      # Tools for C extensions.
      class Ext < Group
        summary "Tools for C extensions"

        # Lists what a C extension takes from ruby, against zr's C API.
        #
        #   zr-dev ext imports path/to/msgpack.bundle
        #   zr-dev ext imports --all a.bundle b.o
        #
        # Each argument is a bundle or an object file. The tool prints its
        # ruby imports that the C API lacks (kernel/capi/*.rb), one a line,
        # after a count; `--all` prints every import, `+` for those that the
        # C API has and `-` for the others. It fails when one is missing,
        # as a build of the extension would.
        class Imports < Command
          summary "List a C extension's ruby imports that zr's C API lacks"
          usage "[--all] <bundle-or-object>..."

          def defaults = @all = false

          def options(o) = o.on("--all", "list every import, with + or -") { @all = true }

          def run(argv)
            fail!("give the path of a bundle or an object file") if argv.empty?

            argv.map { |path| complete?(path) }.all?
          end

          # Prints the imports of the file at `path`; whether the C API has
          # them all.
          def complete?(path)
            fail!("#{path}: no such file") unless File.file?(path)

            imports = Zr::Ext::CApi.imports(path).uniq.sort
            missing = Zr::Ext::CApi.missing(imports)
            puts "#{path}: #{imports.size} ruby imports, #{missing.size} not in zr's C API"
            (@all ? imports : missing).each { |name| puts "  #{mark(name, missing)}#{name}" }
            missing.empty?
          end

          # `+ ` or `- ` before each import under --all.
          def mark(name, missing)
            return "" unless @all

            missing.include?(name) ? "- " : "+ "
          end
        end

        # Ranks the C extensions that block the most downloaded gems.
        #
        #   zr-dev ext rank                 the ranking of the top 1000 gems
        #   zr-dev ext rank --top 300 --build
        #   zr-dev ext rank --build --only zstd-ruby,bcrypt
        #
        # `--build` builds each extension from the gem that `zr-dev gems`
        # unpacked (`--store`, tmp/gems by default), one at a time: this
        # runs the gem's extconf.rb, gem code that a sweep never runs. It
        # prints what each one lacks of the C API, then the functions to
        # add, each with the number of top gems that wait on it.
        class Rank < Command
          summary "Rank the C extensions that block the top gems, and what they lack"
          usage "[--top N] [--build] [--only NAME,...] [--store DIR]"

          def defaults
            @top = 1000
            @build = false
            @only = nil
            @store = Dev::Gems::TMP
          end

          def options(o)
            o.on("--top N", Integer, "the most downloaded N gems (1000)") { |n| @top = n }
            o.on("--build", "build each extension and list what it lacks") { @build = true }
            o.on("--only NAMES", "only these extensions, comma-separated") { |names| @only = names.split(",") }
            o.on("--store DIR", "the gems that zr-dev gems fetched (tmp/gems)") { |dir| @store = File.expand_path(dir) }
          end

          def run(argv)
            fail!("takes no arguments") unless argv.empty?

            entries = ExtRank.ranked(Dev::Gems::Table.new(Dev::Gems::Table.compat), Dev::Gems::Top.read, @top)
            entries = entries.select { |entry| @only.include?(entry.name) } if @only
            return entries.each_with_index { |entry, i| puts line(i, entry, entry.blocked.first(4).join(", ")) } unless @build

            fetched = Dev::Gems::FetchedGems.new(@store)
            reports = entries.each_with_index.map do |entry, i|
              report = ExtRank.build(entry, fetched)
              puts line(i, entry, "#{report.version} #{summary(report)}")
              report
            end
            puts "", "the C API's next functions (top gems that wait on each):"
            ExtRank.worklist(reports).each { |name, count| puts format("%5d  %s", count, name) }
            true
          end

          def line(i, entry, text) = format("%3d %4d  %-22s %s", i + 1, entry.blocked.size, entry.name, text)

          def summary(report)
            case report.status
            when :ready then "ready"
            when :lacks then "lacks #{report.missing.size}: #{report.missing.first(6).join(" ")}#{" ..." if report.missing.size > 6}"
            else "failed: #{report.detail.tr("\n", " ")[0, 160]}"
            end
          end
        end

        # Compares zr's port of a gem's C with the gem's real C extension.
        #
        #   zr-dev ext compare json stringio strscan
        #
        # For each gem, it builds each program of test/programs/stdlib/<gem>/
        # twice, with the port and with `--native-ext`, runs each binary,
        # and prints a table row: the programs that give ruby's output each
        # way, the total time, and the mean binary size.
        class Compare < Command
          summary "Compare zr's port of a gem's C with the gem's real C extension"
          usage "<gem>..."

          def run(argv)
            fail!("give the gems to compare, such as json stringio strscan") if argv.empty?

            work = File.join(Paths::ROOT, "tmp", "ext-compare")
            print ExtCompare::HEADER
            argv.each { |gem| puts ExtCompare.row(gem, ExtCompare.compare(gem, File.join(work, gem))) }
            true
          end
        end

        commands("imports" => ["List a C extension's ruby imports that zr's C API lacks", -> { Imports }],
                 "rank" => ["Rank the C extensions that block the top gems, and what they lack", -> { Rank }],
                 "compare" => ["Compare zr's port of a gem's C with the gem's real C extension", -> { Compare }])
      end
    end
  end
end
