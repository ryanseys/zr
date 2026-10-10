# frozen_string_literal: true

# wasi-libc's waitpid(2) flags, which are 0 where no child can be waited
# for, and the tables the portable Process reads: WASI has no priorities
# and no resource limits, so it names none.
module Process
  WNOHANG = 0
  WUNTRACED = 0

  RLIMITS = {}.freeze
  RLIM_NAMES = {}.freeze
  # musl's sysconf name for the maximum number of supplementary groups,
  # and the maximum that ruby lets a program request.
  SC_NGROUPS_MAX = 3
  MAX_GROUPS = 65_536
  private_constant :RLIMITS, :RLIM_NAMES, :SC_NGROUPS_MAX, :MAX_GROUPS
end
