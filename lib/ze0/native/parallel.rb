# frozen_string_literal: true

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
        failures = dealt(weights, jobs).map { |bin| started(items, bin, work) }.filter_map do |pid, reader, bin|
          collected(pid, reader, bin, answers)
        end
        raise_first(failures) unless failures.empty?
        answers
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
