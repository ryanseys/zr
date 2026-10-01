module Zr::Kern
  # zlib's stream and the values that all its calls use: zlib.h's
  # z_stream and its codes, and zutil.c's error strings. A ZStream is the
  # C z_stream without the allocator hooks, which no code here sets.
  # Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.
  Libc.import :malloc, [Word] => Ptr
  Libc.import :free, [Ptr] => Void
  Libc.import :memmove, [Ptr, Ptr, Word] => Ptr
  Libc.import :memset, [Ptr, I32, Word] => Ptr

  ZStream = layout next_in: Ptr, avail_in: Word, total_in: Word, next_out: Ptr, avail_out: Word, total_out: Word, msg: Ptr, state: Ptr, data_type: Word, adler: Word

  # The flush modes.
  Z_NO_FLUSH = 0
  Z_PARTIAL_FLUSH = 1
  Z_SYNC_FLUSH = 2
  Z_FULL_FLUSH = 3
  Z_FINISH = 4
  Z_BLOCK = 5
  Z_TREES = 6

  # The return codes of a call.
  Z_OK = 0
  Z_STREAM_END = 1
  Z_NEED_DICT = 2
  Z_ERRNO = 0 - 1
  Z_STREAM_ERROR = 0 - 2
  Z_DATA_ERROR = 0 - 3
  Z_MEM_ERROR = 0 - 4
  Z_BUF_ERROR = 0 - 5
  Z_VERSION_ERROR = 0 - 6

  # The only compression method, and the values of data_type.
  Z_DEFLATED = 8
  Z_BINARY = 0
  Z_TEXT = 1
  Z_UNKNOWN = 2

  # The zlib version of this port, as zlibVersion returns it.
  sig [] => Ptr
  def zr_zlib_version_text
    Machine.bytes("1.3.1\0")
  end

  # zError: the text of a code. It is "" for Z_OK and for a code that zlib
  # never returns.
  sig [Word] => Ptr
  def zr_zlib_error_text(err)
    if err == Z_NEED_DICT
      return Machine.bytes("need dictionary\0")
    elsif err == Z_STREAM_END
      return Machine.bytes("stream end\0")
    elsif err == Z_ERRNO
      return Machine.bytes("file error\0")
    elsif err == Z_STREAM_ERROR
      return Machine.bytes("stream error\0")
    elsif err == Z_DATA_ERROR
      return Machine.bytes("data error\0")
    elsif err == Z_MEM_ERROR
      return Machine.bytes("insufficient memory\0")
    elsif err == Z_BUF_ERROR
      return Machine.bytes("buffer error\0")
    elsif err == Z_VERSION_ERROR
      return Machine.bytes("incompatible version\0")
    end
    Machine.bytes("\0")
  end

  # ZSWAP32: reverses the byte order of a 32-bit word.
  sig [Word] => Word
  def zr_zlib_swap32(q)
    ((q >> 24) & 255) + ((q >> 8) & 65280) + ((q & 65280) << 8) + ((q & 255) << 24)
  end

  # The `i`th element of an array of 32-bit words.
  sig [Ptr, Word] => Word
  def zr_zlib_u32(p, i)
    Machine.word(Machine.load32(p + (i * 4), 0))
  end

  sig [Ptr, Word, Word] => Void
  def zr_zlib_set_u32(p, i, v)
    Machine.store32(p + (i * 4), 0, Machine.i32(v))
  end

  # The byte at `p`, as a word.
  sig [Ptr] => Word
  def zr_zlib_byte(p)
    Machine.word(Machine.load8(p, 0))
  end

  # Copies `n` bytes from `from` to `out`, one byte at a time. Thus a copy
  # that overlaps its source repeats the bytes it wrote, as a match copy
  # must.
  sig [Ptr, Ptr, Word] => Void
  def zr_zlib_copy_bytes(out, from, n)
    while n > 0
      Machine.store8(out, 0, Machine.load8(from, 0))
      out += 1
      from += 1
      n -= 1
    end
  end
end
