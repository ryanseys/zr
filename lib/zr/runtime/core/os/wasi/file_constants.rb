# frozen_string_literal: true

# wasi-libc's open(2), flock(2) and fnmatch numbers, with File::Constants's
# names for them: the status flags are WASI's fdflags, the creation flags
# its oflags shifted up 12 bits, and the access modes bits of their own.
class File < IO
  # ruby calls this module File::Constants and IO includes it,
  # so File::APPEND and IO::APPEND are one constant.
  module Constants
    RDONLY = 67108864
    WRONLY = 268435456
    RDWR = 335544320
    NONBLOCK = 4
    APPEND = 1
    SHARE_DELETE = 0
    SYNC = 16
    DSYNC = 2
    RSYNC = 8
    NOFOLLOW = 16777216
    CREAT = 4096
    TRUNC = 32768
    EXCL = 16384
    NOCTTY = 0
    BINARY = 0

    # flock(2): LOCK_SH 1, LOCK_EX 2, LOCK_UN 8, with LOCK_NB 4 added.
    LOCK_SH = 1
    LOCK_EX = 2
    LOCK_NB = 4
    LOCK_UN = 8

    FNM_NOESCAPE = 1
    FNM_PATHNAME = 2
    FNM_DOTMATCH = 4
    FNM_CASEFOLD = 8
    FNM_EXTGLOB = 16
    FNM_SYSCASE = 0
    FNM_SHORTNAME = 0

    NULL = "/dev/null"
  end
end
