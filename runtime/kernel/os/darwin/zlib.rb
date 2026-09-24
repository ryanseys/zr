# The operating system a gzip header names: zutil.h's OS_CODE, which is
# 19 for a build on macOS, as ruby's zlib is here.
sig [] => Word
machine def zr_zlib_os_code
  19
end
