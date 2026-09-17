# frozen_string_literal: true

require "etc"
require "minitest"

module Ze0
  module Test
    # Minitest's parallel executor, forking.
    #
    # `Minitest.parallel_executor` is the one object minitest asks for
    # when a suite says `parallelize_me!`: it is handed `[klass, method,
    # reporter]` and is trusted to run it and give the reporter a
    # result. The executor minitest ships runs them in threads, which
    # buys nothing here -- a ze0 compile is the compiler's own Ruby, and
    # the GVL lets one thread at a time hold it.
    #
    # So this one forks. The parent loads every test file once -- 0.4 s
    # and 68 MB for the whole spec tier -- and a worker is a fork of
    # that, which costs a page table and no reload. The unit of work is
    # one example rather than one file, so no worker sits idle while a
    # neighbour still has ninety examples in front of it.
    #
    # Forking is also what bounds memory. Ruby does not give heap pages
    # back: this tier run in one process reached 4.1 GB and was still
    # climbing. A worker past `RECYCLE_MB` is closed and a fresh one is
    # forked from the parent, which has not grown, so a whole run sits
    # at a flat `size * RECYCLE_MB`.
    #
    # And it is what makes a miscompile readable. A worker the kernel
    # kills takes its pipe with it; the parent reaps it and reports the
    # example it was holding as an error naming that example, instead of
    # stopping the run with no answer for anything.
    class ForkPool
      # What a worker and the child it starts hold between them, in
      # gigabytes: a compile wants most of one, and the binary it built
      # -- or wasmtime -- wants as much again.
      WORKER_GB = 2

      # How many workers. `MT_CPU` is minitest's own name for this.
      #
      # Memory bounds this and not cores. A machine short of it swaps,
      # and a run that swaps does not fail: it takes ten times as long.
      # Twelve workers on this sixteen-gigabyte laptop turned a
      # sixty-five second tier into eleven minutes and a hundred errors,
      # which is the whole reason for the cap.
      def self.size = Integer(ENV.fetch("MT_CPU") { [[Etc.nprocessors, gigabytes / WORKER_GB].min, 1].max })

      # What this machine has. POSIX answers on macOS and on musl
      # alike; a machine that will not say is treated as a small one.
      def self.gigabytes
        Etc.sysconf(Etc::SC_PHYS_PAGES) * Etc.sysconf(Etc::SC_PAGE_SIZE) / (1 << 30)
      rescue StandardError, NotImplementedError
        8
      end

      # What a worker may reside in before it is retired, in megabytes.
      # The pilot measured a process at 426 MB over 388 compiles and at
      # 696 MB over the heaviest area, so this retires the heavy ones
      # and leaves the ordinary ones alone.
      RECYCLE_MB = Integer(ENV.fetch("ZE0_RECYCLE_MB", 600))

      attr_reader :size

      def initialize(size: ForkPool.size, recycle_mb: RECYCLE_MB)
        @size = size
        @recycle_mb = recycle_mb
        @queue = Thread::Queue.new
        @threads = []
        @interrupted = false
      end

      # One thread a worker. The thread owns its worker outright: it is
      # the only writer to that pipe and the only reader of the answer,
      # so a job is never handed to a worker that is still busy.
      def start
        # A worker is a fork of this process and shares its stdout.
        # Whatever the reporter has written must be out of the buffer
        # before a fork, or a worker inherits it and writes it again.
        $stdout.sync = true
        @threads = Array.new(@size) { Thread.new { serve } }
      end

      def <<(job) = @queue << job

      # Minitest asks for this once every suite has been handed over.
      # The nils queue behind the jobs, so each thread finishes what is
      # in front of it and then stops.
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
          elsif worker.resident > @recycle_mb
            worker = worker.close
          end
          reporter.synchronize { reporter.record result }
        end
      ensure
        worker&.close
      end

      # One forked process, and the two pipes it answers on.
      class Worker
        attr_reader :resident

        def self.open
          jobs = IO.pipe
          back = IO.pipe
          $stdout.flush
          pid = Process.fork do
            jobs.last.close
            back.first.close
            serve(jobs.first, back.last)
          end
          jobs.first.close
          back.last.close
          new(pid, jobs.last, back.first)
        end

        # The worker's whole life: read which example, run it, and
        # answer with the result and with what this process now resides
        # in. `exit!` because the report belongs to the parent -- a
        # worker that ran minitest's own `at_exit` would write a second
        # one.
        def self.serve(jobs, back)
          Minitest.parallel_executor = nil
          back.sync = true
          loop do
            # A suite is an anonymous class with a name of its own
            # ("GC programs"), so it cannot be looked up by constant. It
            # does not need to be: a worker is a fork of the parent and
            # holds the same list in the same order.
            at, name = Marshal.load(jobs)
            answer(Minitest::Runnable.runnables[at].new(name).run, back)
          end
        rescue EOFError, IOError
          nil # the parent has gone
        ensure
          exit!(0)
        end

        # The result, and what this process now resides in. Even
        # neutered, a result can hold something Marshal will not take;
        # a bare one saying so beats dying and leaving the parent to
        # report that a worker went quiet.
        def self.answer(result, back)
          Marshal.dump([portable(result), resident], back)
        rescue TypeError => e
          bare = Minitest::Result.new(result.name)
          bare.klass = result.klass
          bare.source_location = result.source_location
          bare.assertions = result.assertions
          bare.time = result.time
          bare.failures << Minitest::UnexpectedError.new(flat(RuntimeError.new("this result does not cross a pipe: #{e.message}")))
          Marshal.dump([bare, resident], back)
        end

        # A failure holds an exception, and an exception the compiler
        # raised can hold anything at all -- an IO, a Proc, a whole
        # program -- none of which crosses a pipe. Only the message and
        # the backtrace are wanted on the other side, so that is all
        # that is sent. `minitest/server` sanitizes for the same reason.
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

        # The pool's own frames come off with the message: the example
        # was called from here, but that is not where anything went
        # wrong, and minitest's backtrace filter does not know this file.
        def self.flat(error)
          backtrace = (error.backtrace || []).reject { |at| at.start_with?(__FILE__) }
          error.class.new(error.message).tap { |flat| flat.set_backtrace(backtrace) }
        end

        # What this process resides in, in megabytes. Ruby has no
        # portable way to ask -- macOS has no `/proc` -- so `ps`
        # answers, which costs one more child beside the one nearly
        # every example already starts.
        def self.resident = `ps -o rss= -p #{Process.pid}`.to_i / 1024

        def initialize(pid, jobs, back)
          @pid = pid
          @jobs = jobs
          @back = back
          @jobs.sync = true
          @resident = 0
        end

        # The result of running `klass#name` here, or nil if this worker
        # did not live to answer.
        def ask(klass, name)
          Marshal.dump([Minitest::Runnable.runnables.index(klass), name], @jobs)
          result, @resident = Marshal.load(@back)
          result
        rescue EOFError, IOError, ArgumentError, TypeError
          nil
        end

        # What killed it, asked for once the pipe has said it is gone.
        def why
          @why ||= begin
            # Whatever went wrong on the pipe, this is not a worker we
            # can talk to any more, and `wait2` would wait forever on
            # one that is somehow still alive. A signal to a process
            # already gone leaves the status it died with standing.
            begin
              Process.kill("KILL", @pid)
            rescue Errno::ESRCH
              nil
            end
            _, @status = Process.wait2(@pid)
            if @status.nil?
              "the worker went without a status"
            elsif @status.signaled?
              "the worker died on SIG#{Signal.signame(@status.termsig)}, holding #{@resident} MB"
            else
              "the worker exited #{@status.exitstatus} without answering"
            end
          end
        end

        # Ctrl-C reaches a worker as well as the parent, and one run
        # that was interrupted should not read as thousands of defects.
        def interrupted? = (why && @status&.signaled? && @status.termsig == Signal.list["INT"])

        # A result for the example the worker was holding when it died,
        # so the report names it rather than losing it.
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

        # Always nil, so a caller can write `worker = worker.close`.
        def close
          @jobs.close unless @jobs.closed?
          @back.close unless @back.closed?
          unless @why
            Process.kill("KILL", @pid)
            Process.wait(@pid)
          end
          nil
        rescue Errno::ESRCH, Errno::ECHILD, IOError
          nil
        end
      end
    end
  end
end
