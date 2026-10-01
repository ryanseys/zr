# frozen_string_literal: true

module Zr
  module Dev
    # Calls the block for each of `items` on `jobs` threads, and returns the
    # results in the order of `items`. A tool uses it when each item runs its
    # own processes, so that threads are enough.
    #
    # `each` is called with each result on the calling thread, in the order
    # that the results finish, so a tool can print a line as soon as it has
    # one. An exception in the block stops the work and is raised in the
    # caller.
    def self.parallel_map(items, jobs:, each: nil)
      items = items.to_a
      return [] if items.empty?

      queue = Queue.new
      items.each_with_index { |item, index| queue << [item, index] }
      queue.close
      done = Queue.new
      workers = Array.new([jobs, items.size].min) do
        Thread.new do
          while (job = queue.pop)
            item, index = job
            done << [index, yield(item)]
          end
        rescue StandardError => e
          done << e
        end
      end
      results = Array.new(items.size)
      items.size.times do
        got = done.pop
        raise got if got.is_a?(Exception)

        index, result = got
        results[index] = result
        each&.call(result)
      end
      results
    ensure
      workers&.each(&:kill)
    end
  end
end
