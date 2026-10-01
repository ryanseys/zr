# WASI's clocks, as ruby identifies them there: wasi-libc's clockid_t is
# a pointer, so ruby identifies each clock with a Symbol, and CLOCK_IDS
# gives the WASI clock id that each Symbol represents.
module Process
  CLOCK_REALTIME = :CLOCK_REALTIME
  CLOCK_MONOTONIC = :CLOCK_MONOTONIC
  CLOCK_PROCESS_CPUTIME_ID = :GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID

  CLOCK_IDS = { CLOCK_REALTIME: 0, CLOCK_MONOTONIC: 1, GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID: 2 }.freeze
  private_constant :CLOCK_IDS
end
