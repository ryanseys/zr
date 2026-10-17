# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "lib/zr/dev"
require_relative "lib/zr/dev/gem_tests"
require_relative "lib/zr/dev/suite"

module Zr
  module Dev
    module Commands
      # Runs the bundled gems' own tests under ruby and in zr, and compares
      # each test, as `zr-dev cruby-test` does for test-all.
      #
      #   zr-dev gem-tests minitest rake         some gems
      #   zr-dev gem-tests --all                 every bundled gem that has tests
      #   zr-dev gem-tests rexml --update-tags   write the tags again
      #   zr-dev gem-tests --all --fetch-only    fetch the sources, run nothing
      #
      # A gem's package has no tests, so the tool fetches the gem's
      # repository at the revision that CRuby's gems/bundled_gems names
      # (else the tag of the version), into `tmp/gem-tests/src/<gem>`. It
      # runs the command of CRuby's own runner (tool/test-bundled-gems.rb)
      # once with the host ruby and once with zr as the ruby (`Suite.zr_ruby`),
      # and reads the verbose report of minitest or test-unit. The runs are
      # one at a time; the tests of a gem that start a ruby start zr.
      #
      # The tests that zr fails on purpose are tags, in
      # `test/gem_tests/tags/<gem>.txt`, one a line: the test's name, a tab,
      # and why (the file of tags is described at `Dev::GemTests::Tags`).
      # `--update-tags` keeps a reason that a `fail` tag has. A run writes
      # `log/gem-tests/results/<gem>.json` and `test/gem_tests/summary.tsv`;
      # test/unit/gem_tests_ratchet_test.rb reads them.
      #
      # A test that hangs ends the gem's run at its time limit: zr's run
      # cannot skip one test, so the tests after it count as not run.
      class GemTests < Command
        summary "Run the bundled gems' own tests in ruby and in zr, and compare each test"
        usage "<gem>... | --all [--update-tags] [--fetch-only]"
        host_ruby!

        OUT = Dev.path("log/gem-tests")
        TAGS = Dev.path("test/gem_tests/tags")
        SUMMARY = Dev.path("test/gem_tests/summary.tsv")
        SRC = Dev.path("tmp/gem-tests/src")

        # Seconds for the tests of one gem under ruby, as CRuby's runner
        # gives them: ten minutes, three times that for rbs, half a minute
        # for csv.
        LIMIT = Hash.new(600).merge("rbs" => 1800, "csv" => 30).freeze

        # zr's run gets this many times the time of ruby's: it builds the
        # programs that it runs.
        ZR_SCALE = 3

        # Seconds with no output after which zr's run counts as hung: a
        # test that starts zr builds a program first, and prints nothing.
        IDLE = 300

        # The form of ruby's kept runs, and of the environment they ran in.
        VERSION = 2

        # Runs `exec` with the second word on as the command, and the first
        # as the file for its standard error, so that the error of a gem
        # that does not start is kept apart from the report in the output.
        EXEC = "exec(*ARGV.drop(1), err: ARGV.first)"

        def defaults
          @all = false
          @update = false
          @fetch_only = false
        end

        def options(o)
          o.on("--all", "every bundled gem that has tests") { @all = true }
          o.on("--update-tags", "write the tags of each gem that ran") { @update = true }
          o.on("--fetch-only", "fetch the sources of the gems and run nothing") { @fetch_only = true }
        end

        def run(argv)
          fail!("give a gem (minitest, rake, ...) or --all") if argv.empty? && !@all
          rows = @all ? bundled.reject { Dev::GemTests::SKIPPED.key?(it.name) } : argv.map { row!(it) }
          checkouts = rows.map { fetch!(it) }
          return true if @fetch_only

          Dev.pinned!(name)
          testable, bare = checkouts.partition(&:testable?)
          bare.each { puts "#{it.row.name}: no tests that the runner can run, skipped" }
          Suite.lock! do
            Suite.pin!
            gaps = testable.sum { GemRun.new(it, rake: rake, rubylib: rubylib, update: @update).run }
            Suite.write_summary(OUT, SUMMARY)
            puts "#{gaps} gap(s) in #{testable.size} gem(s); see #{Dev.rel(OUT)} and #{Dev.rel(SUMMARY)}"
          end
          true
        end

        # The gems of CRuby's gems/bundled_gems at the pinned revision.
        def bundled = @bundled ||= Dev::GemTests::Bundled.parse(Dev.cruby("gems/bundled_gems"))

        def row!(word)
          fail!("#{word} is not run here: #{Dev::GemTests::SKIPPED[word]}") if Dev::GemTests::SKIPPED.key?(word)
          bundled.find { it.name == word } or fail!("no bundled gem #{word}; CRuby's gems/bundled_gems lists them")
        end

        def fetch!(row)
          checkout = Dev::GemTests::Checkout.new(row, root: SRC)
          commit = checkout.fetch or fail!("#{row.name}: none of #{row.revisions.join(", ")} exists at #{row.url}")
          puts "#{row.name} #{row.version}: #{commit[0, 10]} in #{Dev.rel(checkout.dir)}"
          checkout
        end

        # The rake of the host's install, which runs every gem's tests.
        def rake = @rake ||= host_output("puts Gem.bin_path('rake', 'rake')").strip

        # The load paths of the prism gem, which several gems need and
        # their tests start rubies without (CRuby's runner presets them).
        # After them comes CRuby's gems/lib, with the test helpers
        # (core_assertions, envutil) that many gems' tests require.
        def rubylib
          @rubylib ||= [*host_output("old = $:.dup; require 'prism'; puts $:-old").split("\n"),
                        File.join(Dev.ruby_src, "gems/lib")].join(File::PATH_SEPARATOR)
        end

        def host_output(script)
          out = IO.popen(ChildRuby::UNBUNDLED, [Dev.ruby, "-e", script], &:read)
          fail!("the host ruby fails on: #{script}") unless $?.success?
          out
        end

        def self.tags(gem) = tags_store.kinds(gem)
        def self.tags_store = Dev::GemTests::Tags.new(TAGS)

        # The tests of one gem, run and compared.
        class GemRun
          def initialize(checkout, rake:, rubylib:, update:)
            @checkout = checkout
            @rake = rake
            @rubylib = rubylib
            @update = update
            @name = checkout.row.name
          end

          # The count of tests that ruby passes and zr does not.
          def run
            @checkout.prepare
            result, seconds = Dev.timed { Dev::GemTests.compare(reference, execute(zr: true)) }
            Suite.write_results(OUT, @name, { @name => result }, complete: true)
            store = GemTests.tags_store
            store.write(@name, Dev::GemTests.tags_from(result, store.kinds(@name))) if @update
            report(result, seconds)
          end

          # ruby's run, from the kept runs when this gem at this commit
          # ran before.
          def reference
            key = Digest::SHA256.hexdigest([VERSION, RUBY_REVISION, @name, @checkout.row.revisions, head, command(Dev.ruby)].join("\0"))
            path = File.join(OUT, "ruby", "#{key}.json")
            return JSON.parse(File.read(path), symbolize_names: true).tap { it[:examples].transform_keys!(&:to_s) } if File.file?(path)

            run = execute(zr: false)
            unless run[:timed_out]
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, JSON.generate(run))
            end
            run
          end

          def head = Dev.git("rev-parse", "HEAD", dir: @checkout.dir).to_s.strip

          # The command of the gem's tests with `ruby` as its ruby.
          def command(ruby)
            skips = [File.join(Dev.ruby_src, "tool/rbs_skip_tests")]
            Dev::GemTests.argv(@name, ruby: ruby, rake: @rake, rbs_skips: skips)
          end

          # One run of the gem's tests, in its directory, with the time
          # limit: the tests as `Dev::GemTests.read` gives them, whether the
          # limit stopped the run, and, when no test ran, why.
          def execute(zr:)
            Dir.mktmpdir("zr-gem-tests-") do |tmp|
              stderr = File.join(tmp, "stderr")
              argv = [Dev.ruby, "-e", EXEC, stderr, *command(zr ? Suite.zr_ruby : Dev.ruby)]
              limit = LIMIT[@name] * (zr ? ZR_SCALE : 1)
              out, timed_out = Suite.capture(env(tmp, zr: zr), argv, @checkout.dir, limit, idle: (IDLE if zr))
              read = Dev::GemTests.read(out)
              read.merge(timed_out: timed_out, error: (error(stderr) if read[:examples].empty?))
            end
          end

          # The first lines of the error output, which say why no test ran.
          def error(path) = File.file?(path) ? File.read(path).scrub.lines.first(5).join[0, 400] : nil

          # The environment of a run: no bundler of the tools' own, the
          # load paths of prism, no coverage (CRuby's runner sets the
          # same), and, in zr's, its cache.
          def env(tmp, zr:)
            base = ChildRuby::UNBUNDLED.merge("RUBYLIB" => @rubylib, "SIMPLECOV_DISABLE" => "1", "TMPDIR" => tmp,
                                              "RUBY" => zr ? Suite.zr_ruby : Dev.ruby)
            zr ? base.merge(Suite.zr_env) : base
          end

          # The report of the gem, `log/gem-tests/<gem>.txt`: each test that
          # ruby passes and zr does not, with zr's message. Returns their
          # count, and prints one line.
          def report(result, seconds)
            lost = result["examples"].select { |_, (ruby, zr)| ruby == "pass" && zr != "pass" }
            gaps = result["state"] == "ran" ? lost.size : 1
            File.write(File.join(OUT, "#{@name}.txt"), [
              "# #{@name} #{@checkout.row.version}: #{result["state"]}#{", timed out" if result["timed_out"]}, #{seconds.round}s",
              result["error"].to_s.gsub(/^/, "    "),
              *lost.map { |test, (_, zr, message)| ["- #{test} [#{zr}]", ("    #{message}" if message)] }
            ].flatten.compact.join("\n") << "\n")
            _, passes, zr_passes, = Suite.counts({ "files" => { @name => result } })
            state = result["state"] == "ran" ? "" : "[#{result["state"]}] "
            puts format("%-20s %6d tests %6d pass in zr %s(%ds)", @name, passes, zr_passes, state, seconds)
            gaps
          end
        end
      end
    end
  end
end
