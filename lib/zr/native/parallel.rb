# frozen_string_literal: true

require "etc"
require_relative "resident"

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
      # parent's heap (copy on write) and then grows a heap of about the
      # same size. Thus the parent's live set (after `warmed`) is the cost
      # of one worker, and the free memory divided by that cost is the count.
      #
      # A fixed count does not work for both compilers: a worker of the
      # compiled compiler uses about 10 GB. Six such workers put a 16 GB
      # machine into swap, and a run that swaps takes about ten times as long.
      #
      # `ZR_JOBS` overrides this limit. Use it to measure an entry of the
      # table above `Build.jobs`.
      def afforded(jobs)
        return jobs if ENV.key?("ZR_JOBS")

        held = held_bytes
        return jobs if held.zero?

        [[(machine_bytes - held) / held, jobs].min, 1].max
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

      def heap_bytes
        GC.stat_heap.sum { |_, pool| pool[:heap_eden_slots].to_i * pool[:slot_size].to_i } + GC.stat(:malloc_increase_bytes).to_i
      rescue StandardError, NotImplementedError
        0
      end

      # Returns the physical memory. POSIX gives it on macOS and on musl.
      # When the system does not give it, this assumes a small machine (8 GB).
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
