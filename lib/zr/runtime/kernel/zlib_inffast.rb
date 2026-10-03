# inffast.c: the decoding loop that inflate runs while at least 6 bytes
# of input and 258 bytes of output space remain. Thus no step checks for
# either limit. The bit buffer is a Ptr, which is the C unsigned long.
# Derived from zlib; the license is in lib/zr/runtime/kernel/zlib.rb.

module Zr::Kern
  # inflate_fast: decodes literals and matches from the stream's input to
  # its output, from the LEN state. It stops at an end of block, at an
  # error, or when the input or output space becomes low. `start` is the
  # output space at the start of inflate. It gives the position where the
  # output of this call starts.
  #: (ptr, word) -> void
  def zr_inflate_fast(strm, start)
    st = ZStream.state(strm)
    in_ = ZStream.next_in(strm)
    last = in_ + (ZStream.avail_in(strm) - 5)
    out = ZStream.next_out(strm)
    beg = out - (start - ZStream.avail_out(strm))
    end_ = out + (ZStream.avail_out(strm) - 257)
    wsize = InflateState.wsize(st)
    whave = InflateState.whave(st)
    wnext = InflateState.wnext(st)
    window = InflateState.window(st)
    hold = InflateState.hold(st)
    bits = InflateState.bits(st)
    lcode = InflateState.lencode(st)
    dcode = InflateState.distcode(st)
    lmask = (1 << InflateState.lenbits(st)) - 1
    dmask = (1 << InflateState.distbits(st)) - 1
    done = 0
    while true
      if bits < 15
        hold += Machine.ptr(zr_zlib_byte(in_)) << bits
        in_ += 1
        bits += 8
        hold += Machine.ptr(zr_zlib_byte(in_)) << bits
        in_ += 1
        bits += 8
      end
      here = zr_zlib_u32(lcode, Machine.word(hold & lmask))
      while true
        op = zr_inf_code_bits(here)
        hold = hold >> op
        bits -= op
        op = zr_inf_code_op(here)
        if op == 0
          Machine.store8(out, 0, Machine.i8(zr_inf_code_val(here)))
          out += 1
          break
        elsif (op & 16) != 0
          len = zr_inf_code_val(here)
          op = op & 15
          if op != 0
            if bits < op
              hold += Machine.ptr(zr_zlib_byte(in_)) << bits
              in_ += 1
              bits += 8
            end
            len += Machine.word(hold & ((1 << op) - 1))
            hold = hold >> op
            bits -= op
          end
          if bits < 15
            hold += Machine.ptr(zr_zlib_byte(in_)) << bits
            in_ += 1
            bits += 8
            hold += Machine.ptr(zr_zlib_byte(in_)) << bits
            in_ += 1
            bits += 8
          end
          here = zr_zlib_u32(dcode, Machine.word(hold & dmask))
          while true
            op = zr_inf_code_bits(here)
            hold = hold >> op
            bits -= op
            op = zr_inf_code_op(here)
            if (op & 16) != 0
              dist = zr_inf_code_val(here)
              op = op & 15
              if bits < op
                hold += Machine.ptr(zr_zlib_byte(in_)) << bits
                in_ += 1
                bits += 8
                if bits < op
                  hold += Machine.ptr(zr_zlib_byte(in_)) << bits
                  in_ += 1
                  bits += 8
                end
              end
              dist += Machine.word(hold & ((1 << op) - 1))
              hold = hold >> op
              bits -= op
              op = out - beg
              if dist > op
                op = dist - op
                if op > whave
                  ZStream.set_msg(strm, Machine.bytes("invalid distance too far back\0"))
                  InflateState.set_mode(st, INF_BAD)
                  done = 1
                  break
                end
                from = window
                if wnext == 0
                  from += wsize - op
                  if op < len
                    len -= op
                    zr_zlib_copy_bytes(out, from, op)
                    out += op
                    from = out - dist
                  end
                elsif wnext < op
                  from += wsize + wnext - op
                  op -= wnext
                  if op < len
                    len -= op
                    zr_zlib_copy_bytes(out, from, op)
                    out += op
                    from = window
                    if wnext < len
                      op = wnext
                      len -= op
                      zr_zlib_copy_bytes(out, from, op)
                      out += op
                      from = out - dist
                    end
                  end
                else
                  from += wnext - op
                  if op < len
                    len -= op
                    zr_zlib_copy_bytes(out, from, op)
                    out += op
                    from = out - dist
                  end
                end
                zr_zlib_copy_bytes(out, from, len)
                out += len
              else
                from = out - dist
                zr_zlib_copy_bytes(out, from, len)
                out += len
              end
              break
            elsif (op & 64) == 0
              here = zr_zlib_u32(dcode, zr_inf_code_val(here) + Machine.word(hold & ((1 << op) - 1)))
            else
              ZStream.set_msg(strm, Machine.bytes("invalid distance code\0"))
              InflateState.set_mode(st, INF_BAD)
              done = 1
              break
            end
          end
          break
        elsif (op & 64) == 0
          here = zr_zlib_u32(lcode, zr_inf_code_val(here) + Machine.word(hold & ((1 << op) - 1)))
        elsif (op & 32) != 0
          InflateState.set_mode(st, INF_TYPE)
          done = 1
          break
        else
          ZStream.set_msg(strm, Machine.bytes("invalid literal/length code\0"))
          InflateState.set_mode(st, INF_BAD)
          done = 1
          break
        end
      end
      if done != 0
        break
      end
      if in_ >= last || out >= end_
        break
      end
    end
    len = bits >> 3
    in_ -= len
    bits -= len << 3
    hold = hold & ((1 << bits) - 1)
    ZStream.set_next_in(strm, in_)
    ZStream.set_next_out(strm, out)
    if in_ < last
      ZStream.set_avail_in(strm, 5 + (last - in_))
    else
      ZStream.set_avail_in(strm, 5 - (in_ - last))
    end
    if out < end_
      ZStream.set_avail_out(strm, 257 + (end_ - out))
    else
      ZStream.set_avail_out(strm, 257 - (out - end_))
    end
    InflateState.set_hold(st, hold)
    InflateState.set_bits(st, bits)
  end
end
