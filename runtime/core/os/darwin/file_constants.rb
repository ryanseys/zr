# darwin's open(2), flock(2) and fnmatch numbers, as File::Constants
# names them.
class File < IO
  # ruby names this module File::Constants and IO takes it by
  # inclusion, so File::APPEND and IO::APPEND are one constant.
  module Constants
    RDONLY = 0
    WRONLY = 1
    RDWR = 2
    NONBLOCK = 4
    APPEND = 8
    SHARE_DELETE = 0
    SYNC = 128
    DSYNC = 4194304
    NOFOLLOW = 256
    CREAT = 512
    TRUNC = 1024
    EXCL = 2048
    NOCTTY = 131072
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
