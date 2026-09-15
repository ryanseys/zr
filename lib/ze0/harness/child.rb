# frozen_string_literal: true

require_relative "case"

module Ze0
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
      BUILD_MB = Integer(ENV.fetch("ZE0_BUILD_MB", "2048"))
      RUN_MB = Integer(ENV.fetch("ZE0_RUN_MB", "1024"))

      # How often the group's memory is read, in seconds.
      EVERY = 0.2

      module_function

      # The answer and the seconds it took. The answer's code is :timeout
      # past `seconds` and :memory past `megabytes`.
      def run(argv, cwd:, seconds:, megabytes:, stdin: nil, env: {})
        env = { "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(env)
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        in_r, in_w = IO.pipe
        started = now
        pid = Process.spawn(env, *argv, chdir: cwd, in: in_r, out: out_w, err: err_w, pgroup: true)
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

      # Waits for `pid`: its status, or nil and the bound it went past.
      def watch(pid, deadline, megabytes)
        measured = now
        pause = 0.001
        loop do
          _, status = Process.wait2(pid, Process::WNOHANG)
          return [status, nil] if status

          at = now
          over = if at >= deadline then :timeout
                 elsif at - measured >= EVERY
                   measured = at
                   :memory if resident_kb(pid) > megabytes * 1024
                 end
          if over
            Process.kill("KILL", -pid) rescue nil
            Process.wait(pid) rescue nil
            return [nil, over]
          end
          sleep pause
          pause = [pause * 2, 0.02].min
        end
      end

      # The resident kilobytes of every process in `group`, or 0 where ps
      # cannot say (busybox's ps has no -o pgid).
      def resident_kb(group)
        out = IO.popen(["ps", "-A", "-o", "pgid=,rss="], err: File::NULL, &:read)
        out.each_line.sum do |line|
          pgid, kb = line.split
          pgid.to_i == group ? kb.to_i : 0
        end
      rescue SystemCallError
        0
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
