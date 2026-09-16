# zlib over the vendored library (vendor/c/zlib). A z_stream is a
# malloc'd block the extension holds by its address, a Fixnum; each call
# here sets the fields one zlib call reads, makes it, and answers what
# it returned. The extension (rt/ext/zlib.rb) keeps the buffers, as
# zlib.c keeps them, and says how much room the output has.
Machine.import "calloc", [Word, Word] => Ptr
Machine.import "deflateInit2_", [Ptr, I32, I32, I32, I32, I32, Ptr, I32] => I32
Machine.import "deflate", [Ptr, I32] => I32
Machine.import "deflateEnd", [Ptr] => I32
Machine.import "deflateReset", [Ptr] => I32
Machine.import "deflateParams", [Ptr, I32, I32] => I32
Machine.import "deflateSetDictionary", [Ptr, Ptr, I32] => I32
Machine.import "deflateCopy", [Ptr, Ptr] => I32
Machine.import "inflateInit2_", [Ptr, I32, Ptr, I32] => I32
Machine.import "inflate", [Ptr, I32] => I32
Machine.import "inflateEnd", [Ptr] => I32
Machine.import "inflateReset", [Ptr] => I32
Machine.import "inflateSync", [Ptr] => I32
Machine.import "inflateSyncPoint", [Ptr] => I32
Machine.import "inflateSetDictionary", [Ptr, Ptr, I32] => I32
Machine.import "crc32_z", [Word, Ptr, Word] => Word
Machine.import "adler32_z", [Word, Ptr, Word] => Word
Machine.import "crc32_combine", [Word, Word, Word] => Word
Machine.import "adler32_combine", [Word, Word, Word] => Word
Machine.import "get_crc_table", [] => Ptr
Machine.import "zlibVersion", [] => Ptr
Machine.import "zError", [I32] => Ptr

# z_stream's fields, as zlib.h lays them out on a 64-bit host.
Z_NEXT_IN = 0
Z_AVAIL_IN = 8
Z_TOTAL_IN = 16
Z_NEXT_OUT = 24
Z_AVAIL_OUT = 32
Z_TOTAL_OUT = 40
Z_MSG = 48
Z_DATA_TYPE = 88
Z_ADLER = 96
Z_STREAM_SIZE = 112

# What zr_zlib_call runs.
ZLIB_DEFLATE = 0
ZLIB_INFLATE = 1
ZLIB_DEFLATE_END = 2
ZLIB_INFLATE_END = 3
ZLIB_DEFLATE_RESET = 4
ZLIB_INFLATE_RESET = 5
ZLIB_INFLATE_SYNC = 6
ZLIB_INFLATE_SYNC_POINT = 7

sig [Value] => Ptr
machine def zr_zlib_stream(addr)
  Machine.ptr(zr_fix2long(addr))
end

# A zeroed z_stream: zlib's own allocator, no input, no output.
sig [] => Value
machine def zr_zlib_new
  z = calloc(1, Z_STREAM_SIZE)
  if z == 0
    zr_memory_exhausted()
  end
  zr_fix(Machine.word(z))
end

# The stream's state ended, whatever it held, and its block freed.
sig [Value, Value] => Value
machine def zr_zlib_release(addr, kind)
  z = zr_zlib_stream(addr)
  if zr_fix2long(kind) == ZLIB_DEFLATE
    deflateEnd(z)
  else
    inflateEnd(z)
  end
  zr_xfree(z)
  Machine.value(QNIL)
end

# deflateInit2 for a deflate stream, inflateInit2 for an inflate one.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_zlib_init(addr, kind, level, wbits, memlevel, strategy)
  z = zr_zlib_stream(addr)
  version = Machine.bytes("1.3.1\0")
  if zr_fix2long(kind) == ZLIB_DEFLATE
    return zr_fix(Machine.sword(deflateInit2_(z, Machine.i32(zr_fix2long(level)), Machine.i32(8), Machine.i32(zr_fix2long(wbits)), Machine.i32(zr_fix2long(memlevel)), Machine.i32(zr_fix2long(strategy)), version, Machine.i32(Z_STREAM_SIZE))))
  end
  zr_fix(Machine.sword(inflateInit2_(z, Machine.i32(zr_fix2long(wbits)), version, Machine.i32(Z_STREAM_SIZE))))
end

# The input the next calls read: `str`'s bytes from `offset`, or none.
# The String must stay as it is until they are done.
sig [Value, Value, Value] => Value
machine def zr_zlib_input(addr, str, offset)
  z = zr_zlib_stream(addr)
  if str == QNIL
    Machine.store64(z, Z_NEXT_IN, Machine.word(Machine.bytes("\0")))
    Machine.store32(z, Z_AVAIL_IN, Machine.i32(0))
  else
    at = zr_fix2long(offset)
    Machine.store64(z, Z_NEXT_IN, Machine.word(RString.ptr(str) + at))
    Machine.store32(z, Z_AVAIL_IN, Machine.i32(RString.len(str) - at))
  end
  Machine.value(QNIL)
end

# The output a call writes: `room` bytes past the end of `buf`, which
# grows to hold them. A nil `buf` takes no output.
sig [Ptr, Value, Word] => Void
machine def zr_zlib_output(z, buf, room)
  if buf == QNIL
    Machine.store64(z, Z_NEXT_OUT, 0)
    Machine.store32(z, Z_AVAIL_OUT, Machine.i32(0))
    return
  end
  len = RString.len(buf)
  if len + room + 1 > RString.capa(buf)
    p = zr_xmalloc(len + room + 1)
    zr_memcpy(p, RString.ptr(buf), len)
    zr_xfree(RString.ptr(buf))
    RString.set_ptr(buf, p)
    RString.set_capa(buf, len + room + 1)
  end
  Machine.store64(z, Z_NEXT_OUT, Machine.word(RString.ptr(buf) + len))
  Machine.store32(z, Z_AVAIL_OUT, Machine.i32(room))
end

# What the call wrote, counted into `buf`'s length.
sig [Ptr, Value] => Void
machine def zr_zlib_output_taken(z, buf)
  if buf == QNIL
    return
  end
  len = Machine.ptr(Machine.load64(z, Z_NEXT_OUT)) - RString.ptr(buf)
  RString.set_len(buf, len)
  Machine.store8(RString.ptr(buf) + len, 0, Machine.i8(0))
  zr_str_modified(buf)
end

# One call of `op`, writing into `room` bytes past the end of `buf`.
# `flush` is the flush mode of deflate and inflate.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_zlib_call(addr, op, flush, buf, room)
  z = zr_zlib_stream(addr)
  o = zr_fix2long(op)
  f = Machine.i32(zr_fix2long(flush))
  zr_zlib_output(z, buf, zr_fix2long(room))
  err = 0
  if o == ZLIB_DEFLATE
    err = Machine.sword(deflate(z, f))
  elsif o == ZLIB_INFLATE
    err = Machine.sword(inflate(z, f))
  elsif o == ZLIB_DEFLATE_END
    err = Machine.sword(deflateEnd(z))
  elsif o == ZLIB_INFLATE_END
    err = Machine.sword(inflateEnd(z))
  elsif o == ZLIB_DEFLATE_RESET
    err = Machine.sword(deflateReset(z))
  elsif o == ZLIB_INFLATE_RESET
    err = Machine.sword(inflateReset(z))
  elsif o == ZLIB_INFLATE_SYNC
    err = Machine.sword(inflateSync(z))
  else
    err = Machine.sword(inflateSyncPoint(z))
  end
  zr_zlib_output_taken(z, buf)
  zr_fix(err)
end

# deflateParams, which may flush what the old parameters compressed.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_zlib_params(addr, level, strategy, buf, room)
  z = zr_zlib_stream(addr)
  zr_zlib_output(z, buf, zr_fix2long(room))
  err = Machine.sword(deflateParams(z, Machine.i32(zr_fix2long(level)), Machine.i32(zr_fix2long(strategy))))
  zr_zlib_output_taken(z, buf)
  zr_fix(err)
end

sig [Value, Value, Value] => Value
machine def zr_zlib_dictionary(addr, kind, dict)
  z = zr_zlib_stream(addr)
  if zr_fix2long(kind) == ZLIB_DEFLATE
    return zr_fix(Machine.sword(deflateSetDictionary(z, RString.ptr(dict), Machine.i32(RString.len(dict)))))
  end
  zr_fix(Machine.sword(inflateSetDictionary(z, RString.ptr(dict), Machine.i32(RString.len(dict)))))
end

sig [Value, Value] => Value
machine def zr_zlib_copy(dest, source)
  zr_fix(Machine.sword(deflateCopy(zr_zlib_stream(dest), zr_zlib_stream(source))))
end

# [avail_in, total_in, avail_out, total_out, data_type, adler, msg]
sig [Value] => Value
machine def zr_zlib_fields(addr)
  z = zr_zlib_stream(addr)
  out = zr_ary_new(7)
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(z, Z_AVAIL_IN))))
  zr_ary_push(out, zr_fix(Machine.load64(z, Z_TOTAL_IN)))
  zr_ary_push(out, zr_fix(Machine.word(Machine.load32(z, Z_AVAIL_OUT))))
  zr_ary_push(out, zr_fix(Machine.load64(z, Z_TOTAL_OUT)))
  zr_ary_push(out, zr_fix(Machine.sword(Machine.load32(z, Z_DATA_TYPE))))
  zr_ary_push(out, zr_fix(Machine.load64(z, Z_ADLER)))
  zr_ary_push(out, zr_cstr_str(Machine.ptr(Machine.load64(z, Z_MSG))))
  out
end

# total_in moved on by `n`, as a gzip footer read counts its bytes.
sig [Value, Value] => Value
machine def zr_zlib_count_in(addr, n)
  z = zr_zlib_stream(addr)
  Machine.store64(z, Z_TOTAL_IN, Machine.load64(z, Z_TOTAL_IN) + zr_fix2long(n))
  Machine.value(QNIL)
end

# crc32 (kind 0) or adler32 (kind 1) of `str` onto `sum`; a nil `str`
# answers the initial value.
sig [Value, Value, Value] => Value
machine def zr_zlib_checksum(kind, sum, str)
  s = zr_fix2long(sum)
  p = 0
  n = 0
  if str != QNIL
    p = RString.ptr(str)
    n = RString.len(str)
  end
  if zr_fix2long(kind) == 0
    return zr_fix(crc32_z(s, p, n))
  end
  zr_fix(adler32_z(s, p, n))
end

sig [Value, Value, Value, Value] => Value
machine def zr_zlib_combine(kind, first, second, len)
  if zr_fix2long(kind) == 0
    return zr_fix(crc32_combine(zr_fix2long(first), zr_fix2long(second), zr_fix2long(len)))
  end
  zr_fix(adler32_combine(zr_fix2long(first), zr_fix2long(second), zr_fix2long(len)))
end

# The CRC table's 256 entries, as the bytes of their 32-bit words.
sig [] => Value
machine def zr_zlib_crc_table
  zr_str_new(get_crc_table(), 1024)
end

sig [] => Value
machine def zr_zlib_version
  zr_cstr_str(zlibVersion())
end

sig [Value] => Value
machine def zr_zlib_message(err)
  zr_cstr_str(zError(Machine.i32(zr_fix2long(err))))
end
