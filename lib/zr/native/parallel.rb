# frozen_string_literal: true

require "etc"
require_relative "resident"
require_relative "../config"
require_relative "../paths"

module Zr
  module Native
    # Maps work over many items in forked workers. Use it only for work
    # that computes and has no side effects (a cold unit's passes and
    # assembly). Each worker gets a bin of items: the heaviest item goes
    # first, to the lightest bin. Each worker writes its results to a pipe.
    # The results are in item order, so they do not depend on `jobs`.
    module Parallel
      module_function

      # Runs `work` over `items` in `jobs` workers at most. `weight` returns
      # the cost of an item. The map runs in this process when the total
      # cost is below `floor`, when there is one job, or when fork is not
      # available. When workers raise, this raises the error of the first
      # item (in item order) that raised.
      def map(items, jobs:, weight:, floor: 0, &work)
        weights = items.map(&weight)
        jobs = [jobs, items.size].min
        return items.map(&work) if jobs <= 1 || weights.sum < floor || !Process.respond_to?(:fork)

        answers = Array.new(items.size)
        warmed
        jobs = afforded(jobs)
        failures = dealt(weights, jobs).map { |bin| started(items, bin, work) }.filter_map do |pid, reader, bin|
          collected(pid, reader, bin, answers)
        end
        raise_first(failures) unless failures.empty?
        answers
      end

      # Prepares the heap before the fork. `Process.warmup` runs a full
      # collection, compacts the heap, promotes the live objects to the old
      # generation and frees empty pages. A minor collection in a worker
      # then skips the inherited objects. It does not mark them again and
      # dirty the shared pages one at a time.
      #
      # Without this, a sampled self-compile worker spent 92% of its time
      # in ruby's collector (the parent 64%). Almost all of it was marking
      # the objects that the fork gave it.
      def warmed
        Process.warmup if Process.respond_to?(:warmup)
      end

      # Limits the worker count to the number that fits in this machine's
      # memory. Memory is the limit, not cores. A worker shares the
      # parent's heap (copy on write), and after `warmed` it copies only
      # the pages that it writes. Under ruby, a worker that assembles eval
      # support's functions added 1.1 GB to a parent of 4.8 GB, and one that
      # only took fingerprints 0.34 GB (the machine's used memory, from
      # `vm_stat`; a worker's own phys_footprint also counts the shared pages
      # that it reads). Five workers that assembled, from an estimate of a
      # quarter, made the machine swap 1.8 GB. Thus a worker costs a third
      # of the parent (WORKER_SHARE), and the workers get three quarters
      # of the available memory.
      #
      # A worker of the compiled compiler copies about all of the parent:
      # about 10 GB. Six such workers put a 16 GB machine into swap, and a
      # run that swaps takes about ten times as long.
      #
      # `ZR_JOBS` overrides this limit. Use it to measure an entry of the
      # table above `Build.jobs`.
      WORKER_SHARE = 3

      def afforded(jobs)
        return jobs if Config.current.jobs_given?

        held = held_bytes
        return jobs if held.zero?

        cost = Host.compiled? ? held : held / WORKER_SHARE
        available = available_bytes
        free = available ? available * 3 / 4 : machine_bytes - held
        [[free / cost, jobs].min, 1].max
      end

      # The memory that the system can give to new work now, or nil: Linux
      # gives it as MemAvailable. On macOS it is the machine less the
      # memory of processes (anonymous pages that are not purgeable), the
      # wired pages and the compressor; the file cache can be dropped.
      def available_bytes
        if File.readable?("/proc/meminfo")
          kb = File.read("/proc/meminfo")[/^MemAvailable:\s+(\d+)/, 1]
          return kb && kb.to_i * 1024
        end
        used = Resident.used_pages or return nil
        [machine_bytes - (used * Etc.sysconf(Etc::SC_PAGESIZE)), 0].max
      rescue SystemCallError, IOError, NotImplementedError
        nil
      end

      # Returns the memory of this process, which a forked worker starts
      # with. It is the resident size when the system gives it
      # (`Resident`). Otherwise it is the heap: the cells of every pool
      # plus their payload. `malloc_increase_bytes` is zr's live payload;
      # under ruby it is only the growth since the last collection (the
      # lower bound that ruby can read without Fiddle). The compiled
      # compiler's memory is mostly payload: 10 GB where its cells gave 1 GB.
      def held_bytes
        Resident.bytes_of(Process.pid) || heap_bytes
      end

      # Zero if the collector does not give its heap: then the worker
      # count is not limited by memory. Only an estimate, so a failure
      # must not stop the build.
      def heap_bytes
        GC.stat_heap.sum { |_, pool| pool[:heap_eden_slots].to_i * pool[:slot_size].to_i } + GC.stat(:malloc_increase_bytes).to_i
      rescue StandardError, NotImplementedError
        0
      end

      # Returns the physical memory. POSIX gives it on macOS and on musl.
      # When the system does not give it, this assumes a small machine (8 GB).
      # (A system without these sysconf names raises NameError or
      # NotImplementedError, and one with them can raise SystemCallError.)
      def machine_bytes
        Etc.sysconf(Etc::SC_PHYS_PAGES) * Etc.sysconf(Etc::SC_PAGE_SIZE)
      rescue StandardError, NotImplementedError
        8 * (1 << 30)
      end

      # Returns the item indexes of each bin. It puts the heaviest item
      # first, each into the lightest bin so far (the lowest bin on a tie).
      def dealt(weights, jobs)
        bins = Array.new(jobs) { [] }
        loads = Array.new(jobs, 0)
        weights.each_index.sort_by { |i| [-weights[i], i] }.each do |i|
          k = loads.index(loads.min)
          bins[k] << i
          loads[k] += weights[i]
        end
        bins.reject(&:empty?)
      end

      # Forks a worker for the items of `bin`. A thread reads the worker's
      # result while the worker writes, so a full pipe does not block it.
      def started(items, bin, work)
        r, w = IO.pipe
        pid = fork do
          r.close
          w.binmode
          w.write(Marshal.dump(answered(items, bin, work)))
          w.close
          exit!(0)
        end
        w.close
        [pid, Thread.new { r.binmode.read.tap { r.close } }, bin]
      end

      # Returns `[:ok, results]`, or `[:raised, index, class name, message]`
      # for the first item of the bin that raised.
      def answered(items, bin, work)
        done = []
        bin.each do |i|
          done << work.call(items[i])
        rescue StandardError => e
          return [:raised, i, e.class.name, e.message]
        end
        [:ok, done]
      end

      # Puts the worker's results at their indexes. Returns its failure, if any.
      def collected(pid, reader, bin, answers)
        bytes = reader.value
        _, status = Process.wait2(pid)
        raise "a worker stopped without an answer (#{status})" if bytes.empty?

        tag, *rest = Marshal.load(bytes)
        return rest if tag == :raised

        bin.zip(rest.first) { |i, answer| answers[i] = answer }
        nil
      end

      # Raises the failure of the lowest item. It uses the original error
      # class when that class accepts only a message.
      def raise_first(failures)
        _, name, message = failures.min_by(&:first)
        error = begin
          Object.const_get(name).new(message)
        rescue NameError, ArgumentError
          RuntimeError.new("#{name}: #{message}")
        end
        raise error
      end
    end
  end
end
