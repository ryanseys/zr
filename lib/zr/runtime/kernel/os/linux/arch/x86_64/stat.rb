module Zr::Kern
  # The struct stat of x86_64 Linux: nlink is 64 bits, before mode.
  STAT_LEN = 144

  # Returns stat(2) as fixnums in an Array: dev, ino, mode, nlink, uid,
  # gid, rdev, size, blksize, blocks, then atime, mtime and ctime as
  # seconds and nanoseconds.
  #: (ptr) -> value
  def zr_os_stat_rows(buf)
    out = zr_ary_new(16)
    zr_ary_push(out, zr_fix(Machine.load64(buf, 0)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 8)))
    zr_ary_push(out, zr_fix(zr_os_stat_mode(buf)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 16)))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 28))))
    zr_ary_push(out, zr_fix(Machine.u32(Machine.load32(buf, 32))))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 40)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 48)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 56)))
    zr_ary_push(out, zr_fix(Machine.load64(buf, 64)))
    at = 72
    while at < 120
      zr_ary_push(out, zr_fix(Machine.load64(buf + at, 0)))
      at += 8
    end
    out
  end

  # st_size.
  #: (ptr) -> word
  def zr_os_stat_size(buf)
    Machine.load64(buf, 48)
  end

  # st_mode, 32 bits at offset 24.
  #: (ptr) -> word
  def zr_os_stat_mode(buf)
    Machine.u32(Machine.load32(buf, 24))
  end
end
