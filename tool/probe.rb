# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "lib/zr/dev"
require_relative "../test/support/harness/reference"

module Zr
  module Dev
    # Runs Ruby files under ruby 4.0.7 and as zr binaries, and shows where
    # the two differ.
    #
    #   zr-dev probe probes/                 every .rb file in a directory
    #   zr-dev probe a.rb b.rb -j 6          six at a time
    #
    # A probe is a small program that prints many results, to find a
    # divergence from ruby. The tool compiles each probe in a fork of one
    # process that has the compiler and the runtime loaded, so a probe
    # costs its own compile and link, not a start of zr. It compares
    # stdout, stderr, the exit status and the signal, and prints a unified
    # diff of each part that differs. Each program runs in its own
    # directory with its own relative path, so the two backtraces agree.
    # An object address (`0x` and 16 hex digits) is never the same in two
    # processes, so the tool writes each one as `0x...` in both outputs.
    #
    # Exit status: 0 when every probe gives ruby's output, else 1.
    class Probe < Command
      summary "Run Ruby files under ruby and as zr binaries, and show the differences"
      usage "[-j JOBS] <file.rb|dir>..."
      host_ruby!

      JOBS = 4
      # Seconds for one program. A probe that loops forever does not stop
      # the run.
      LIMIT = 60

      Answer = Struct.new(:stdout, :stderr, :status, :signal)

      def options(o) = o.on("-j JOBS", Integer, "probes at a time (default #{JOBS})") { |v| @jobs = v }

      def run(argv)
        fail!("give probe files or directories") if argv.empty?
        files = argv.flat_map { |a| File.directory?(a) ? Dir[File.join(a, "*.rb")].sort : [a] }.map { |f| File.expand_path(f) }
        missing = files.reject { |f| File.file?(f) }
        fail!("no such file: #{missing.join(", ")}") unless missing.empty?
        warm!(files)

        differ = 0
        results = in_parallel(files, @jobs || JOBS) { |file| [file, ruby(file), zr(file)] }
        results.each do |file, want, got|
          name = Dev.rel(file)
          if want == got
            puts "SAME #{name}"
            next
          end
          differ += 1
          puts "DIFF #{name}"
          want.each_pair do |part, value|
            next if value == got[part]

            puts "--- #{part} (ruby, then zr)"
            puts diff(value.to_s, got[part].to_s)
          end
        end
        puts "#{files.size - differ} of #{files.size} probe(s) give ruby's output"
        differ.zero?
      end

      # Loads the compiler and the runtime, builds the runtime object if
      # it is missing, and loads its prelinked image, so that every fork
      # shares them. When a probe evals, it also builds eval support here,
      # once: a fork that found it missing would build it itself, and
      # several such builds at once take all the memory.
      def warm!(files)
        require_relative "../lib/zr/cli"
        require_relative "../lib/zr/runtime"
        require_relative "../lib/zr/native/build"
        runtime = Zr.runtime
        runtime.description
        objects = [Native::Build.runtime_object(runtime)]
        objects << Native::Build.eval_support_object(Zr.eval_support) if files.any? { |file| evals?(file) }
        Native::Build.prelink([objects.first])
        Native::Build.prelink(objects)
      end

      # Whether the program of `file` links eval support. A file that does
      # not build counts as no: its fork reports why.
      def evals?(file)
        Dir.chdir(File.dirname(file)) { Hir.build(File.read(file), File.basename(file)).evals }
      rescue StandardError, ScriptError
        false
      end

      def ruby(file)
        work = Dir.mktmpdir("zr-probe-ruby-")
        answer([Dev.ruby, File.basename(file)], stage(file, work), Harness::Reference.env)
      ensure
        FileUtils.rm_rf(work) if work
      end

      # Compiles `file` in a fork and runs the binary. The fork compiles as
      # `zr run` does (`CLI.lower`), so a refusal or a syntax error gives
      # the report and the status that `zr run` gives.
      def zr(file)
        work = Dir.mktmpdir("zr-probe-zr-")
        dir = stage(file, work)
        bin = File.join(work, "program")
        err = File.join(work, "compile.err")
        pid = fork do
          $stderr.reopen(err, "w")
          Dir.chdir(dir)
          program = CLI.lower(File.basename(file), "run", Target.default, assemble: true)
          why = Native::Build.program(program, bin, work: work)
          abort "zr: #{why}" if why
          exit!(0)
        end
        _, status = Process.wait2(pid)
        return Answer.new("".b, unaddressed(File.binread(err)), status.exitstatus, status.termsig) unless status.success?

        answer([bin], dir)
      ensure
        FileUtils.rm_rf(work) if work
      end

      # Copies the probe into its own directory, and returns the directory.
      def stage(file, work)
        dir = File.join(File.realpath(work), "run")
        FileUtils.mkdir_p(dir)
        FileUtils.cp(file, dir)
        dir
      end

      # Runs `command` in `dir` with an empty stdin. A program that runs
      # longer than LIMIT is killed, and its signal is the answer's.
      def answer(command, dir, env = {})
        Open3.popen3(env, *command, chdir: dir) do |stdin, stdout, stderr, waiter|
          stdin.close
          out = Thread.new { stdout.read }
          err = Thread.new { stderr.read }
          Process.kill("KILL", waiter.pid) unless waiter.join(LIMIT)
          status = waiter.value
          Answer.new(unaddressed(out.value), unaddressed(err.value), status.exitstatus, status.termsig)
        end
      end

      ADDRESS = /0x\h{16}/n

      def unaddressed(text) = text.b.gsub(ADDRESS, "0x...")

      # Maps `items` with `jobs` threads. Each item runs its own processes,
      # so threads are enough.
      def in_parallel(items, jobs)
        queue = Queue.new
        items.each_with_index { |item, i| queue << [item, i] }
        out = Array.new(items.size)
        Array.new([jobs, items.size].min) do
          Thread.new do
            while (job = (queue.pop(true) rescue nil))
              item, i = job
              out[i] = yield(item)
            end
          end
        end.each(&:join)
        out
      end

      def diff(a, b)
        Dir.mktmpdir("zr-probe-diff-") do |dir|
          File.binwrite(File.join(dir, "ruby"), a)
          File.binwrite(File.join(dir, "zr"), b)
          text, = Open3.capture2("diff", "-u", "ruby", "zr", chdir: dir)
          text.lines.drop(2).join
        end
      end
    end
  end
end
