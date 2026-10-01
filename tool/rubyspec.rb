# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Runs ruby/spec, the specs of ruby 4.0.7's own checkout, under ruby
    # and in a zr binary, and lists each example that passes in ruby and
    # fails in the binary.
    #
    #   zr-dev rubyspec language                    one area
    #   zr-dev rubyspec core                        each directory of core/
    #   zr-dev rubyspec core/array library/json     some areas
    #   zr-dev rubyspec core/array -f pop_spec.rb   the files that match
    #
    # zr's own specs test what zr's authors thought of. ruby/spec tests
    # what ruby's authors thought of, so it finds the other gaps.
    #
    # For each area, the tool writes one program that runs the area's
    # spec files through mspec, and builds it once. Each require in it is
    # a literal, so zr compiles every spec file into the binary. The
    # program runs only the files that its arguments name, so each file
    # runs in its own process, under ruby and in the binary, with a time
    # limit. An example that ruby fails too is not a gap: some specs need
    # a build of ruby that the host does not have.
    #
    # The report of an area goes to `tmp/rubyspec/<area>.txt`, and a line
    # for each area to `tmp/rubyspec/summary.tsv`. The binary is deleted
    # after the run.
    class RubySpec < Command
      summary "Run ruby/spec in ruby and in a zr binary, and list the gaps"
      usage "<area>... [-f PATTERN] [-j JOBS] [--keep]"
      host_ruby!

      # Seconds for one spec file. A file that does not end in this time
      # is a gap: zr loops where ruby raises, or is much slower.
      LIMIT = 60

      # The areas that need a feature a compiled program has on purpose
      # in another form (the command line, the C API), or that start ruby.
      SKIPPED = %w[command_line optional security].freeze

      OUT = Dev.path("tmp/rubyspec")

      def defaults
        @filter = nil
        @jobs = nil
        @keep = false
      end

      def options(o)
        o.on("-f PATTERN", "only the spec files whose path matches") { |v| @filter = Regexp.new(v) }
        o.on("-j JOBS", Integer, "files to run at once (default 4)") { |v| @jobs = v }
        o.on("--keep", "keep the binaries") { @keep = true }
      end

      def run(argv)
        Dev.pinned!(name)
        fail!("give an area, such as language, core or core/array") if argv.empty?
        root = checkout!
        areas = argv.flat_map { |a| areas_of(root, a) }
        FileUtils.mkdir_p(OUT)
        gaps = areas.sum do |area|
          RubySpec::Area.new(root, area, filter: @filter, jobs: @jobs || 4, keep: @keep).run
        rescue StandardError => e
          warn "#{area}: #{e.class}: #{e.message}"
          0
        end
        puts "#{gaps} gap(s) in #{areas.size} area(s); see #{Dev.rel(OUT)}"
        true
      end

      # The spec directory of the CRuby checkout at RUBY_REVISION.
      def checkout!
        src = Dev.ruby_src
        head = Dev.git("rev-parse", "HEAD", dir: src, err: $stderr).to_s.strip
        fail!("#{src} is at #{head[0, 10]}, not ruby #{RUBY} (#{RUBY_REVISION[0, 10]})") unless head == RUBY_REVISION
        File.join(src, "spec")
      end

      # `core` is each of its directories; any other word is one area.
      def areas_of(root, word)
        word = word.delete_suffix("/")
        dir = File.join(root, "ruby", word)
        fail!("no area #{word} in #{root}/ruby") unless File.directory?(dir)
        return [word] if Dir.glob("#{dir}/*_spec.rb").any? || !%w[core library].include?(word)

        Dir.children(dir).sort.filter_map do |d|
          area = "#{word}/#{d}"
          area if File.directory?(File.join(dir, d)) && !SKIPPED.include?(d)
        end
      end

      # One area: its program, its binary and its report.
      class Area
        Result = Struct.new(:failed, :examples, :status, :timed_out, :tail, :messages)

        def initialize(root, area, filter:, jobs:, keep:)
          @root = root
          @area = area
          @jobs = jobs
          @keep = keep
          @files = Dir.glob(File.join(root, "ruby", area, "**", "*_spec.rb")).sort
          @files.select! { |f| f.match?(filter) } if filter
          @work = File.join(OUT, "work", area.tr("/", "-"))
        end

        # The count of gaps.
        def run
          return 0 if @files.empty?

          FileUtils.rm_rf(@work)
          FileUtils.mkdir_p(@work)
          program = File.join(@work, "main.rb")
          File.write(program, source)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          binary = build(program)
          seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          report = binary ? compare(program, binary) : { refused: File.read("#{program}.build") }
          write(report, seconds)
        ensure
          FileUtils.rm_rf(@work) unless @keep
        end

        # The program: mspec, the spec helper, then each file behind a
        # test of the arguments. A file that raises as it loads is
        # reported, and the next one runs.
        def source
          mspec = File.join(@root, "mspec/lib")
          lines = [
            "# frozen_string_literal: false",
            'ENV["MSPEC_RUNNER"] = "1"',
            "$LOAD_PATH.unshift(#{mspec.inspect})",
            'require "mspec"',
            'require "mspec/utils/script"',
            'require "mspec/runner/formatters/specdoc"',
            "require #{File.join(@root, "ruby/spec_helper.rb").inspect}",
            "SpecdocFormatter.new.register",
            "MSpec.register_files ARGV",
            "MSpec.actions :start",
            "MSpec.setup_env"
          ]
          @files.each do |f|
            lines << "if ARGV.include?(#{f.inspect})"
            lines << "  MSpec.store :file, #{f.inspect}"
            lines << "  MSpec.actions :load"
            lines << "  begin"
            lines << "    require #{f.inspect}"
            lines << "  rescue Exception => e"
            lines << "    puts \"LOADFAIL \#{e.class}: \#{e.message.lines.first}\""
            lines << "  end"
            lines << "  MSpec.actions :unload"
            lines << "end"
          end
          lines << "MSpec.actions :finish"
          lines << "exit MSpec.exit_code"
          lines.join("\n") << "\n"
        end

        # A build that saw a source of zr change (Zr::SourceChanged) runs
        # once more.
        def build(program, again: true)
          binary = File.join(@work, "main")
          out, status = Open3.capture2e(Dev.ruby, Dev.path("exe/zr"), "build", program, "-o", binary)
          return build(program, again: false) if !status.success? && again && out.include?("changed while this build ran")

          File.write("#{program}.build", out)
          status.success? ? binary : nil
        end

        # Runs each file under ruby and in the binary, `@jobs` at once.
        def compare(program, binary)
          pairs = Dev.parallel_map(@files, jobs: @jobs) { |file| [run_one([Dev.ruby, program, file]), run_one([binary, file])] }
          @files.zip(pairs).to_h
        end

        # Runs one spec file in a temporary directory, and reads the
        # examples that failed.
        def run_one(argv)
          Dir.mktmpdir("rubyspec") do |dir|
            env = { "RUBY_EXE" => RbConfig.ruby, "RUBYOPT" => nil, "SPEC_TEMP_DIR" => File.join(dir, "tmp") }
            out, timed_out, status = capture(env, argv, dir)
            failed, examples = parse(out)
            Result.new(failed, examples, status, timed_out, out.lines.last(12).join, messages(out))
          end
        end

        def capture(env, argv, dir)
          reader, writer = IO.pipe
          pid = Process.spawn(env, *argv, chdir: dir, in: File::NULL, out: writer, err: writer, pgroup: true)
          writer.close
          out = +""
          collector = Thread.new { out << reader.read }
          timed_out = collector.join(LIMIT).nil?
          if timed_out
            kill(pid)
            collector.join(5)
          end
          _, status = Process.wait2(pid)
          [out.force_encoding(Encoding::BINARY), timed_out, status]
        ensure
          reader&.close
        end

        # The spec's process group, or the spec alone when the group is
        # gone: a spec can start its own session (`Process.setsid`).
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

        # Each example that failed, as its describe and its sentence, and
        # the count of examples the run finished. SpecdocFormatter prints
        # a describe line, then each example as `- sentence`, marked
        # `(FAILED - n)` or `(ERROR - n)` when it failed.
        def parse(out)
          failed = []
          examples = 0
          header = nil
          out.each_line do |line|
            line = line.chomp.scrub
            if line.start_with?("- ")
              examples += 1
              failed << "#{header} #{::Regexp.last_match(1)}" if line =~ /\A- (.*) \((?:FAILED|ERROR) - \d+\)\z/
            elsif line.start_with?("LOADFAIL ")
              failed << line
            elsif !line.empty?
              header = line
            end
          end
          [failed, examples]
        end

        # The first line of each failure's message, by the example's full
        # sentence. After the examples, mspec prints `n)`, then the sentence
        # with FAILED or ERROR, then the message.
        def messages(out)
          lines = out.lines.map { |l| l.chomp.scrub }
          found = {}
          lines.each_with_index do |line, i|
            next unless line.match?(/\A\d+\)\z/) && (head = lines[i + 1])

            found[head.sub(/ (?:FAILED|ERROR)\z/, "")] = lines[i + 2].to_s[0, 160]
          end
          found
        end

        def write(report, seconds)
          path = File.join(OUT, "#{@area.tr("/", "-")}.txt")
          gaps = 0
          timeouts = 0
          examples = 0
          File.open(path, "w") do |f|
            f.puts "# #{@area}: ruby/spec at ruby #{RUBY}, #{@files.size} file(s), built in #{seconds.round}s"
            if report[:refused]
              f.puts "", "BUILD FAILED", report[:refused].lines.first(30).join
              gaps = 1
            else
              report.sort.each do |file, (ruby, zr)|
                examples += ruby.examples
                rel = file.delete_prefix("#{@root}/ruby/")
                lost = zr.failed - ruby.failed
                short = zr.examples < ruby.examples
                next if lost.empty? && !short && !zr.timed_out

                timeouts += 1 if zr.timed_out
                gaps += lost.size + (short && lost.empty? ? 1 : 0)
                f.puts "", "## #{rel}#{" (TIMEOUT)" if zr.timed_out}"
                f.puts "ran #{zr.examples} of #{ruby.examples} examples, #{zr.status}" if short || zr.timed_out
                lost.each do |ex|
                  f.puts "- #{ex}"
                  f.puts "    #{zr.messages[ex]}" if zr.messages[ex]
                end
                f.puts zr.tail.gsub(/^/, "    ") if short || zr.timed_out
              end
            end
          end
          line = [@area, @files.size, examples, gaps, timeouts, seconds.round].join("\t")
          File.open(File.join(OUT, "summary.tsv"), "a") { |f| f.puts line }
          puts format("%-28s %4d files %6d examples %4d gaps %3d timeouts", @area, @files.size, examples, gaps, timeouts)
          gaps
        end
      end
    end
  end
end
