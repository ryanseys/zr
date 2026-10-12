# frozen_string_literal: true

require "json"
require "open3"

module Zr
  module Dev
    module Fuzz
      # The fuzzer's side of the warm builder (builder.rb): it starts the
      # builder on the copy of zr at `pin`, sends it build requests, and
      # gives each answer to the thread that waits for it. Many threads
      # can call `build` at once; the builder forks at most `jobs` builds.
      class BuilderClient
        # One build: its status, the signal that stopped it, whether it
        # took longer than its limit, the stderr of the build, its seconds,
        # and the compiler lines that it ran ("file:line").
        Build = Struct.new(:status, :signal, :timeout, :stderr, :seconds, :lines, keyword_init: true) do
          def ok? = status&.zero? && !signal && !timeout
        end

        SCRIPT = File.expand_path("builder.rb", __dir__)

        # The environment that a binary of the builder runs with.
        attr_reader :env

        def initialize(pin:, jobs:, coverage: false, limit: 180, log: nil)
          argv = [Dev.ruby, SCRIPT, pin, "--jobs=#{jobs}", "--limit=#{limit}"]
          argv << "--coverage" if coverage
          @in, @out, @waiter = spawn(argv, log)
          @lock = Mutex.new
          @waiting = {}
          @next = 0
          ready = @out.gets or raise "zr-dev fuzz: the builder stopped before it was ready (see #{log || "its stderr"})"
          @env = JSON.parse(ready).fetch("env")
          @reader = Thread.new { read_answers }
        end

        # Builds `file` in `dir` to the binary `out`. Blocks until the
        # builder answers.
        def build(dir:, file:, out:)
          queue = Queue.new
          id = @lock.synchronize do
            @next += 1
            @waiting[@next] = queue
            @in.puts(JSON.generate({ id: @next, dir: dir, file: file, out: out }))
            @next
          end
          got = queue.pop
          raise got if got.is_a?(Exception)

          Build.new(status: got["status"], signal: got["signal"], timeout: got["timeout"], stderr: got["stderr"].b,
                    seconds: got["seconds"], lines: got["lines"])
        ensure
          @lock.synchronize { @waiting.delete(id) } if id
        end

        # Stops the builder: no more requests, and it ends when its last
        # build ends.
        def close
          @in.close unless @in.closed?
          @reader&.join(5)
          @waiter.join(30) || Process.kill("KILL", @waiter.pid)
        rescue Errno::ESRCH
          nil
        end

        private

        # The builder's stderr goes to `log` (a warning of the compiler, or
        # why the builder stopped), else to this process's stderr.
        def spawn(argv, log)
          err = log ? File.open(log, "a") : $stderr
          stdin, stdout, waiter = Open3.popen2(Harness::CleanEnv.env(Suite.zr_env), *argv, err: err)
          stdin.sync = true
          [stdin, stdout, waiter]
        end

        def read_answers
          while (line = @out.gets)
            got = JSON.parse(line)
            queue = @lock.synchronize { @waiting[got["id"]] }
            queue&.push(got)
          end
        ensure
          stopped = RuntimeError.new("zr-dev fuzz: the builder stopped")
          @lock.synchronize { @waiting.each_value { |queue| queue.push(stopped) } }
        end
      end
    end
  end
end
