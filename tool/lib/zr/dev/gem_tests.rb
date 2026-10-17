# frozen_string_literal: true

require "fileutils"
require_relative "../dev"

module Zr
  module Dev
    # The parts of `zr-dev gem-tests` (tool/gem_tests.rb) that need neither
    # the network nor zr: the list of bundled gems, the choice of a
    # revision, the test command of a gem, the reader of a test run, and
    # the tags. The tests of this module are test/unit/gem_tests_test.rb.
    module GemTests
      # One line of CRuby's gems/bundled_gems: a gem, the released version
      # that ruby bundles, the repository that holds its tests, and
      # sometimes the revision to test.
      Bundled = Data.define(:name, :version, :url, :revision) do
        # The gems of the file's text, in its order. A comment and a blank
        # line give none.
        def self.parse(text) = text.each_line.filter_map { parse_line(it) }

        def self.parse_line(line)
          name, version, url, revision = line.split("#", 2).first.split
          new(name: name, version: version, url: url, revision: revision) if url
        end

        # What to fetch, in the order to try. Without a revision, the tag
        # of the version: "v<version>", else "<version>" (as CRuby's own
        # runner has it).
        def revisions = revision ? [revision] : ["v#{version}", version]
      end

      # A gem's repository in a directory, at the revision of its row.
      # Only `git` runs, and nothing is ever deleted.
      class Checkout
        attr_reader :row, :dir

        def initialize(row, root:)
          @row = row
          @dir = File.join(root, row.name)
        end

        # The commit that the directory now holds, or nil when no
        # revision of the row exists at the repository. The directory is
        # reused when its HEAD already is the commit of a revision.
        def fetch
          FileUtils.mkdir_p(dir)
          git("init", "-q") unless File.exist?(File.join(dir, ".git"))
          # (Not `git remote`: a global `remote.origin.prune` makes it list origin in a new repository.)
          git("remote", "add", "origin", row.url) unless git("config", "--get", "remote.origin.url")
          return head if row.revisions.any? { current?(it) }

          row.revisions.each do |rev|
            next unless git(*fetch_arguments(rev))

            return head if git("checkout", "--quiet", "--force", "--detach", rev)
          end
          nil
        end

        # Whether the gem has tests that its runner can run: a test
        # directory, and the library that the tests load.
        def testable?
          name = row.name
          File.directory?(File.join(dir, "test")) &&
            [name, name.tr("-", "/")].any? { File.exist?(File.join(dir, "lib", "#{it}.rb")) }
        end

        # The files that CRuby's runner takes out of a gem's copy before it
        # runs the tests: rbs tests the JSON additions that json 3 removed.
        def prepare
          return unless row.name == "rbs"

          RBS_JSON_TESTS.each { |path| FileUtils.rm_f(File.join(dir, path)) }
        end

        private

        def git(*args) = Dev.git(*args, dir: dir)

        def head = git("rev-parse", "HEAD").to_s.strip

        def current?(rev) = git("rev-parse", "--verify", "--quiet", "#{rev}^{commit}")&.strip == head

        # A commit is fetched by its hash, a tag by its name.
        def fetch_arguments(rev)
          rev.match?(/\A\h{40}\z/) ? ["fetch", "--depth", "1", "origin", rev] : ["fetch", "--depth", "1", "origin", "tag", rev]
        end
      end

      RBS_JSON_TESTS = %w[BigDecimal Complex DateTime Date Exception OpenStruct Range Rational Regexp Set Struct Symbol Time]
                       .map { "test/stdlib/json/JSON#{it}_test.rb" }.freeze

      # The gems that CRuby's runner does not run on this platform, and why
      # (tool/test-bundled-gems.rb): both run on Windows only.
      SKIPPED = {
        "debug" => "it needs a pty, so CRuby's runner runs it on Windows only",
        "win32ole" => "it is for Windows"
      }.freeze

      # The script that requires each of minitest's test files.
      MINITEST_RUN = 'Dir.glob("test/minitest/test_*.rb").sort.each { require "./#{it}" }'

      # The script that requires each of reline's test files, as its
      # Rakefile's UTF-8 task does.
      RELINE_RUN = 'RELINE_TEST_ENCODING = Encoding::UTF_8; Dir.glob("test/reline/test_*.rb").sort.each { require "./#{it}" }'

      # The command of a gem's tests, run in the gem's directory, as
      # CRuby's runner has it: `rake test`, or the gem's own script. Each
      # asks for the verbose report: one line a test, with its name and
      # its result. `rake` is the rake of the host's install. minitest's
      # Rakefile needs hoe, which CRuby's runner has from the gems' bundle,
      # so its test files are required directly. So are reline's: its
      # tasks load each file as a feature, so a TESTOPTS of -v is a file
      # too. They run under UTF-8, one of the four encodings that its
      # Rakefile runs them under, because each run has the same names.
      def self.argv(name, ruby:, rake:, rbs_skips: [])
        case name
        when "rbs"
          [ruby, rake, "stdlib_test", "validate", "RBS_SKIP_TESTS=#{rbs_skips.join(File::PATH_SEPARATOR)}",
           "SKIP_RBS_VALIDATION=true", "TESTOPTS=-v"]
        when "rexml" then [ruby, "test/run.rb", "--ignore-name=/linear_performance/", "-v"]
        when "test-unit" then [ruby, "test/run.rb", "-v"]
        when "csv" then [ruby, "run-test.rb", "-v"]
        when "minitest" then [ruby, "-Ilib", "-Itest", "-e", MINITEST_RUN, "--", "-v"]
        when "reline" then [ruby, "-I.", "-Ilib", "-Itest", "-e", RELINE_RUN, "--", "-v"]
        else [ruby, rake, "test", "TESTOPTS=-v"]
        end
      end

      # The tests of a run, as { examples: { name => [status, message] },
      # ended:, hung: }, from the verbose report of minitest or of
      # test-unit. A status is "pass", "fail", "error" or "skip". `ended`
      # says that the run printed its totals; `hung` names the test that
      # started and did not end (the last line stops before its result).
      def self.read(out)
        lines = out.dup.force_encoding(Encoding::UTF_8).scrub.lines
        partial = lines.pop.chomp unless lines.empty? || lines.last.end_with?("\n")
        lines = lines.map(&:chomp)
        ended = lines.any? { it.match?(/\A\d+ (?:runs|tests), \d+ assertions, /) }
        partial = nil if ended
        minitest = read_minitest(lines, partial)
        test_unit = read_test_unit(lines, partial)
        { examples: minitest[:examples].merge(test_unit[:examples]), ended: ended, hung: minitest[:hung] || test_unit[:hung] }
      end

      # minitest: `Class#test_name = 0.01 s = .`. The report after the run
      # gives the message of each test that did not pass: `1) Failure:`,
      # then the test's name, then the message.
      def self.read_minitest(lines, partial)
        marks = { "." => "pass", "F" => "fail", "E" => "error", "S" => "skip" }
        examples = {}
        lines.each_with_index do |line, i|
          if (found = line.match(/\A(?<name>\S.*#.+) = \d+(?:\.\d+)? s = (?<mark>[.FES])\z/))
            examples[found[:name]] = [marks.fetch(found[:mark])]
          elsif line.match?(/\A\s+\d+\) (?:Failure|Error|Skipped):\z/) && (name = lines[i + 1].to_s[/\A(.+#.+?)(?: \[.*\])?:\z/, 1])
            examples[name]&.push(lines[i + 2].to_s[0, 200])
          end
        end
        { examples: examples, hung: (partial[/\A(\S.*#.+) = /, 1] if partial) }
      end

      # test-unit: a heading `Class: ` for each test case, nested ones
      # (`sub_test_case`) indented by two more spaces, and under it
      # `  test_name:<tabs>.: (0.001)`. A test that did not pass has its
      # report between two lines of `=`, printed before the time. The
      # message is the first line of that report.
      def self.read_test_unit(lines, partial)
        marks = { "." => "pass", "N" => "pass", "F" => "fail", "E" => "error", "P" => "skip", "O" => "skip" }
        examples = {}
        scope = []
        reporting = false
        last = nil
        lines.each do |line|
          if line.match?(/\A={79}\z/)
            reporting = !reporting
          elsif reporting
            examples[last]&.push(line[0, 200]) if last
            last = nil
          elsif (found = line.match(/\A(?<indent> *)(?<name>\S.*?):\t+(?<mark>[.FEPON])(?:: \(\d+(?:\.\d+)?\))?\z/))
            name = "#{scope.first(found[:indent].size / 2).join("::")}##{found[:name]}"
            examples[name] = [marks.fetch(found[:mark])]
            last = name unless found[:mark] == "."
          elsif (heading = line.match(/\A(?<indent> *)(?<name>\S.*?): ?\z/))
            scope = scope.first(heading[:indent].size / 2) << heading[:name]
          end
        end
        { examples: examples, hung: test_unit_hung(partial, scope) }
      end

      # The test of the last, unfinished line of a test-unit run.
      def self.test_unit_hung(partial, scope)
        found = partial&.match(/\A(?<indent> *)(?<name>\S.*?):\t+\z/) or return
        "#{scope.first(found[:indent].size / 2).join("::")}##{found[:name]}"
      end

      # The results of a gem: ruby's run and zr's, test by test, in the
      # form that Suite writes (one "file", the gem). A run of zr that
      # printed no test and did not time out never started its tests: the
      # gem does not "load", and `error` says why.
      def self.compare(ruby, zr)
        examples = (ruby[:examples].keys | zr[:examples].keys).to_h do |name|
          status, message = zr[:examples][name] || ["missing", nil]
          [name, [ruby[:examples].dig(name, 0) || "missing", status, message].compact]
        end
        load = zr[:examples].empty? && !zr[:timed_out] && !ruby[:examples].empty?
        { "state" => load ? "load" : "ran", "ended" => zr[:ended], "timed_out" => zr[:timed_out],
          "error" => (zr[:error] if load), "hung" => zr[:hung], "examples" => examples }.compact
      end

      # The tags of a gem from its results, as { name => kind }: each test
      # that ruby passes and zr does not `fails`; the one that zr hung in
      # `hangs`, as does one that an earlier run tagged `hangs` and zr
      # still does not reach. A gem that does not load has the tag "" with
      # "load".
      def self.tags_from(result, old)
        return { "" => result["state"] } if result["state"] == "load"

        result["examples"].each_with_object({}) do |(name, (ruby, zr)), tags|
          next unless ruby == "pass" && zr != "pass"

          hangs = name == result["hung"] || (zr == "missing" && old[name] == "hangs")
          tags[name] = hangs ? "hangs" : "fails"
        end
      end

      # The tags of gems, in a directory of `<gem>.txt` files: one line a
      # test, its name, a tab, and why:
      #
      #   Foo#test_x<TAB>fail      zr fails it
      #   Foo#test_y<TAB>timeout   zr stops or loops in it
      #   *<TAB>load               the gem's tests do not start
      #
      # Another reason (`cext`, `ractor`, ...) is a `fail` that says why.
      class Tags
        def initialize(dir) = @dir = dir

        def path(gem) = File.join(@dir, "#{gem}.txt")

        # The tags as they are written: { name => why }.
        def reasons(gem)
          return {} unless File.file?(path(gem))

          File.readlines(path(gem), chomp: true).to_h { it.split("\t", 2) }
        end

        # The tags as { name => kind }, "fails" or "hangs"; the gem's own
        # tag is under "".
        def kinds(gem)
          reasons(gem).to_h do |name, why|
            next ["", why] if name == "*"

            [name, why == "timeout" ? "hangs" : "fails"]
          end
        end

        # Writes the tags again from { name => kind }. A reason that a
        # `fails` tag had stays; any other gets "fail" or "timeout".
        def write(gem, kinds)
          old = reasons(gem)
          lines = kinds.map do |name, kind|
            next "*\t#{kind}" if name.empty?

            why = old[name] if kind == "fails" && old[name] && old[name] != "timeout"
            "#{name}\t#{why || (kind == "hangs" ? "timeout" : "fail")}"
          end
          return FileUtils.rm_f(path(gem)) if lines.empty?

          FileUtils.mkdir_p(@dir)
          File.write(path(gem), lines.join("\n") << "\n")
        end
      end
    end
  end
end
