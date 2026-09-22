# frozen_string_literal: true

require "etc"
require_relative "resident"

module Ze0
  module Native
    # A map over many items in forked workers, for work that only computes
    # (a cold unit's passes and assembly): each worker takes a bin of
    # items, dealt heaviest first to the lightest bin, and hands its
    # answers back through a pipe. The answers come back in item order
    # whatever the bins, so the result does not depend on `jobs`.
    module Parallel
      module_function

      # `work` over `items`, in `jobs` workers at most. `weight` answers an
      # item's cost; below `floor` in all, or with one job, or where there
      # is no fork, the map runs here. A worker that raises raises here the
      # error of the first item, in item order, that raised.
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

      # What the parent owes its workers before it forks.
      # `Process.warmup` runs a full collection, compacts what is left and
      # promotes it to the old generation, then frees the pages that came
      # empty: a worker then inherits a heap whose objects a minor
      # collection steps over, instead of one it marks again and dirties
      # a page at a time.
      #
      # Sampled while a self-compile ran, a worker spent 92% of its
      # running time in ruby's collector and the parent 64%, and nearly
      # all of the worker's was marking what the fork had given it.
      def warmed
        Process.warmup if Process.respond_to?(:warmup)
      end

      # No more workers than this machine will hold.
      #
      # Memory bounds this and not cores. A worker inherits the parent's
      # heap -- which the fork shares, page by page, until one of them
      # writes -- and then grows a heap of its own of about the same size
      # again while it works through its bin. So what the parent holds,
      # which `warmed` has just settled to the live set, is what one more
      # worker costs, and what this machine has over that is how many of
      # them fit.
      #
      # The number this replaces was a flat six, and the comment beside
      # it -- "each worker holds half a gigabyte or more" -- was measured
      # of the compiler running under ruby. A worker of the *compiled*
      # compiler holds ten gigabytes: six of them drove this sixteen
      # gigabyte machine into 16.4 GB of swap, and `rake stage2` had not
      # finished at seventeen minutes. A run that swaps does not fail, it
      # takes ten times as long, which is the worst way for this to go
      # wrong. Reading the live set covers both compilers with no
      # constant to keep true.
      #
      # `ZE0_JOBS` overrules it, which is how a row of the table above
      # `Build.jobs` is measured.
      def afforded(jobs)
        return jobs if ENV.key?("ZE0_JOBS")

        held = held_bytes
        return jobs if held.zero?

        [[(machine_bytes - held) / held, jobs].min, 1].max
      end

      # What this process holds, which a worker forked from it starts
      # with and grows from: what it resides in, where the system says
      # (`Resident`); else its heap, the cells of every pool and the
      # payload they hold (`malloc_increase_bytes` is ze0's live payload,
      # and under ruby what grew since the last collection -- the floor
      # ruby reads without Fiddle). The compiled compiler's bytes are
      # mostly payload: a worker of it held ten gigabytes where its
      # cells said one.
      def held_bytes
        Resident.bytes_of(Process.pid) || heap_bytes
      end

      def heap_bytes
        GC.stat_heap.sum { |_, pool| pool[:heap_eden_slots].to_i * pool[:slot_size].to_i } + GC.stat(:malloc_increase_bytes).to_i
      rescue StandardError, NotImplementedError
        0
      end

      # What this machine has. POSIX answers on macOS and on musl alike;
      # a machine that will not say is treated as a small one.
      def machine_bytes
        Etc.sysconf(Etc::SC_PHYS_PAGES) * Etc.sysconf(Etc::SC_PAGE_SIZE)
      rescue StandardError, NotImplementedError
        8 * (1 << 30)
      end

      # The item indexes of each bin: the heaviest item first, each to the
      # bin that weighs least so far (the lowest such bin on a tie).
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

      # A worker over the items of `bin`, and a thread that reads its
      # answer as it writes, so a full pipe never stops it.
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

      # `[:ok, answers]`, or `[:raised, index, class name, message]` for
      # the first item of the bin that raised.
      def answered(items, bin, work)
        done = []
        bin.each do |i|
          done << work.call(items[i])
        rescue StandardError => e
          return [:raised, i, e.class.name, e.message]
        end
        [:ok, done]
      end

      # The worker's answers placed at their indexes; its failure, if any.
      def collected(pid, reader, bin, answers)
        bytes = reader.value
        _, status = Process.wait2(pid)
        raise "a worker stopped without an answer (#{status})" if bytes.empty?

        tag, *rest = Marshal.load(bytes)
        return rest if tag == :raised

        bin.zip(rest.first) { |i, answer| answers[i] = answer }
        nil
      end

      # The failure of the lowest item, raised as its own class when that
      # class takes a message alone.
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
