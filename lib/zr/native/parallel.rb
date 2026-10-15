# frozen_string_literal: true

require "etc"
require_relative "resident"
require_relative "../config"
require_relative "../paths"
require_relative "../timing"

module Zr
  module Native
    # Maps work over many items in forked workers. Use it only for work
    # that computes and has no side effects (a cold unit's passes and
    # assembly). The workers take the items from one queue, the heaviest
    # first, so a weight that is wrong costs little: a worker that is done
    # takes the next item. Each worker writes each result to a pipe as
    # soon as it has it, so with timing on the parent shows the progress
    # (`Progress`). The results are in item order, so they do not depend
    # on `jobs`.
    module Parallel
      module_function

      # The memory that `machine_bytes` assumes when the system does not give it.
      SMALL_MACHINE = 8 * (1 << 30)

      # Runs `work` over `items` in `jobs` workers at most. `weight` returns
      # the cost of an item, and `label` its name in the timing report. The
      # map runs in this process when the total cost is below `floor`, when
      # there is one job, or when fork is not available. When workers raise,
      # this raises the error of the first item (in item order) that raised.
      # @rbs [Item, Answer] (Array[Item] items, jobs: Integer, weight: ^(Item) -> Integer, ?floor: Integer,
      #                     ?label: (^(Item) -> String)?) { (Item) -> Answer } -> Array[Answer]
      def map(items, jobs:, weight:, floor: 0, label: nil, &work)
        weights = items.map(&weight)
        jobs = [jobs, items.size].min
        return items.map(&work) if jobs <= 1 || weights.sum < floor || !Process.respond_to?(:fork)

        # The workers' answers come back through Marshal, as bytes until
        # every worker is done.
        answers = Array.new(items.size) #: Array[untyped]
        warmed
        asked = jobs
        jobs = afforded(jobs)
        if Config.current.timing?
          warn format("zr: %d items in %d of %d workers%s", items.size, jobs, asked,
                      jobs < asked ? " (the free memory allows no more)" : "")
        end
        progress = Progress.new(weights) if Config.current.timing?
        Timing.tallies.clear
        queue, feed = IO.pipe
        feeder = fed(feed, weights)
        inbox = Thread::Queue.new
        workers = Array.new(jobs) { started(items, queue, feed, work, inbox) }
        queue.close
        failures = without_collections { collected(workers, inbox, answers, progress) }
        feeder.join
        progress&.finish(items, label)
        raise_first(failures) unless failures.empty?
        answers.map! { |bytes| Marshal.load(bytes) }
      end

      # The header of a worker's message: its kind, the item's index, the
      # item's seconds, and the size of the Marshal bytes that follow.
      HEAD = "CLEQ"
      HEAD_BYTES = 21
      ITEM = 0
      RAISED = 1
      DONE = 2

      # Runs the block with the collector off. While it collects, this
      # process makes only the answers, which it keeps, so a collection
      # would free almost nothing and mark the whole heap: 8 major
      # collections of 48 s in all, for eval support's prelude, while the
      # workers waited to write.
      #: [T] () { () -> T } -> T
      def without_collections
        was_off = GC.disable
        begin
          yield
        ensure
          GC.enable unless was_off
        end
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
      #: () -> void
      def warmed
        Timing.phase("warming the heap for the workers", "heap warmed") { Process.warmup } if Process.respond_to?(:warmup)
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
      # A worker of the compiled compiler (`zr-dev stage`) copies about all
      # of the parent, gigabytes each. A few such workers put a 16 GB
      # machine into swap, and a run that swaps takes many times as long.
      #
      # `ZR_JOBS` overrides this limit. Use it to measure an entry of the
      # table above `Build.jobs`.
      WORKER_SHARE = 3

      #: (Integer jobs) -> Integer
      def afforded(jobs)
        return jobs if Config.current.jobs_given?

        held = held_bytes
        return jobs if held.zero?

        cost = Binary.running? ? held : held / WORKER_SHARE
        available = available_bytes
        free = available ? available * 3 / 4 : machine_bytes - held
        [[free / cost, jobs].min, 1].max
      end

      # The memory that the system can give to new work now, or nil: Linux
      # gives it as MemAvailable. On macOS it is the machine less the
      # memory of processes (anonymous pages that are not purgeable), the
      # wired pages and the compressor; the file cache can be dropped.
      #: () -> Integer?
      def available_bytes
        if File.readable?("/proc/meminfo")
          kb = File.read("/proc/meminfo")[/^MemAvailable:\s+(\d+)/, 1]
          return kb && kb.to_i * 1024
        end
        used = Resident.used_pages or return nil
        page = Etc.sysconf(Etc::SC_PAGESIZE) or return nil
        [machine_bytes - (used * page), 0].max
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
      #: () -> Integer
      def held_bytes
        Resident.bytes_of(Process.pid) || heap_bytes
      end

      # Zero if the collector does not give its heap: then the worker
      # count is not limited by memory. Only an estimate, so a failure
      # must not stop the build.
      #: () -> Integer
      def heap_bytes
        GC.stat_heap.sum { |_, pool| pool[:heap_eden_slots].to_i * pool[:slot_size].to_i } + GC.stat(:malloc_increase_bytes).to_i
      rescue StandardError, NotImplementedError
        0
      end

      # Returns the physical memory. POSIX gives it on macOS and on musl.
      # When the system does not give it, this assumes a small machine (8 GB).
      # (A system without these sysconf names raises NameError or
      # NotImplementedError, and one with them can raise SystemCallError.)
      #: () -> Integer
      def machine_bytes
        pages = Etc.sysconf(Etc::SC_PHYS_PAGES)
        size = Etc.sysconf(Etc::SC_PAGE_SIZE)
        return SMALL_MACHINE unless pages && size

        pages * size
      rescue StandardError, NotImplementedError
        SMALL_MACHINE
      end

      # Starts a thread that writes the queue of the item indexes to `feed`,
      # the heaviest first (the lowest index on a tie), 4 bytes each, and
      # then closes it. A thread writes it, since a long queue is more than
      # a pipe holds. Each write and read is a whole number of indexes, so
      # two workers never share one.
      #: (IO feed, Array[Integer] weights) -> Thread
      def fed(feed, weights)
        order = weights.each_index.sort_by { |i| [-weights[i], i] }
        Thread.new { feed.binmode.write(order.pack("L*")).tap { feed.close } }
      end

      # Forks a worker that takes items from `queue`. The worker closes its
      # copy of `feed`, so its read after the last index gets nil. A thread
      # reads the worker's messages while the worker writes, so a full pipe
      # does not block it, and puts each in `inbox` as `[pid, bytes]`, then
      # `[pid, nil]` at the end of the pipe.
      #: [Item] (Array[Item] items, IO queue, IO feed, ^(Item) -> untyped work, Thread::Queue inbox) -> [Integer, Thread]
      def started(items, queue, feed, work, inbox)
        r, w = IO.pipe
        pid = fork do
          feed.close
          queue.binmode
          r.close
          w.binmode
          minor_only
          Timing.tallies.clear
          answered(items, queue, work) do |kind, i, seconds, payload|
            bytes = Marshal.dump(payload)
            w.write([kind, i, seconds, bytes.bytesize].pack(HEAD), bytes)
          end
          w.close
          exit!(0)
        end
        w.close
        [pid, Thread.new { read_messages(pid, r.binmode, inbox) }]
      end

      # Keeps a worker's collections minor. A major one marks the whole
      # heap that the fork gave the worker: gigabytes for eval support's
      # prelude, where lldb found each worker in such a mark at every
      # sample. After `warmed` the parent's objects are old, and a worker
      # lives only for its map, so the garbage it makes is young and a
      # minor collection finds it. The cost: an object that the worker
      # promotes and then drops stays until the worker ends.
      #: () -> void
      def minor_only
        GC.config(rgengc_allow_full_mark: false)
      end

      # Puts each message of the worker in `inbox` as `[pid, kind, index,
      # seconds, bytes]`, then `[pid]` at the end of the pipe.
      #: (Integer pid, IO r, Thread::Queue inbox) -> void
      def read_messages(pid, r, inbox)
        while (head = r.read(HEAD_BYTES))
          kind, i, seconds, size = head.unpack(HEAD) #: [Integer, Integer, Float, Integer]
          inbox << [pid, kind, i, seconds, r.read(size)]
        end
      ensure
        r.close
        inbox << [pid]
      end

      # Yields `ITEM, index, seconds, result` for each item, then `DONE`
      # with the worker's `Timing.tallies`. For the first item that raises,
      # it yields `RAISED, index` with the error's class name and message
      # instead and stops; the other workers take the rest.
      #: [Item] (Array[Item] items, IO queue, ^(Item) -> untyped work) { (Integer, Integer, Float, untyped) -> void } -> void
      def answered(items, queue, work)
        while (word = queue.read(4))
          i = word.unpack1("L") #: Integer
          began = Timing.now
          begin
            answer = work.call(items[i])
          rescue StandardError => e
            return yield RAISED, i, 0.0, [e.class.name, e.message]
          end
          yield ITEM, i, Timing.now - began, answer
        end
        yield DONE, 0, 0.0, Timing.tallies
      end

      # Reads the workers' messages until each pipe ends. It keeps each
      # answer's bytes at its index, adds each worker's tallies to this
      # process's, and returns the failures as `[index, class name,
      # message]`. Only the header is read here, so a worker's write never
      # waits on a Marshal.load.
      #: (Array[[Integer, Thread]] workers, Thread::Queue inbox, Array[untyped] answers, Progress? progress) -> Array[Array[untyped]]
      def collected(workers, inbox, answers, progress)
        failures = [] #: Array[Array[untyped]]
        ended = {} #: Hash[Integer, bool]
        open = workers.size
        while open.positive?
          pid, kind, i, seconds, bytes = inbox.pop
          if kind.nil?
            open -= 1
            next
          end

          case kind
          when ITEM
            answers[i] = bytes
            progress&.done(i, seconds)
          when RAISED then failures << [i, *Marshal.load(bytes)]
          when DONE then Timing.add(Marshal.load(bytes))
          end
          ended[pid] = true unless kind == ITEM
        end
        workers.each do |pid, reader|
          reader.join
          _, status = Process.wait2(pid)
          raise "a worker stopped without an answer (#{status})" unless ended[pid]
        end
        failures
      end

      # The progress of a map in workers, for a person who waits on a long
      # build (timing on). It prints a line at each tenth of the total
      # weight, with the time so far and the time left at the same rate
      # (the heaviest items go first, so that time is high at the start),
      # and at the end the slowest items.
      class Progress
        # @rbs @weights: Array[Integer]
        # @rbs @total: Integer
        # @rbs @weighed: Integer
        # @rbs @count: Integer
        # @rbs @tenth: Integer
        # @rbs @began: Float
        # @rbs @seconds: Array[[Float, Integer]]

        # The slowest items that `finish` names.
        SLOWEST = 10

        #: (Array[Integer] weights) -> void
        def initialize(weights)
          @weights = weights
          @total = weights.sum
          @weighed = 0
          @count = 0
          @tenth = 1
          @began = Timing.now
          @seconds = [] #: Array[[Float, Integer]]
        end

        #: (Integer i, Float seconds) -> void
        def done(i, seconds)
          @count += 1
          @weighed += @weights.fetch(i)
          @seconds << [seconds, i]
          return if @total.zero? || @weighed * 10 < @tenth * @total

          @tenth = (@weighed * 10 / @total) + 1
          elapsed = Timing.now - @began
          warn format("zr: %3d%% of the weight (%d of %d items) in %s, about %s left", @weighed * 100 / @total,
                      @count, @weights.size, clock(elapsed), clock(elapsed * (@total - @weighed) / @weighed))
        end

        # Prints the slowest items, by `label` or by index, and the time by
        # part that the workers tallied, as a share of the items' seconds.
        #: [Item] (Array[Item] items, (^(Item) -> String)? label) -> void
        def finish(items, label)
          work = @seconds.sum(0.0) { |seconds, _| seconds }
          warn format("zr: %.1f s of work in %.1f s", work, Timing.now - @began)
          warn "zr: the slowest items"
          @seconds.max(SLOWEST).each do |seconds, i|
            warn format("zr:   %8.2fs  weight %8d  %s", seconds, @weights.fetch(i), label ? label.call(items.fetch(i)) : "item #{i}")
          end
          Timing.report("the time by part, in all workers", work)
        end

        private

        #: (Float seconds) -> String
        def clock(seconds)
          minutes, rest = seconds.round.divmod(60)
          format("%d:%02d", minutes, rest)
        end
      end

      # Raises the failure of the lowest item. It uses the original error
      # class when that class accepts only a message.
      #: (Array[Array[untyped]] failures) -> bot
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
