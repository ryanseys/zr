# frozen_string_literal: true

require_relative "answer"
require_relative "clean_env"

module Zr
  module Harness
    # Runs a child process, captures stdout and stderr, and limits its
    # wall-clock time and memory. The memory limit stops a runaway build
    # or binary from using all of the machine. macOS does not enforce
    # RLIMIT_AS, so this reads the group's resident size while it runs,
    # and kills the group when it uses more than the limit.
    #
    # At either limit, all of the process group is killed, so a child of
    # the program cannot keep the pipes open.
    module Child
      # The memory limit of a build and of a run, in megabytes, summed
      # over the process group.
      BUILD_MB = Integer(ENV.fetch("ZR_TEST_BUILD_MB", "2048"))
      RUN_MB = Integer(ENV.fetch("ZR_TEST_RUN_MB", "1024"))

      # How often the group's memory is read, in seconds.
      EVERY = 0.2

      # The process group of each child that runs now. Each child has its
      # own group, so a kill of the caller's group does not stop it.
      @live = {}

      module_function

      # Returns the output and the seconds it took. The output's code is
      # :timeout after `seconds`, and :memory above `megabytes`. When
      # `megabytes` is nil, nothing samples the group's memory and no
      # other process starts next to the child. A benchmark needs this,
      # because it reads its CPU time from all children of this process.
      # With `merge`, stderr goes into stdout, in the order that the child
      # writes them.
      def run(argv, cwd:, seconds:, megabytes:, stdin: nil, env: {}, merge: false)
        env = CleanEnv.env(env)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_r, in_w = IO.pipe
        started = now
        pid = Process.spawn(env, *argv, chdir: cwd, in: in_r, out: out_w, err: merge ? out_w : err_w, pgroup: true,
                            unsetenv_others: true)
        [out_w, err_w, in_r].each(&:close)
        writer = Thread.new do
          in_w.binmode
          in_w.write(stdin) if stdin
        rescue Errno::EPIPE
          nil
        ensure
          in_w.close
        end
        reader = [out_r, err_r].map { |io| Thread.new { io.binmode.read } }
        status, over = watch(pid, started + seconds, megabytes)
        writer.join
        stdout, stderr = reader.map(&:value)
        seconds = now - started
        return [Answer.new(stdout, stderr, over, nil), seconds] if over

        [Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig), seconds]
      end

      # Kills every child that runs now, with its process group. A test
      # worker calls this before it stops, so that no build continues
      # after the worker.
      def stop_all
        @live.each_key { |pid| kill_group(pid) }
      end

      # Kills the process group of `pid`, if it still runs.
      def kill_group(pid)
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      # How often the limits are checked while the child runs, in seconds.
      LOOK = 0.05

      # Waits for `pid`. Returns its status, or nil and the limit that it
      # went above. A thread blocks in `wait2`, so the result comes as
      # soon as the child ends. Polling would add up to one poll interval
      # to each run of a tier. This thread checks the limits between joins.
      def watch(pid, deadline, megabytes)
        @live[pid] = true
        Watch.add(pid) if megabytes
        waiter = Thread.new { Process.wait2(pid).last }
        loop do
          return [waiter.value, nil] if waiter.join(LOOK)

          over = if now >= deadline then :timeout
                 elsif megabytes && Watch.resident_kb(pid) > megabytes * 1024 then :memory
                 end
          next unless over

          kill_group(pid)
          waiter.join
          return [nil, over]
        end
      ensure
        @live.delete(pid)
        Watch.drop(pid) if megabytes
      end

      # One thread reads the memory of all watched groups. It runs `ps`
      # once every EVERY seconds while a child is watched, and stops when
      # none is. One `ps` for each child five times a second causes too
      # much load when twelve children run.
      module Watch
        @groups = {}
        @sample = {}
        @lock = Mutex.new

        module_function

        def add(pid)
          @lock.synchronize do
            @groups[pid] = true
            @thread ||= Thread.new { sample_until_idle }
          end
        end

        def drop(pid)
          @lock.synchronize { @groups.delete(pid) }
        end

        # The resident kilobytes of the group that `pid` leads, at the last
        # sample. It is 0 before the first sample, or when ps cannot give
        # it (busybox's ps has no -o pgid).
        def resident_kb(pid)
          @lock.synchronize { @sample.fetch(pid, 0) }
        end

        # The thread ends under the lock, so `add` sees a live thread or
        # no thread, never a thread that is ending. A thread that stops on
        # an error also clears `@thread`, so the next `add` starts a new one.
        def sample_until_idle
          loop do
            groups = @lock.synchronize do
              @thread = nil if @groups.empty?
              @groups.dup
            end
            return if groups.empty?

            sample = read(groups)
            @lock.synchronize { @sample = sample }
            sleep EVERY
          end
        ensure
          @lock.synchronize { @thread = nil if @thread == Thread.current }
        end

        def read(groups)
          out = IO.popen(["ps", "-A", "-o", "pgid=,rss="], err: File::NULL, &:read)
          sample = Hash.new(0)
          out.each_line do |line|
            pgid, kb = line.split
            pgid = pgid.to_i
            sample[pgid] += kb.to_i if groups.key?(pgid)
          end
          sample
        rescue SystemCallError
          {}
        end
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
