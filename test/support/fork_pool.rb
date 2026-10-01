# frozen_string_literal: true

require_relative "../../lib/zr/native/resident"
require_relative "workers"
require "etc"
require "io/wait"
require "minitest"

module Zr
  module Test
    # A Minitest parallel executor that forks.
    #
    # Minitest uses `Minitest.parallel_executor` for a suite that calls
    # `parallelize_me!`. It gets `[klass, method, reporter]`, runs the
    # example and gives the result to the reporter. The Minitest executor
    # uses threads. Threads do not help here: a zr compile is Ruby code,
    # and the GVL lets only one thread run it at a time.
    #
    # The parent loads all test files one time (0.4 s and 68 MB for the
    # old spec tier). Each worker is a fork of the parent, so it does not load
    # them again. The unit of work is one example, not one file, so no
    # worker is idle while another worker has many examples left.
    #
    # Forks also limit memory. Ruby does not release heap pages: the tier
    # in one process grew past 4.1 GB. When a worker grows past
    # `RECYCLE_MB`, the pool closes it and forks a new one from the parent.
    # Thus a run stays at about `size * RECYCLE_MB`.
    #
    # Forks also make a miscompile easy to see. When the OS kills a
    # worker, the parent reaps it and reports an error for that example.
    # The run does not stop.
    class ForkPool
      # The maximum time for one example of `klass`. A suite that defines
      # `deadline` sets its own limit, for work that is slow but not stuck
      # (a wasm build spends minutes in the backend). `ZR_TEST_TIMEOUT`
      # overrides all suites, so one run can use one limit for the tier.
      def self.deadline_for(klass)
        return Workers::DEADLINE unless ENV["ZR_TEST_TIMEOUT"].nil? && klass.respond_to?(:deadline)

        klass.deadline
      end

      attr_reader :size

      def initialize(size: Workers.size, recycle_mb: Workers::RECYCLE_MB)
        @size = size
        @recycle_mb = recycle_mb
        @queue = Thread::Queue.new
        @threads = []
        @interrupted = false
      end

      # Starts one thread for each worker. Only that thread writes to the
      # pipe of the worker and reads its result, so the pool never gives
      # a job to a busy worker.
      def start
        unless ENV["MT_CPU"]
          warn "#{@size} test worker(s) on #{Etc.nprocessors} cores and #{Workers.gigabytes} GB (MT_CPU sets the number)"
        end
        # A worker shares stdout with this process. Flush the reporter
        # output before a fork, or the worker writes it again.
        $stdout.sync = true
        # Each worker inherits the memory of this process.
        # `Process.warmup` collects, compacts and promotes the live objects
        # to the old generation. Thus the first major GC of a worker does
        # not mark (and so copy) the whole warmed compiler. Without it, the
        # pages stay shared only until the first GC.
        Process.warmup
        @threads = Array.new(@size) { Thread.new { serve } }
      end

      def <<(job) = @queue << job

      # Minitest calls this after it gives all suites to the pool. The
      # nils go into the queue after the jobs, so each thread finishes its
      # jobs and then stops.
      def shutdown
        @size.times { @queue << nil }
        @threads.each(&:join)
      end

      private

      def serve
        worker = nil
        while (job = @queue.pop)
          break if @interrupted

          klass, name, reporter = job
          worker ||= Worker.open
          reporter.synchronize { reporter.prerecord klass, name }
          result = worker.ask(klass, name)
          if result.nil?
            result = worker.epitaph(klass, name)
            @interrupted ||= worker.interrupted?
            worker = worker.close
          elsif worker.grown > @recycle_mb
            worker = worker.close
          end
          reporter.synchronize { reporter.record result }
        end
      ensure
        worker&.close
      end

      # One forked process and its two pipes.
      class Worker
        attr_reader :resident, :grown

        def self.open
          jobs = IO.pipe
          back = IO.pipe
          $stdout.flush
          pid = Process.fork do
            # Put the worker in its own process group, so that a kill
            # also stops the processes it started. A zr build forks six
            # more processes. An orphan keeps its pipe open and uses about
            # 100 MB after the run stops the example.
            Process.setpgid(0, 0)
            # `stop!` sends SIGTERM first. The children that
            # `Harness::Child` starts have their own process groups, so the
            # worker kills them before it stops.
            Signal.trap("TERM") do
              Zr::Harness::Child.stop_all if defined?(Zr::Harness::Child)
              Signal.trap("TERM", "DEFAULT")
              Process.kill("TERM", Process.pid)
            end
            jobs.last.close
            back.first.close
            serve(jobs.first, back.last)
          end
          # Both processes set the group, because either can run first.
          # The child can already be gone; the system reports that as any
          # of these errors.
          begin
            Process.setpgid(pid, pid)
          rescue Errno::ESRCH, Errno::EACCES, Errno::EPERM
            nil
          end
          jobs.first.close
          back.last.close
          new(pid, jobs.last, back.first)
        end

        # The worker loop: read an example, run it, and send back the
        # result and the resident size. It ends with `exit!`, because
        # the parent writes the report. The Minitest `at_exit` in a worker
        # would write a second report.
        def self.serve(jobs, back)
          Minitest.parallel_executor = nil
          back.sync = true
          @settled = nil
          loop do
            # A suite can be an anonymous class with a custom name
            # ("GC programs"), so no constant finds it. The worker is a fork
            # of the parent and has the same list in the same order, so an
            # index finds it.
            at, name = Marshal.load(jobs)
            @job = [Minitest::Runnable.runnables[at], name]
            @began = Minitest.clock_time
            answer(@job.first.new(name).run, back)
            @job = nil
          end
        rescue IOError # EOFError is an IOError
          nil # the parent has gone
        rescue Exception => e # rubocop:disable Lint/RescueException
          escaped(e, back) if @job
        ensure
          exit!(0)
        end

        # An exception that Minitest does not catch (`exit`, a POSIX
        # signal, NoMemoryError) left the example. The example fails with
        # the exception class. The growth is infinite, so the parent
        # replaces the worker: this process can be in any state.
        def self.escaped(error, back)
          klass, name = @job
          result = Minitest::Result.new(name)
          result.klass = klass.name
          result.source_location = klass.instance_method(name).source_location
          result.assertions = 0
          result.time = Minitest.clock_time - @began
          reason = RuntimeError.new("the example raised #{error.class} past minitest: #{error.message}")
          reason.set_backtrace(error.backtrace || [])
          result.failures << Minitest::UnexpectedError.new(flat(reason))
          Marshal.dump([result, resident, Float::INFINITY], back)
        rescue StandardError
          nil # the parent reports a worker that went quiet
        end

        # Sends the result, the resident size, and the growth since the
        # worker settled. Even after `portable`, a result can contain an
        # object that Marshal cannot dump. Then send a bare result with
        # that error, so the worker does not stop.
        #
        # The worker settles after its first example, not at the fork. A
        # page of the parent is not resident in a worker until the worker
        # touches it. So a new fork starts at a few MB and grows to the
        # size of the parent as it uses the inherited compiler. Measured
        # from the fork, that growth would replace the worker at once
        # (test/unit/fork_pool_test.rb tests this). The size after the
        # first example is the base; only growth past it counts.
        def self.answer(result, back)
          now = resident
          @settled ||= now
          Marshal.dump([portable(result), now, now - @settled], back)
        rescue TypeError => e
          bare = Minitest::Result.new(result.name)
          bare.klass = result.klass
          bare.source_location = result.source_location
          bare.assertions = result.assertions
          bare.time = result.time
          bare.failures << Minitest::UnexpectedError.new(flat(RuntimeError.new("this result does not cross a pipe: #{e.message}")))
          Marshal.dump([bare, now, now - @settled], back)
        end

        # A failure contains an exception, and a compiler exception can
        # contain any object (an IO, a Proc, a whole program) that Marshal
        # cannot send. The parent needs only the message and the
        # backtrace, so send only those. `minitest/server` does the same.
        def self.portable(result)
          result.failures.map! do |failure|
            case failure
            when Minitest::UnexpectedError then Minitest::UnexpectedError.new(flat(failure.error))
            when Minitest::Assertion then flat(failure)
            else failure
            end
          end
          result
        end

        # Removes the frames of this file from the backtrace. The example
        # is called from here, but the error is not here, and the Minitest
        # backtrace filter does not know this file.
        def self.flat(error)
          backtrace = (error.backtrace || []).reject { |at| at.start_with?(__FILE__) }
          error.class.new(error.message).tap { |flat| flat.set_backtrace(backtrace) }
        end

        # The resident size of this process in MB (Native::Resident).
        # When the system call is not available, use `ps`.
        def self.resident = resident_of(Process.pid)

        def self.resident_of(pid)
          ::Zr::Native::Resident.of(pid) || IO.popen(["ps", "-o", "rss=", "-p", pid.to_s], &:read).to_i / 1024
        end

        def initialize(pid, jobs, back)
          @pid = pid
          @jobs = jobs
          @back = back
          @jobs.sync = true
          @resident = 0
          @grown = 0
        end

        # Runs `klass#name` in this worker and returns the result. Returns
        # nil if the worker died, or if it took more time than the suite
        # allows.
        def ask(klass, name)
          Marshal.dump([Minitest::Runnable.runnables.index(klass), name], @jobs)
          return nil unless answered?(ForkPool.deadline_for(klass))

          result, @resident, @grown = Marshal.load(@back)
          result
        rescue IOError, ArgumentError, TypeError
          nil
        end

        # Returns true if the worker starts to write a result within
        # `seconds`. A wait on the pipe finds a worker that is stuck
        # anywhere: in Ruby code, in a C call, or on a machine that swaps.
        # A timeout inside the worker finds only the first of these.
        def answered?(seconds)
          return true if seconds.zero? || @back.wait_readable(seconds)

          @overdue = [seconds, self.class.resident_of(@pid)]
          false
        end

        # The reason that the worker stopped. Call it after the pipe
        # closes.
        def why
          @why ||= begin
            # After a pipe error, the worker is not usable. Kill it first,
            # because `wait2` waits forever for a live process. A kill of a
            # process that is already gone does not change its status.
            @status = stop!
            if @overdue
              seconds, resident = @overdue
              "the worker ran past #{seconds}s on this example, holding #{resident} MB " \
                "(ZR_TEST_TIMEOUT changes the bound)"
            elsif @status.nil?
              "the worker went without a status"
            elsif @status.signaled?
              "the worker died on SIG#{Signal.signame(@status.termsig)}, holding #{@resident} MB"
            else
              "the worker exited #{@status.exitstatus} without answering"
            end
          end
        end

        # Ctrl-C goes to the workers and the parent. An interrupted run
        # must not report thousands of failures.
        def interrupted? = (why && @status&.signaled? && @status.termsig == Signal.list["INT"])

        # Returns a failed result for the example that the worker ran when
        # it died, so the report shows that example.
        def epitaph(klass, name)
          file, line = klass.instance_method(name).source_location
          error = RuntimeError.new(why)
          error.set_backtrace(["#{file}:#{line}:in '#{name}'"])
          result = Minitest::Result.new(name)
          result.klass = klass.name
          result.source_location = [file, line]
          result.time = 0.0
          result.failures << Minitest::UnexpectedError.new(error)
          result
        end

        # Stops the worker and all processes it started, and returns its
        # status. SIGTERM lets the worker kill the children in other
        # process groups. After one second, SIGKILL stops the worker's
        # group, which contains the forks of a build, and then the worker.
        def stop!
          signal("TERM", @pid)
          status = reap(1.0)
          signal("KILL", -@pid)
          signal("KILL", @pid)
          status || Process.wait2(@pid).last
        end

        def signal(name, pid)
          Process.kill(name, pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end

        # The worker's status, or nil when it does not stop in `seconds`.
        def reap(seconds)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
          loop do
            pid, status = Process.wait2(@pid, Process::WNOHANG)
            return status if pid
            return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

            sleep 0.01
          end
        end

        # Always nil, so a caller can write `worker = worker.close`.
        def close
          @jobs.close unless @jobs.closed?
          @back.close unless @back.closed?
          stop! unless @why
          nil
        rescue Errno::ESRCH, Errno::ECHILD, IOError
          nil
        end
      end
    end
  end
end
