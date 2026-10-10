# frozen_string_literal: true

# Linux's waitpid(2) flags, priority targets, resource limits and
# sysconf name, with Process's names for them.
module Process
  WNOHANG = 1
  WUNTRACED = 2

  # The target of a priority query: a process, a process group, a user.
  PRIO_PROCESS = 0
  PRIO_PGRP = 1
  PRIO_USER = 2

  # The resources a limit is set on, and the limit that is none: every
  # bit of an rlim_t.
  RLIMIT_AS = 9
  RLIMIT_CORE = 4
  RLIMIT_CPU = 0
  RLIMIT_DATA = 2
  RLIMIT_FSIZE = 1
  RLIMIT_LOCKS = 10
  RLIMIT_MEMLOCK = 8
  RLIMIT_MSGQUEUE = 12
  RLIMIT_NICE = 13
  RLIMIT_NOFILE = 7
  RLIMIT_NPROC = 6
  RLIMIT_RSS = 5
  RLIMIT_RTPRIO = 14
  RLIMIT_RTTIME = 15
  RLIMIT_SIGPENDING = 11
  RLIMIT_STACK = 3
  RLIM_INFINITY = 0xffff_ffff_ffff_ffff
  RLIM_SAVED_MAX = RLIM_INFINITY
  RLIM_SAVED_CUR = RLIM_INFINITY
  RLIMITS = { "AS" => RLIMIT_AS, "CORE" => RLIMIT_CORE, "CPU" => RLIMIT_CPU, "DATA" => RLIMIT_DATA,
              "FSIZE" => RLIMIT_FSIZE, "LOCKS" => RLIMIT_LOCKS, "MEMLOCK" => RLIMIT_MEMLOCK,
              "MSGQUEUE" => RLIMIT_MSGQUEUE, "NICE" => RLIMIT_NICE, "NOFILE" => RLIMIT_NOFILE,
              "NPROC" => RLIMIT_NPROC, "RSS" => RLIMIT_RSS, "RTPRIO" => RLIMIT_RTPRIO,
              "RTTIME" => RLIMIT_RTTIME, "SIGPENDING" => RLIMIT_SIGPENDING, "STACK" => RLIMIT_STACK }.freeze
  RLIM_NAMES = { "INFINITY" => RLIM_INFINITY, "SAVED_MAX" => RLIM_SAVED_MAX, "SAVED_CUR" => RLIM_SAVED_CUR }.freeze
  # sysconf's name for the maximum number of supplementary groups, and
  # the maximum that ruby lets a program request.
  SC_NGROUPS_MAX = 3
  MAX_GROUPS = 65_536
  private_constant :RLIMITS, :RLIM_NAMES, :SC_NGROUPS_MAX, :MAX_GROUPS
end
