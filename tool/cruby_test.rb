# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require_relative "lib/zr/dev"
require_relative "lib/zr/dev/suite"

module Zr
  module Dev
    # Runs CRuby's own tests (test-all, `test/` of ruby 4.0.7's checkout)
    # under ruby and in zr binaries, and compares each test.
    #
    #   zr-dev cruby-test ruby                      test/ruby
    #   zr-dev cruby-test ruby -f test_array        the files that match
    #   zr-dev cruby-test json stringio             some directories
    #   zr-dev cruby-test --all [--shard 2/4]       every directory
    #   zr-dev cruby-test ruby --update-tags        write the tags again
    #
    # Each test file runs on CRuby's own runner (tool/lib/test/unit.rb),
    # compiled into a binary with its directory's other files
    # (`Suite::Area`). A test that starts a ruby (`assert_separately`,
    # `assert_in_out_err`, `EnvUtil.invoke_ruby`) starts zr, through
    # `RUBY`.
    #
    # The tests that zr fails on purpose are tags, in
    # `test/cruby/tags/<dir>/<file>.txt`, one a line: the test's name, a
    # tab, and why:
    #
    #   TestArray#test_pack<TAB>fail      zr fails it
    #   TestThread#test_x<TAB>timeout     zr stops or loops in it; its run skips it
    #   *<TAB>build                       the file does not build
    #   *<TAB>load                        the file raises as it loads
    #
    # Another reason (`cext`, `ractor`, `rubyvm`, `spawns`) is a `fail` that says
    # why; `--update-tags` keeps it. A run writes
    # `log/cruby-test/results/<dir>.json` and `test/cruby/summary.tsv`;
    # test/unit/cruby_test_ratchet_test.rb reads them.
    class CRubyTest < Command
      summary "Run CRuby's test-all in ruby and in zr binaries, and compare each test"
      usage "<dir>... | --all [-f PATTERN] [-j JOBS] [--shard I/N] [--update-tags] [--keep]"
      host_ruby!

      # Seconds for one test file. Its tests that start a ruby compile
      # their code with zr, so this is longer than ruby/spec's limit.
      LIMIT = 600

      # Seconds with no output after which a test counts as hung. A test
      # that starts zr builds a program first, which prints nothing, and
      # one test can start several.
      IDLE = 300

      # The runner's scale for the time limits of the rubies a test starts
      # (EnvUtil.apply_timeout_scale), as CRuby's CI sets it for slow
      # platforms: in zr, each one builds its program first, for 8 s or
      # more, where ruby's limit is often 10 s.
      TIMEOUT_SCALE = "10"

      # The directories of test/ that test what only CRuby has, and why.
      CRUBY_ONLY = {
        "dtrace" => "dtrace probes of CRuby's C code",
        "mkmf" => "building C extensions",
        "-ext-" => "ruby's C API, through the test extensions",
        "objspace" => "ObjectSpace's dump of CRuby's heap"
      }.freeze

      # The files of test/ruby that test CRuby's VM, and why.
      CRUBY_ONLY_FILES = {
        "ruby/test_iseq.rb" => "RubyVM::InstructionSequence's bytecode",
        "ruby/test_yjit.rb" => "YJIT",
        "ruby/test_zjit.rb" => "ZJIT",
        "ruby/test_yjit_exit_locations.rb" => "YJIT",
        "ruby/test_rubyvm.rb" => "RubyVM's internals",
        "ruby/test_shapes.rb" => "CRuby's object shapes"
      }.freeze

      # The order of `--all`: test/ruby first, then the libraries.
      FIRST = %w[ruby].freeze

      OUT = Dev.path("log/cruby-test")
      TAGS = Dev.path("test/cruby/tags")
      SUMMARY = Dev.path("test/cruby/summary.tsv")

      # The form of the program and of ruby's kept results.
      VERSION = 2

      def defaults
        @filter = nil
        @jobs = 2
        @keep = false
        @all = false
        @shard = nil
        @update = false
      end

      def options(o)
        o.on("-f PATTERN", "only the test files whose path matches") { |v| @filter = Regexp.new(v) }
        o.on("-j JOBS", Integer, "files to run at once (default 2)") { |v| @jobs = v }
        o.on("--all", "every directory, test/ruby first") { @all = true }
        o.on("--shard I/N", "with --all: the I-th of N equal shares of the directories") { |v| @shard = v.split("/").map(&:to_i) }
        o.on("--update-tags", "write the tags of each file that ran") { @update = true }
        o.on("--keep", "keep the binaries") { @keep = true }
      end

      def run(argv)
        Dev.pinned!(name)
        fail!("give a directory of test/ (ruby, json, ...) or --all") if argv.empty? && !@all
        root = checkout!
        dirs = @all ? all_dirs(root) : argv.map { |d| dir!(root, d) }
        dirs = shard(dirs) if @shard
        Suite.lock! do
          Suite.pin!
          gaps = dirs.sum do |dir|
            Area.new(root, dir, filter: @filter, jobs: @jobs, keep: @keep, update: @update).run
          end
          Suite.write_summary(OUT, SUMMARY)
          puts "#{gaps} gap(s) in #{dirs.size} director(ies); see #{Dev.rel(OUT)} and #{Dev.rel(SUMMARY)}"
        end
        true
      end

      # The test directory of the CRuby checkout at RUBY_REVISION.
      def checkout!
        src = Dev.ruby_src
        head = Dev.git("rev-parse", "HEAD", dir: src, err: $stderr).to_s.strip
        fail!("#{src} is at #{head[0, 10]}, not ruby #{RUBY} (#{RUBY_REVISION[0, 10]})") unless head == RUBY_REVISION
        src
      end

      def dir!(root, word)
        word = word.delete_suffix("/")
        fail!("test/#{word} is CRuby's alone: #{CRUBY_ONLY[word]}") if CRUBY_ONLY.key?(word)
        fail!("no directory test/#{word} in #{root}") unless File.directory?(File.join(root, "test", word))
        word
      end

      def all_dirs(root)
        dirs = Dir.children(File.join(root, "test")).sort.select do |d|
          File.directory?(File.join(root, "test", d)) && !CRUBY_ONLY.key?(d) && !%w[lib fixtures].include?(d)
        end
        FIRST + (dirs - FIRST)
      end

      def shard(dirs)
        index, count = @shard
        fail!("--shard takes I/N with 1 <= I <= N") unless count.to_i.positive? && index.to_i.between?(1, count)
        dirs.select.with_index { |_, i| i % count == index - 1 }
      end

      # The tags of one test file, as { name => kind } ("fails" or
      # "hangs"; the file's own, "build" or "load", under "").
      def self.tags(rel) = reasons(rel).to_h { |name, why| [name == "*" ? "" : name, kind(name, why)] }

      def self.kind(name, why)
        return why if name == "*"

        why == "timeout" ? "hangs" : "fails"
      end

      # The tags of one test file as they are written: { name => why }.
      def self.reasons(rel)
        path = tags_path(rel)
        return {} unless File.file?(path)

        File.readlines(path, chomp: true).to_h { |line| line.split("\t", 2) }
      end

      def self.tags_path(rel) = File.join(TAGS, rel.sub(/\.rb\z/, ".txt"))

      # One directory of test/ (`Suite::Area` runs it).
      class Area < Suite::Area
        def initialize(root, dir, filter:, **)
          @src = root
          base = File.join(root, "test")
          files = Dir.glob(File.join(base, dir, "**", "test_*.rb")).sort
          files.reject! { |f| CRUBY_ONLY_FILES.key?(f.delete_prefix("#{base}/")) || f.include?("/-ext-/") }
          files.select! { |f| f.match?(filter) } if filter
          super(out: OUT, root: base, area: dir, files: files, filtered: !filter.nil?, **)
        end

        def version = VERSION
        def limit = LIMIT
        def idle = IDLE
        def tags(rel) = CRubyTest.tags(rel)
        def program(files) = CRubyTest.program(@src, files)
        def read(out) = CRubyTest.read(out)

        # The runner's options: zr's run skips the tests tagged `timeout`,
        # and those in `skip`, which hung in this run.
        def arguments(file, zr:, skip: [])
          hung = zr ? tags(rel(file)).select { |_, kind| kind == "hangs" }.keys | skip : []
          skip = hung.empty? ? [] : ["-n", "/./", "-n", "!/\\A(?:#{hung.map { |n| Regexp.escape(n) }.join("|")})\\z/"]
          [file, *skip]
        end

        # A test that starts a ruby starts the interpreter of the run.
        def env(dir, zr:)
          super.merge("RUBY" => zr ? Suite.zr_ruby : RbConfig.ruby, "TMPDIR" => dir, "RUBY_TEST_TIMEOUT_SCALE" => (TIMEOUT_SCALE if zr))
        end

        def write_tags(rel, result)
          old = CRubyTest.reasons(rel)
          lines = tags_from(result, tags(rel)).map do |name, kind|
            next "*\t#{kind}" if name.empty?

            why = old[name] if old[name] && old[name] != "timeout" && kind == "fails"
            "#{name}\t#{why || (kind == "hangs" ? "timeout" : "fail")}"
          end
          path = CRubyTest.tags_path(rel)
          return FileUtils.rm_f(path) if lines.empty?

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, lines.join("\n") << "\n")
        end
      end

      # The program of `files`: CRuby's runner, then each file behind a
      # test of the first argument, so one binary runs any one of its
      # files. The other arguments go to the runner. A file that raises as
      # it loads is reported.
      # Stand-ins for the C extensions that only CRuby's own tests load
      # (ext/-test-/*), last on the load path.
      STAND_INS = File.expand_path("lib/zr/dev/cruby_test", __dir__)

      def self.program(src, files)
        load_path = [File.join(src, "tool/lib"), File.join(src, "test/lib"), *files.map { |f| File.dirname(f) }.uniq, STAND_INS]
        lines = [
          "# frozen_string_literal: false",
          "$LOAD_PATH.unshift(#{load_path.map(&:inspect).join(", ")})",
          "file = ARGV.shift",
          # --show-skip lists each test that called omit, so it reads as a
          # skip, not a pass.
          'ARGV.replace(["-v", "--tty=no", "--show-skip", *ARGV])',
          'require "test/unit"',
          # tool/test/init.rb, minus its checkers of CRuby internals: experimental
          # warnings are off, and iseq_loader_checker loads tempfile (and with it
          # tmpdir), which some tests use without a require.
          "Warning[:experimental] = false",
          'require "tempfile"',
          "case file"
        ]
        files.each do |f|
          lines << "when #{f.inspect}"
          lines << "  begin"
          lines << "    require #{f.inspect}"
          lines << "  rescue Exception => e"
          lines << "    STDOUT.puts \"ZRTEST\\tload\\t\#{e.class}: \#{e.message.lines.first.to_s.chomp}\""
          lines << "    exit!(1)"
          lines << "  end"
        end
        lines << "end"
        lines.join("\n") << "\n"
      end

      # The tests of a run, in the order they ran. Each `[i/n] Class#test =
      # t s` line is a test that ended; the report after the run gives
      # each that failed (`n) Failure:`, `Error:`, `Timeout:`), with its
      # message on the next line.
      def self.read(out)
        examples = {}
        load = nil
        lines = out.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
        lines.each_with_index do |line, i|
          if (name = line[/\A\[\s*\d+\/\d+\] (\S+#\S+) = [\d.]+ s/, 1])
            examples[name] ||= ["pass"]
          elsif (kind = line[/\A\s+\d+\) (Failure|Error|Timeout|Skipped):\z/, 1])
            name = lines[i + 1].to_s[/\A(\S+#\S+?):?(?: \[|\z)/, 1] or next
            status = { "Failure" => "fail", "Skipped" => "skip" }.fetch(kind, "error")
            examples[name] = [status, lines[i + 2].to_s[0, 200]]
          elsif line.start_with?("ZRTEST\tload\t")
            load = line.split("\t", 3).last
          end
        end
        ended = lines.any? { |l| l.start_with?("Finished tests in") }
        # The test that started and did not end: `[i/n] Class#test` with no
        # time after it, on the last line of its kind.
        started = lines.reverse_each.find { |l| l.match?(/\A\[\s*\d+\/\d+\] \S+#\S+/) }
        hung = started[/\A\[\s*\d+\/\d+\] (\S+#\S+)/, 1] if started && !ended && !started.match?(/ = [\d.]+ s/)
        { examples: examples, load: load, ended: ended, hung: hung }
      end
    end
  end
end
