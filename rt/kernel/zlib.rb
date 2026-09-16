# zlib, as the kernel's own port of it (rt/kernel/zlib_*.rb). A stream
# is a malloc'd ZStream the extension holds by its address, a Fixnum;
# each call here sets the fields one zlib call reads, makes it, and
# answers what it returned. The extension (rt/ext/zlib.rb) keeps the
# buffers, as zlib.c keeps them, and says how much room the output has.
#
# The port is derived from zlib 1.3.1, (C) 1995-2024 Jean-loup Gailly
# and Mark Adler, under the zlib license:
#
#   This software is provided 'as-is', without any express or implied
#   warranty. In no event will the authors be held liable for any damages
#   arising from the use of this software.
#
#   Permission is granted to anyone to use this software for any purpose,
#   including commercial applications, and to alter it and redistribute it
#   freely, subject to the following restrictions:
#
#   1. The origin of this software must not be misrepresented; you must not
#      claim that you wrote the original software. If you use this software
#      in a product, an acknowledgment in the product documentation would be
#      appreciated but is not required.
#   2. Altered source versions must be plainly marked as such, and must not be
#      misrepresented as being the original software.
#   3. This notice may not be removed or altered from any source distribution.
#
# The Ruby here is an altered version: the same algorithms, written in
# the kernel dialect. See THIRD_PARTY_NOTICES.md.

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

# A zeroed stream: no state, no input, no output.
sig [] => Value
machine def zr_zlib_new
  z = malloc(ZStream.size)
  if z == 0
    zr_memory_exhausted()
  end
  memset(z, Machine.i32(0), ZStream.size)
  zr_fix(Machine.word(z))
end

# The stream's state ended, whatever it held, and its block freed.
sig [Value, Value] => Value
machine def zr_zlib_release(addr, kind)
  z = zr_zlib_stream(addr)
  if zr_fix2long(kind) == ZLIB_DEFLATE
    zr_deflate_end(z)
  else
    zr_inflate_end(z)
  end
  zr_xfree(z)
  Machine.value(QNIL)
end

# deflateInit2 for a deflate stream, inflateInit2 for an inflate one.
sig [Value, Value, Value, Value, Value, Value] => Value
machine def zr_zlib_init(addr, kind, level, wbits, memlevel, strategy)
  z = zr_zlib_stream(addr)
  if zr_fix2long(kind) == ZLIB_DEFLATE
    return zr_fix(zr_deflate_init2(z, zr_fix2long(level), Z_DEFLATED, zr_fix2long(wbits), zr_fix2long(memlevel), zr_fix2long(strategy)))
  end
  zr_fix(zr_inflate_init2(z, zr_fix2long(wbits)))
end

# The input the next calls read: `str`'s bytes from `offset`, or none.
# The String must stay as it is until they are done.
sig [Value, Value, Value] => Value
machine def zr_zlib_input(addr, str, offset)
  z = zr_zlib_stream(addr)
  if str == QNIL
    ZStream.set_next_in(z, Machine.bytes("\0"))
    ZStream.set_avail_in(z, 0)
  else
    at = zr_fix2long(offset)
    ZStream.set_next_in(z, RString.ptr(str) + at)
    ZStream.set_avail_in(z, RString.len(str) - at)
  end
  Machine.value(QNIL)
end

# The output a call writes: `room` bytes past the end of `buf`, which
# grows to hold them. A nil `buf` takes no output.
sig [Ptr, Value, Word] => Void
machine def zr_zlib_output(z, buf, room)
  if buf == QNIL
    ZStream.set_next_out(z, 0)
    ZStream.set_avail_out(z, 0)
    return
  end
  len = RString.len(buf)
  zr_str_reserve(buf, len + room)
  ZStream.set_next_out(z, RString.ptr(buf) + len)
  ZStream.set_avail_out(z, room)
end

# What the call wrote, counted into `buf`'s length.
sig [Ptr, Value] => Void
machine def zr_zlib_output_taken(z, buf)
  if buf == QNIL
    return
  end
  len = ZStream.next_out(z) - RString.ptr(buf)
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
  f = zr_fix2long(flush)
  zr_zlib_output(z, buf, zr_fix2long(room))
  err = 0
  if o == ZLIB_DEFLATE
    err = zr_deflate(z, f)
  elsif o == ZLIB_INFLATE
    err = zr_inflate(z, f)
  elsif o == ZLIB_DEFLATE_END
    err = zr_deflate_end(z)
  elsif o == ZLIB_INFLATE_END
    err = zr_inflate_end(z)
  elsif o == ZLIB_DEFLATE_RESET
    err = zr_deflate_reset(z)
  elsif o == ZLIB_INFLATE_RESET
    err = zr_inflate_reset(z)
  elsif o == ZLIB_INFLATE_SYNC
    err = zr_inflate_sync(z)
  else
    err = zr_inflate_sync_point(z)
  end
  zr_zlib_output_taken(z, buf)
  zr_fix(err)
end

# deflateParams, which may flush what the old parameters compressed.
sig [Value, Value, Value, Value, Value] => Value
machine def zr_zlib_params(addr, level, strategy, buf, room)
  z = zr_zlib_stream(addr)
  zr_zlib_output(z, buf, zr_fix2long(room))
  err = zr_deflate_params(z, zr_fix2long(level), zr_fix2long(strategy))
  zr_zlib_output_taken(z, buf)
  zr_fix(err)
end

sig [Value, Value, Value] => Value
machine def zr_zlib_dictionary(addr, kind, dict)
  z = zr_zlib_stream(addr)
  if zr_fix2long(kind) == ZLIB_DEFLATE
    return zr_fix(zr_deflate_set_dictionary(z, RString.ptr(dict), RString.len(dict)))
  end
  zr_fix(zr_inflate_set_dictionary(z, RString.ptr(dict), RString.len(dict)))
end

sig [Value, Value] => Value
machine def zr_zlib_copy(dest, source)
  zr_fix(zr_deflate_copy(zr_zlib_stream(dest), zr_zlib_stream(source)))
end

# [avail_in, total_in, avail_out, total_out, data_type, adler, msg]
sig [Value] => Value
machine def zr_zlib_fields(addr)
  z = zr_zlib_stream(addr)
  out = zr_ary_new(7)
  zr_ary_push(out, zr_fix(ZStream.avail_in(z)))
  zr_ary_push(out, zr_fix(ZStream.total_in(z)))
  zr_ary_push(out, zr_fix(ZStream.avail_out(z)))
  zr_ary_push(out, zr_fix(ZStream.total_out(z)))
  zr_ary_push(out, zr_fix(ZStream.data_type(z)))
  zr_ary_push(out, zr_fix(ZStream.adler(z)))
  zr_ary_push(out, zr_cstr_str(ZStream.msg(z)))
  out
end

# total_in moved on by `n`, as a gzip footer read counts its bytes.
sig [Value, Value] => Value
machine def zr_zlib_count_in(addr, n)
  z = zr_zlib_stream(addr)
  ZStream.set_total_in(z, ZStream.total_in(z) + zr_fix2long(n))
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
    return zr_fix(zr_crc32(s, p, n))
  end
  zr_fix(zr_adler32(s, p, n))
end

sig [Value, Value, Value, Value] => Value
machine def zr_zlib_combine(kind, first, second, len)
  if zr_fix2long(kind) == 0
    return zr_fix(zr_crc32_combine(zr_fix2long(first), zr_fix2long(second), zr_fix2long(len)))
  end
  zr_fix(zr_adler32_combine(zr_fix2long(first), zr_fix2long(second), zr_fix2long(len)))
end

# The CRC table's 256 entries, as the bytes of their 32-bit words.
sig [] => Value
machine def zr_zlib_crc_table
  zr_str_new(zr_crc_table(), 1024)
end

sig [] => Value
machine def zr_zlib_version
  zr_cstr_str(zr_zlib_version_text())
end

sig [Value] => Value
machine def zr_zlib_message(err)
  zr_cstr_str(zr_zlib_error_text(zr_fix2long(err)))
end
