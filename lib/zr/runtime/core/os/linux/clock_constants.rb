# frozen_string_literal: true

# Linux's clock_gettime(2) ids, with Process's names for them.
module Process
  CLOCK_REALTIME = 0
  CLOCK_MONOTONIC = 1
  CLOCK_PROCESS_CPUTIME_ID = 2
  CLOCK_THREAD_CPUTIME_ID = 3
  CLOCK_MONOTONIC_RAW = 4
  CLOCK_REALTIME_COARSE = 5
  CLOCK_MONOTONIC_COARSE = 6
  CLOCK_BOOTTIME = 7
  CLOCK_REALTIME_ALARM = 8
  CLOCK_BOOTTIME_ALARM = 9
  CLOCK_TAI = 11

  # Every clock here is a number.
  CLOCK_IDS = {}.freeze
  private_constant :CLOCK_IDS
end
