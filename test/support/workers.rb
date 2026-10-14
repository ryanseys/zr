# frozen_string_literal: true

require_relative "flag"
require "etc"

module Zr
  module Test
    # How many forked test workers a run starts (`ForkPool`), and when a
    # worker is replaced.
    module Workers
      # The memory for one worker and the child it starts, in GB. A
      # compile uses most of 1 GB, and the built binary (or wasmtime) can
      # use the same again.
      WORKER_GB = 2

      # The number of workers. `MT_CPU` is the Minitest variable for it.
      #
      # Memory limits this number, not cores. A run that swaps does not
      # fail, but takes ten times as long. Ten workers on a 12-core, 16 GB
      # laptop made a 65-second tier take 11 minutes, with 104 false
      # errors. Eight workers (all 16 GB) stopped the whole machine. So
      # the pool keeps `reserve` GB for the OS and the other programs,
      # and two cores for the parent and the OS: 6 workers on that laptop.
      def self.size = Integer(ENV.fetch("MT_CPU") { fit(Etc.nprocessors, gigabytes) })

      def self.fit(cores, gigabytes)
        [[cores - 2, (gigabytes - reserve(gigabytes)) / WORKER_GB].min, 1].max
      end

      # The memory that the workers leave free, in GB: a quarter of the
      # machine, and at least 4 GB.
      def self.reserve(gigabytes) = [4, gigabytes / 4].max

      # The physical memory of this machine, in GB. The POSIX call works
      # on macOS and on musl. If it fails, assume a small machine.
      def self.gigabytes
        Etc.sysconf(Etc::SC_PHYS_PAGES) * Etc.sysconf(Etc::SC_PAGE_SIZE) / (1 << 30)
      rescue StandardError, NotImplementedError
        8
      end

      # The maximum time for one example, in seconds. After this time, the
      # pool kills the worker and reports that example as a failure. Thus a
      # compile that loops, or a machine that swaps, costs one example and
      # not the tier. `ZR_TEST_TIMEOUT=0` waits forever, for a debugger.
      DEADLINE = Integer(ENV.fetch("ZR_TEST_TIMEOUT", 180))

      # The memory, in MB, that a worker can *add* before the pool
      # replaces it. A process grew 426 MB over 388 compiles, and 696 MB
      # over the heaviest area. So this limit replaces the heavy workers
      # and not the usual ones.
      #
      # The limit applies to growth, not to the total resident size. The
      # parent warms the compiler before it forks, so each worker starts
      # with a few hundred MB of shared pages. With a total limit, the pool
      # would replace each worker after a few examples, and a fork is not
      # free. Growth is also the correct measure, because the pool replaces
      # a worker for the heap it allocated and that Ruby does not release.
      RECYCLE_MB = Integer(ENV.fetch("ZR_TEST_RECYCLE_MB", 600))

      # Whether a run stops at its first failure (`ZR_TEST_FAIL_FAST=1`).
      def self.fail_fast? = Zr::Test.flag?("ZR_TEST_FAIL_FAST")
    end
  end
end
