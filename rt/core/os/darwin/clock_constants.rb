# darwin's clock_gettime(2) ids, as Process names them.
module Process
  CLOCK_REALTIME = 0
  CLOCK_MONOTONIC = 6
  CLOCK_PROCESS_CPUTIME_ID = 12
  CLOCK_THREAD_CPUTIME_ID = 16
end
