# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../../../../lib/zr/cli/runner"

module Zr
  module Dev
    # What the two suites of ruby's own tests share: `zr-dev rubyspec`
    # (ruby/spec) and `zr-dev cruby-test` (CRuby's test-all). Each runs
    # every example under ruby and in a zr binary, writes the results of
    # an area to `log/<suite>/results/<area>.json`, and keeps the examples
    # that zr fails on purpose as tags in `test/<suite>/tags/`. The ratchet
    # tests read the results and the tags (`Suite.problems`); they never
    # compile.
    module Suite
      # The lock that keeps a second suite from starting while one runs:
      # each suite builds large binaries and runs them in parallel.
      LOCK = Dev.path("tmp/suite.lock")

      # Bumped when the form of a results file changes, so that a ratchet
      # skips the old files.
      FORMAT = 1

      module_function

      # Runs the block while this process holds the lock, or stops.
      def lock!
        FileUtils.mkdir_p(File.dirname(LOCK))
        File.open(LOCK, File::RDWR | File::CREAT) do |f|
          abort "zr-dev: another suite runs (#{f.read.strip}); run one suite at a time" unless f.flock(File::LOCK_EX | File::LOCK_NB)

          f.truncate(0)
          f.write("pid #{Process.pid}: #{$PROGRAM_NAME} #{ARGV.join(" ")}")
          f.flush
          yield
        end
      end

      # The copy of zr that a suite runs. `pin!` copies the checkout's
      # zr into it when the suite starts, so the checkout can change while
      # the suite runs: its builds and the zr that its tests start read
      # only this copy.
      PIN = Dev.path("tmp/suite/zr")

      # What zr reads below its root: the command, the compiler with its
      # runtime, and the vendored libraries.
      PINNED = %w[exe lib vendor].freeze

      # Copies the checkout's zr, with the changes that are not committed,
      # to PIN, and records its version. The lock holds, so no other suite
      # uses the copy.
      # rubocop:disable ThreadSafety/ClassInstanceVariable -- one suite runs at a time (the lock)
      def pin!
        @version = checkout_version
        FileUtils.rm_rf(PIN)
        FileUtils.mkdir_p(PIN)
        PINNED.each { |dir| FileUtils.cp_r(Dev.path(dir), File.join(PIN, dir)) }
        puts "zr-dev: the suite runs a copy of zr at #{@version[0, 19]} (#{Dev.rel(PIN)}); the checkout may change"
      end

      # The zr command of the copy.
      def zr = File.join(PIN, "exe/zr")

      # The zr that a test starts as its ruby: the copy, pinned to the host
      # ruby and the checkout's cache, so it starts with any environment,
      # as a ruby binary does.
      def zr_ruby = Zr::CLI::Runner.pinned_launcher(zr, ruby: Dev.ruby, flags: ["--cache-dir=#{Dev.path("tmp/cache")}"])

      # The environment of the copy. It is not a checkout, so its cache
      # is named: the checkout's, whose entries are keyed by digests. It
      # trims nothing, and builds alone, as the build server builds from
      # the checkout.
      def zr_env = { "ZR_CACHE" => Dev.path("tmp/cache"), "ZR_CACHE_MAX_GB" => "0", "ZR_SERVER" => "0" }

      # The ruby tree of the copy, which a program that the copy runs gets as
      # its home (ZR_HOME, `CLI::Runner.program_env`).
      def zr_home = File.realpath(File.join(PIN, "vendor/ruby"))

      # The version of zr that a run tested: the one `pin!` copied.
      def zr_version = @version || checkout_version
      # rubocop:enable ThreadSafety/ClassInstanceVariable

      # The checkout's version: the commit, and a digest of the changes
      # that are not committed.
      def checkout_version
        head = Dev.git("rev-parse", "HEAD").to_s.strip
        diff = Dev.git("diff", "HEAD").to_s
        diff.empty? ? head : "#{head}+#{Digest::SHA256.hexdigest(diff)[0, 12]}"
      end

      # One area's results: for each file, how its run ended (`state`:
      # "ran", "build" or "load") and each example by name, with ruby's
      # status, zr's status and zr's message. A status is "pass", "fail",
      # "error", "skip" or "missing" (the run ended before the example).
      # `complete` says that the files are all the files of the area, so the
      # summary can count the area from them.
      def write_results(dir, area, files, complete:)
        path = File.join(dir, "results", "#{area.tr("/", "-")}.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate({ "format" => FORMAT, "revision" => RUBY_REVISION, "zr" => zr_version,
                                                "area" => area, "complete" => complete, "files" => files }))
        path
      end

      # The results files of a suite that this ruby revision and FORMAT
      # wrote, by area.
      def results(dir)
        Dir[File.join(dir, "results", "*.json")].sort.filter_map do |path|
          data = JSON.parse(File.read(path))
          [data["area"], data] if data["format"] == FORMAT && data["revision"] == RUBY_REVISION
        end.to_h
      end

      # What a ratchet reports for one area. `tags` gives a file's tags as
      # { name => kind }, a kind being "fails" or "hangs"; the file's own
      # tag is under the name "" ("build" or "load").
      #
      # - a regression: an example that ruby passes and zr does not, with
      #   no tag;
      # - a stale tag: an example tagged `fails` that zr now passes, or a
      #   file tagged `build` or `load` that now builds and loads;
      # - a file that does not build or load, with no tag that says so.
      def problems(data, tags)
        data["files"].flat_map do |file, run|
          tagged = tags.call(file)
          own = tagged[""]
          state = run["state"]
          next ["#{file}: does not #{state}, and has no fails(#{state}) tag"] if %w[build load].include?(state) && own != state
          next ["#{file}: stale fails(#{own}) tag: the file #{own}s now"] if %w[build load].include?(own) && state == "ran"
          next [] if %w[build load].include?(state)

          run["examples"].flat_map do |name, (ruby, zr)|
            kind = tagged[name]
            if ruby == "pass" && zr != "pass" && kind.nil?
              ["#{file}: #{name}: zr #{zr == "missing" ? "never ran it" : "fails it"}, ruby passes, and it has no tag"]
            elsif kind == "fails" && zr == "pass"
              ["#{file}: #{name}: stale tag, zr passes it now"]
            else
              []
            end
          end
        end
      end

      # The counts of one area for the summary: files, the examples that
      # ruby passes, the ones zr passes too, and the files that do not
      # build or load in zr.
      def counts(data)
        runs = data["files"].values
        passing = runs.flat_map { |run| run["examples"].values }.select { |statuses| statuses.first == "pass" }
        [runs.size, passing.size, passing.count { |_, zr| zr == "pass" },
         runs.count { |run| run["state"] == "build" }, runs.count { |run| run["state"] == "load" }]
      end

      # Writes the summary of a suite again: one row for each area, and a
      # total. An area whose results are complete gets its row from them.
      # Every other area keeps the row that the summary had, so a run of
      # some files or of some areas never drops or shrinks a row.
      def write_summary(dir, path)
        kept = summary_rows(path)
        results(dir).each { |area, data| kept[area] = counts(data) if data["complete"] }
        rows = kept.sort.map { |area, counts| [area, *counts] }
        total = ["total", *(rows.empty? ? [0] * 5 : rows.transpose.drop(1).map(&:sum))]
        header = %w[area files ruby_passes zr_passes no_build no_load]
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, [header, *rows, total].map { |row| row.join("\t") }.join("\n") << "\n")
      end

      # The rows of the summary at `path`, by area, without the header and
      # the total.
      def summary_rows(path)
        return {} unless File.file?(path)

        File.readlines(path, chomp: true).drop(1).each_with_object({}) do |line, rows|
          area, *counts = line.split("\t")
          rows[area] = counts.map { |n| Integer(n) } unless area == "total"
        end
      end

      # A suite started in the background inherits SIGINT ignored, and a
      # program keeps an ignored signal, as ruby does. The programs run as
      # from a terminal, with SIGINT at its default, so a spec that sends
      # itself SIGINT sees an Interrupt.
      def foreground_signals!
        old = Signal.trap("INT", "DEFAULT")
        Signal.trap("INT", old) unless old == "IGNORE"
      end

      # Runs `argv` in `dir` with a time limit, and returns its standard
      # output and whether a limit stopped it: `limit` seconds in all, or
      # `idle` seconds with no output (a test that hangs).
      # `live`, when given, gets each whole line of the output as it comes.
      def capture(env, argv, dir, limit, idle: nil, live: nil)
        foreground_signals!
        reader, writer = IO.pipe
        pid = Process.spawn(env, *argv, chdir: dir, in: File::NULL, out: writer, err: File::NULL, pgroup: true)
        writer.close
        out = +""
        clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        heard = clock.call
        collector = Thread.new do
          told = 0
          loop do
            out << reader.readpartial(65_536)
            heard = clock.call
            next unless live && (last = out.rindex("\n", -1)) && last >= told

            out.byteslice(told, last + 1 - told).each_line { |line| live.call(line.chomp) }
            told = last + 1
          end
        rescue IOError
          nil
        end
        deadline = clock.call + limit
        timed_out = false
        until collector.join(1)
          next unless clock.call > deadline || (idle && clock.call - heard > idle)

          timed_out = true
          kill(pid)
          collector.join(5)
          break
        end
        Process.wait(pid)
        [out.force_encoding(Encoding::BINARY), timed_out]
      ensure
        reader&.close
      end

      # The process group, or the process alone when the group is gone: a
      # test can start its own session (`Process.setsid`).
      def kill(pid)
        %w[TERM KILL].each do |signal|
          begin
            Process.kill("-#{signal}", pid)
          rescue Errno::ESRCH, Errno::EPERM
            Process.kill(signal, pid)
          end
          sleep 1
        end
      rescue Errno::ESRCH
        nil
      end

      # One area of a suite: its binaries, its runs, its results and its
      # tags. A subclass gives the program of some files (`program`), how
      # to read a run's output (`read`), and the tags (`tags`,
      # `write_tags`).
      #
      # The files go into binaries of `chunk` files each, built one at a
      # time. A chunk that does not build is split in two until the file
      # that does not build is alone. Each file then runs in its own
      # process, under ruby and in its binary, `jobs` at once. ruby's
      # results are kept by the file's digest, so ruby runs each file once.
      class Area
        # Where the binaries of a run go: under tmp/, as they are large and a
        # run makes them again.
        attr_reader :work

        def initialize(out:, root:, area:, files:, jobs:, keep:, update:, filtered:)
          @out = out
          @root = root
          @area = area
          @files = files
          @jobs = jobs
          @keep = keep
          @update = update
          @filtered = filtered
          @work = Dev.path(File.join("tmp", File.basename(out), "work", area.tr("/", "-")))
        end

        # The count of examples that ruby passes and zr does not.
        def run
          return 0 if @files.empty?

          FileUtils.rm_rf(@work)
          FileUtils.mkdir_p(@work)
          FileUtils.mkdir_p(File.dirname(issues))
          FileUtils.mkdir_p(File.dirname(tests_log))
          File.write(issues, "")
          @tests = File.open(tests_log, "w")
          @tests.sync = true
          @tests_lock = Mutex.new
          started = now
          results = {}
          chunks.each do |chunk|
            bisect(chunk).each do |files, binary, error|
              unless binary
                files.each { |f| results[rel(f)] = progress(f, started) { { "state" => "build", "error" => error, "examples" => {} } } }
                next
              end

              rows = Dev.parallel_map(files, jobs: @jobs) { |f| [rel(f), progress(f, started) { compare(f, binary) }] }
              rows.each { |r, result| results[r] = result }
              FileUtils.rm_f(binary) unless @keep
            end
          end
          # A run of some files keeps the results of the others, and its
          # results are complete when the earlier ones were.
          earlier = (Suite.results(@out)[@area] if @filtered) || {}
          results = earlier.fetch("files", {}).merge(results).sort.to_h
          Suite.write_results(@out, @area, results, complete: !@filtered || earlier["complete"] == true)
          results.each { |r, result| write_tags(r, result) } if @update
          File.open(issues, "a") { |io| io.puts JSON.generate({ done: true, area: @area, files: results.size }) }
          report(results, now - started)
        ensure
          @tests&.close
          FileUtils.rm_rf(@work) unless @keep
        end

        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # The result of one file, with a line when it ends, so a log shows
        # how far a long run is: the count of files that ended, the file,
        # the examples that ruby and zr pass, and the time.
        def progress(file, started)
          began = now
          result = yield
          @done = (@done || 0) + 1
          examples = result["examples"].values
          ruby = examples.count { |statuses| statuses.first == "pass" }
          zr = examples.count { |rb, z| rb == "pass" && z == "pass" }
          ending = if result["timed_out"] then ", timed out"
                   elsif result["state"] == "ran" then ""
                   else ", #{result["state"]}"
                   end
          $stdout.puts format("[%d/%d] %s: %d/%d pass in zr (%ds%s; %dm in all)", @done, @files.size, rel(file), zr, ruby,
                              now - began, ending, (now - started) / 60)
          $stdout.flush
          log_issues(file, result)
          result
        end

        # The live list of the area's gaps, `<out>/issues/<area>.jsonl`,
        # which another process (an agent that fixes them) may read while
        # the run goes on. Each line is one JSON object: an example that
        # ruby passes and zr does not, with zr's status and message and
        # its tag, if any; or a file that did not build, load or end, with
        # the name "*". The last line of a run that ended is {"done":true}.
        def issues = File.join(@out, "issues", "#{@area.tr("/", "-")}.jsonl")

        # The live log of zr's runs, `<out>/tests/<area>.log`: each line of
        # output as it comes, after the time and the file, so `tail -f`
        # shows each test start and end, and the one that hangs.
        def tests_log = File.join(@out, "tests", "#{@area.tr("/", "-")}.log")

        def tested(file, line)
          @tests_lock.synchronize { @tests.puts("#{Time.now.strftime("%H:%M:%S")} #{rel(file)}: #{line}") }
        end

        def log_issues(file, result)
          r = rel(file)
          tagged = tags(r)
          lines = result["examples"].filter_map do |name, (ruby, zr, message)|
            next unless ruby == "pass" && zr != "pass"
            # A test that hung is listed once, as a hang.
            next if result["hung"]&.include?(name)

            { area: @area, file: r, name: name, zr: zr, message: message, tag: tagged[name] }
          end
          result["hung"]&.each { |name| lines << { area: @area, file: r, name: name, zr: "hang", message: nil, tag: tagged[name] } }
          unless result["state"] == "ran" && !result["timed_out"]
            why = result["timed_out"] ? "timeout" : result["state"]
            lines.unshift({ area: @area, file: r, name: "*", zr: why, message: result["error"], tag: tagged[""] })
          end
          return if lines.empty?

          File.open(issues, "a") { |io| io.write(lines.map { |line| JSON.generate(line) << "\n" }.join) }
        end

        # A file's path below the suite's root, as results and tags name it.
        def rel(file) = file.delete_prefix("#{@root}/")

        # The chunks to build: the files that built last time, `chunk` at a
        # time, then each file that did not, alone.
        def chunks
          broken, fine = @files.partition { |f| tags(rel(f))[""] == "build" }
          fine.each_slice(chunk).to_a + broken.each_slice(1).to_a
        end

        def chunk = 20

        # [[files, binary, error]]: a chunk that builds is one entry; one
        # that does not is split until the file that does not build is alone.
        def bisect(files)
          binary, error = build(files)
          return [[files, binary, error]] if binary || files.size == 1

          half = files.size / 2
          bisect(files.take(half)) + bisect(files.drop(half))
        end

        # Builds the program of `files`. A build that saw a source of zr
        # change (Zr::SourceChanged) runs once more.
        def build(files, again: true)
          name = "chunk-#{Digest::SHA256.hexdigest(files.join("\n"))[0, 12]}"
          source = File.join(@work, "#{name}.rb")
          binary = File.join(@work, name)
          File.write(source, program(files))
          out, status = Open3.capture2e(Suite.zr_env, Dev.ruby, Suite.zr, "build", source, "-o", binary)
          return build(files, again: false) if !status.success? && again && out.include?("changed while this build ran")
          return [binary, nil] if status.success?

          [nil, out.lines.first(20).join]
        end

        # The results of one file: ruby's and the binary's, example by
        # example.
        def compare(file, binary)
          ruby = ruby_run(file)
          zr = resumed(file, binary)
          names = ruby[:examples].keys | zr[:examples].keys
          examples = names.to_h do |n|
            zr_status, message = zr[:examples][n] || ["missing", nil]
            [n, [ruby[:examples].dig(n, 0) || "missing", zr_status, message].compact]
          end
          { "state" => zr[:load] ? "load" : "ran", "ended" => zr[:ended], "timed_out" => zr[:timed_out],
            "error" => zr[:load], "hung" => zr[:hung], "examples" => examples }.compact
        end

        # The most times a run that hung starts again.
        RESUMES = 5

        # zr's run of `file`. When a test hangs and the suite can name it
        # (`read` gives `hung`), the run starts again without it, so the
        # tests after it still run; `hung` lists each one.
        def resumed(file, binary)
          hung = []
          result = nil
          loop do
            run = run_one([binary, *arguments(file, zr: true, skip: hung)], zr: true, file: file)
            result = result ? result.merge(run, examples: result[:examples].merge(run[:examples])) : run
            break hung << run[:hung] if run[:timed_out] && run[:hung] && hung.size >= RESUMES
            break if !run[:timed_out] || run[:hung].nil? || hung.include?(run[:hung])

            hung << run[:hung]
          end
          result.merge(hung: hung.empty? ? nil : hung)
        end

        # ruby's run of `file`, from the cache when this file at this
        # revision ran before.
        def ruby_run(file)
          key = Digest::SHA256.hexdigest([self.class.name, version, RUBY_REVISION, rel(file), File.binread(file)].join("\0"))
          path = File.join(@out, "ruby", "#{key}.json")
          return JSON.parse(File.read(path), symbolize_names: true).tap { |r| r[:examples].transform_keys!(&:to_s) } if File.file?(path)

          source = File.join(@work, "ruby-#{key[0, 12]}.rb")
          File.write(source, program([file]))
          result = run_one([Dev.ruby, source, *arguments(file, zr: false)], zr: false)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.generate(result))
          result
        end

        # Runs one file with the time limit, in a directory of its own, and
        # reads its output: { examples: { name => [status, message] },
        # load:, ended:, timed_out: }.
        def run_one(argv, zr:, file: nil)
          Dir.mktmpdir("zr-suite-") do |dir|
            live = (->(line) { tested(file, line) } if file)
            out, timed_out = Suite.capture(env(dir, zr: zr), argv, dir, limit, idle: idle, live: live)
            read(out).merge(timed_out: timed_out)
          end
        end

        # Seconds with no output that end a run as hung; nil: only `limit`.
        def idle = nil

        # The environment of a run: no bundler of the tools' own.
        # zr's run gets the environment of the pinned copy, for the zr that
        # its tests start, and the copy's home, as a program that zr runs.
        def env(_dir, zr:)
          base = { "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLER_SETUP" => nil }
          zr ? base.merge(Suite.zr_env, "ZR_HOME" => Suite.zr_home) : base
        end

        # The tags of one file from its results: each example that ruby
        # passes and zr does not. When zr's run stopped early, the first
        # example that it did not reach is the one that stopped it: it
        # `hangs`, so the next run skips it and gets further. A hang that
        # the run skipped stays. An example missing from a run that ended
        # is one that a guard left out in zr: it `fails`.
        def tags_from(result, old)
          return { "" => result["state"] } if %w[build load].include?(result["state"])

          # The tests that the run saw hang, or else the first that it did
          # not reach.
          hung = result["hung"]
          first = hung.nil? && !result["ended"]
          result["examples"].each_with_object({}) do |(name, (ruby, zr)), tags|
            next tags[name] = "hangs" if old[name] == "hangs" || hung&.include?(name)
            next unless ruby == "pass" && zr != "pass"

            tags[name] = zr == "missing" && first ? "hangs" : "fails"
            first = false if zr == "missing"
          end
        end

        # The report of the area, `<out>/<area>.txt`: each example that
        # ruby passes and zr does not, with zr's message.
        def report(results, seconds)
          path = File.join(@out, "#{@area.tr("/", "-")}.txt")
          gaps = 0
          File.open(path, "w") do |f|
            f.puts "# #{@area}: #{results.size} file(s) at ruby #{RUBY}, #{seconds.round}s"
            results.each do |r, result|
              lost = result["examples"].select { |_, (ruby, zr)| ruby == "pass" && zr != "pass" }
              next if lost.empty? && result["state"] == "ran" && !result["timed_out"]

              gaps += [lost.size, 1].max
              f.puts "", "## #{r} (#{result["state"]}#{", timed out" if result["timed_out"]})"
              f.puts result["error"].to_s.gsub(/^/, "    ") if result["error"]
              lost.each { |name, (_, zr, message)| f.puts "- #{name} [#{zr}]", ("    #{message}" if message) }
            end
          end
          files, passes, zr_passes, no_build, no_load = Suite.counts({ "files" => results })
          puts format("%-28s %4d files %6d examples %6d pass in zr %3d no build %3d no load", @area, files, passes, zr_passes, no_build, no_load)
          gaps
        end
      end
    end
  end
end
