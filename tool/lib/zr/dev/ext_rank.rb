# frozen_string_literal: true

require "timeout"
require_relative "../dev"
require_relative "gems"
require_relative "gems/table"
require_relative "gems/top"
require_relative "../../../../lib/zr/ext"
require_relative "../../../../lib/zr/ext/c_api"

module Zr
  module Dev
    # The C extensions that keep the most downloaded gems from zr, worst
    # first, and what each one needs of zr's C API (`zr-dev ext rank`).
    #
    # A sweep refuses a gem whose gemspec names a C extension
    # (`cext:<name>` in gems/compat.tsv) and runs none of its code. This
    # ranks those kinds among the top gems of gems/top.tsv: by the number
    # of them that each extension blocks, then by the extension gem's own
    # downloads. A build (`build`) then runs the extension's extconf.rb and
    # compiles it from the gem that the sweep unpacked (`Ext::Builder`), and
    # lists the functions that its objects import and the C API lacks.
    module ExtRank
      # One extension: its gem, the top gems that it blocks, and the
      # downloads of its own gem.
      Entry = Data.define(:name, :blocked, :downloads)

      # What a build found: `:ready` (the C API has every import), `:lacks`
      # (`missing` names what it lacks), or `:failed` (`detail` says why).
      Report = Data.define(:entry, :version, :status, :missing, :detail)

      # The most seconds that one extension's build takes.
      BUILD_SECONDS = 600

      module_function

      # The extensions that block the top `count` gems of `top`, as the
      # rows of `table` name them, worst first.
      def ranked(table, top, count)
        names = top.keys.first(count).to_set
        blocked = table.select { |row| names.include?(row.gem) && row.kind.start_with?("cext:") }
                       .group_by { |row| row.kind.delete_prefix("cext:") }
        entries = blocked.map { |name, rows| Entry.new(name, rows.map(&:gem).sort, top.fetch(name, 0)) }
        entries.sort_by { |entry| [-entry.blocked.size, -entry.downloads, entry.name] }
      end

      # Builds the extension of `entry` from the newest version of its gem
      # that `fetched` (Gems::FetchedGems) unpacked, in a child that stops
      # after `seconds`, and reports what the C API lacks.
      def build(entry, fetched, seconds: BUILD_SECONDS)
        subject = fetched.versions(entry.name).max_by { |s| Gem::Version.new(s.version) }
        return Report.new(entry, nil, :failed, [], "not fetched; run `zr-dev gems try #{entry.name}`") unless subject

        spec = Gem::Specification.load(File.join(fetched.specifications, "#{File.basename(subject.root)}.gemspec"))
        extconfs = spec&.extensions.to_a.grep(/extconf\.rb\z/)
        return Report.new(entry, subject.version, :failed, [], "no extconf.rb (#{spec&.extensions.to_a.join(", ")})") if extconfs.empty?

        imports = in_child(seconds) do
          extconfs.flat_map { |extconf| Ext::CApi.imports(*Ext::Builder.new(File.join(subject.root, extconf)).source(subject.root).objects) }
                  .uniq
        end
        missing = Ext::CApi.missing(imports).sort
        return Report.new(entry, subject.version, :failed, [], "imports nothing of ruby's C API (an FFI library?)") if imports.empty?

        Report.new(entry, subject.version, missing.empty? ? :ready : :lacks, missing, "")
      rescue Refused, ChildFailed => e
        Report.new(entry, subject&.version, :failed, [], e.message.lines.first(3).join.strip)
      end

      # A build that its child did not finish.
      class ChildFailed < StandardError; end

      # Runs the block in a child process of its own group, and returns
      # its value; a child that runs past `seconds` is killed with every
      # process it started (cc, make).
      def in_child(seconds)
        reader, writer = IO.pipe
        pid = fork do
          reader.close
          Process.setpgid(0, 0)
          value = begin
            [:ok, yield]
          rescue StandardError => e
            [:error, e.message]
          end
          writer.write(Marshal.dump(value))
          exit!(0)
        end
        writer.close
        data = Timeout.timeout(seconds) { reader.read }
        Process.wait(pid)
        # Our own child wrote it.
        status, value = Marshal.load(data)
        status == :ok ? value : raise(ChildFailed, value)
      rescue Timeout::Error
        Process.kill("KILL", -pid)
        Process.wait(pid)
        raise ChildFailed, "the build ran past #{seconds} s"
      rescue ArgumentError, TypeError # the child died before it wrote
        raise ChildFailed, "the build stopped"
      ensure
        reader&.close
      end

      # The functions that the extensions lack, each with the number of
      # top gems that the extensions that lack it block, most first.
      def worklist(reports)
        counts = Hash.new(0)
        reports.each { |report| report.missing.each { |name| counts[name] += report.entry.blocked.size } }
        counts.sort_by { |name, count| [-count, name] }
      end
    end
  end
end
