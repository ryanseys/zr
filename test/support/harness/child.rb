# frozen_string_literal: true

require_relative "answer"
require_relative "unbundled"

module Zr
  module Harness
    # A child with both streams captured, bounded in wall-clock time and in
    # memory. The bound on memory is what keeps a runaway build or binary
    # from taking the whole machine down with it: macOS does not enforce
    # RLIMIT_AS, so the group's resident size is read while it runs, and
    # the group is killed once it holds more than the limit.
    #
    # The whole process group goes when either bound is hit, so a child of
    # the program cannot hold the pipes open.
    module Child
      # The most a build and a run may hold, in megabytes, summed over the
      # process group.
      BUILD_MB = Integer(ENV.fetch("ZR_BUILD_MB", "2048"))
      RUN_MB = Integer(ENV.fetch("ZR_RUN_MB", "1024"))

      # The environment a program gets when the question is "what does
      # ruby say", which is not the environment `bundle exec rake` runs
      # in: bundler puts its own `GEM_HOME` and `BUNDLE_GEMFILE` there,
      # the child's `require` then finds bundler's gems rather than the
      # ones ruby ships, and `Kernel#require` is not even the same
      # method -- `[[:req, :name]]` under bundler where a bare ruby has
      # rubygems' `[[:req, :path]]`.
      #
      # The recordings were made by a bare ruby, so a road that asks
      # ruby for an answer merges this. A road that builds with zr does
      # not: the compiler needs the gems bundler set up.
      BARE_RUBY = { "GEM_HOME" => nil, "GEM_PATH" => nil, "BUNDLE_GEMFILE" => nil,
                    "BUNDLE_BIN_PATH" => nil, "BUNDLE_LOCKFILE" => nil,
                    "BUNDLER_SETUP" => nil, "BUNDLER_VERSION" => nil }.freeze

      # How often the group's memory is read, in seconds.
      EVERY = 0.2

      module_function

      # The answer and the seconds it took. The answer's code is :timeout
      # past `seconds` and :memory past `megabytes`. With `megabytes` nil
      # nothing samples the group's memory, and nothing forks beside
      # the child: what a benchmark asks, since its CPU time is read
      # from the process's children as a whole.
      def run(argv, cwd:, seconds:, megabytes:, stdin: nil, env: {})
        env = Unbundled.env(env)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_r, in_w = IO.pipe
        started = now
        pid = Process.spawn(env, *argv, chdir: cwd, in: in_r, out: out_w, err: err_w, pgroup: true,
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
        reader = [out_r, err_r].map { |io| Thread.new { io.binmode; io.read } }
        status, over = watch(pid, started + seconds, megabytes)
        writer.join
        stdout, stderr = reader.map(&:value)
        seconds = now - started
        return [Answer.new(stdout, stderr, over, nil), seconds] if over

        [Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig), seconds]
      end

      # How often the bounds are looked at while the child runs.
      LOOK = 0.05

      # Waits for `pid`: its status, or nil and the bound it went past.
      # A thread blocks in `wait2`, so the answer comes the moment the
      # child ends; polling it on a grid of up to 20 ms added that much
      # to every one of a tier's runs. This thread looks at the bounds
      # between joins.
      def watch(pid, deadline, megabytes)
        Watch.add(pid) if megabytes
        waiter = Thread.new { Process.wait2(pid).last }
        loop do
          return [waiter.value, nil] if waiter.join(LOOK)

          over = if now >= deadline then :timeout
                 elsif megabytes && Watch.resident_kb(pid) > megabytes * 1024 then :memory
                 end
          next unless over

          Process.kill("KILL", -pid) rescue nil
          waiter.join
          return [nil, over]
        end
      ensure
        Watch.drop(pid) if megabytes
      end

      # One reader of every group's memory: a thread that runs `ps` once
      # every EVERY seconds while any child is watched, and stops when
      # none is. Twelve children each running their own `ps` five times
      # a second was a load of its own.
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

        # The resident kilobytes of the group `pid` leads at the last
        # sample, or 0 before the first one or where ps cannot say
        # (busybox's ps has no -o pgid).
        def resident_kb(pid)
          @lock.synchronize { @sample.fetch(pid, 0) }
        end

        # The thread ends under the lock, so an `add` sees either a live
        # thread or none and never a dying one; a thread that dies of an
        # error lets go the same way, so the next `add` starts another.
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
