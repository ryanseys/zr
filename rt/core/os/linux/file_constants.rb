# Linux's open(2), flock(2) and fnmatch numbers, as File::Constants
# names them, with the flags only Linux has.
class File < IO
  # ruby names this module File::Constants and IO takes it by
  # inclusion, so File::APPEND and IO::APPEND are one constant.
  module Constants
    RDONLY = 0
    WRONLY = 1
    RDWR = 2
    APPEND = 1024
    CREAT = 64
    EXCL = 128
    NONBLOCK = 2048
    TRUNC = 512
    NOCTTY = 256
    BINARY = 0
    SHARE_DELETE = 0
    SYNC = 1052672
    DSYNC = 4096
    RSYNC = 1052672
    NOFOLLOW = 32768
    NOATIME = 262144
    DIRECT = 65536
    TMPFILE = 4210688

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
