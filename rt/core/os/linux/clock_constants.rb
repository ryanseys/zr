# Linux's clock_gettime(2) ids, as Process names them.
module Process
  CLOCK_REALTIME = 0
  CLOCK_MONOTONIC = 1
  CLOCK_PROCESS_CPUTIME_ID = 2
  CLOCK_THREAD_CPUTIME_ID = 3

  # Every clock here is a number.
  CLOCK_IDS = {}.freeze
  private_constant :CLOCK_IDS
end
