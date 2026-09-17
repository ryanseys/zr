# frozen_string_literal: true

require "etc"
require "rbconfig"

module Ze0
  module Test
    # Runs test files, a process a file, several at a time, and a file
    # that says `# shards: N` in N of them.
    #
    # One ruby loading them all holds every program a file compiles in a
    # single heap, and ruby does not give heap pages back: over eight
    # programs the live slots barely move while the allocated heap pages
    # go from 881 to 8,938, and `GC.compact` returns none of it.
    # Separate processes bound that, say which file failed rather than
    # which assertion, and let the machine run several at once. Each runs
    # under YJIT, as the CLI runs the compiler: most of a test file is
    # the compiler's own Ruby.
    class Supervisor
      # Memory is what bounds this, not cores: a process compiling
      # programs wants a gigabyte or more, and a machine short of it
      # stops the run rather than swapping. `ZE0_JOBS` says otherwise.
      def self.jobs = Integer(ENV.fetch("ZE0_JOBS") { [Etc.nprocessors, 4].min })

      # A file names its own shard count in its first lines, where a
      # reader meets it before the code.
      HEAD = 40
      SHARDS = /^# shards: (\d+)$/

      Row = Struct.new(:file, :shard, :ok, :out, :seconds) do
        # `core/string/frozen`, not `frozen`: a subject name repeats
        # across areas, and the area is what tells two of them apart.
        def name
          parts = file.delete_suffix("_test.rb").split("/")
          parts.last(3).join("/").delete_prefix("spec/") + (shard ? " #{shard}" : "")
        end

        def tally = out[/^\d+ runs.*$/]
      end

      # `root`: the checkout. `env`: what every process is started with.
      def initialize(root, jobs: Supervisor.jobs, env: {}, io: $stdout)
        @root = root
        @jobs = jobs
        @env = env
        @io = io
      end

      # Run `files`, and answer whether every one of them passed.
      def run(files)
        queue = fill(files)
        total = queue.size
        jobs = [@jobs, total].min
        rows = []
        # A file can run for a minute, and a whole run for several. Each
        # one says how it went as it finishes, rather than the run
        # holding every answer until the last of them is in.
        @io.sync = true
        say = Mutex.new
        began = now
        @io.puts format("%d file(s), %d process(es), %d at a time", files.size, total, jobs)
        Array.new(jobs) do
          Thread.new do
            until queue.empty?
              file, shard = (queue.pop(true) rescue break)
              row = one(file, shard)
              say.synchronize { rows << row; report(row, rows.size, total) }
            end
          end
        end.each(&:join)
        finish(rows, files.size, jobs, now - began)
      end

      # Every file, and a file that asks for shards once per shard.
      def fill(files)
        queue = Queue.new
        files.each do |file|
          n = File.foreach(file).first(HEAD).join[SHARDS, 1].to_i
          n < 2 ? queue << [file, nil] : n.times { |i| queue << [file, "#{i + 1}/#{n}"] }
        end
        queue
      end

      # One file, in a process of its own.
      def one(file, shard)
        began = now
        env = @env.merge(shard ? { "ZE0_SHARD" => shard } : {})
        out = IO.popen(env, [RbConfig.ruby, "--yjit", *load_path, file], err: %i[child out], &:read)
        Row.new(file, shard, $?.success?, out, now - began)
      end

      def load_path = ["-I#{File.join(@root, "lib")}", "-I#{File.join(@root, "test")}"]

      def report(row, at, total)
        @io.puts format("[%*d/%d] %-34s %6.1fs  %s%s", total.to_s.size, at, total, row.name, row.seconds,
                        row.tally || "did not report a tally", row.ok ? "" : "  <-")
      end

      # The failures in full, then the run's own line.
      def finish(rows, files, jobs, seconds)
        failed = rows.reject(&:ok)
        failed.each { |row| warn("\n--- #{File.basename(row.file)}\n#{row.out}") }
        @io.puts format("%d file(s), %d process(es), %.1f s, %d at a time, %d failed",
                        files, rows.size, seconds, jobs, failed.size)
        failed.empty?
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
