# Derived from zlib 1.3.1 (Zlib); see THIRD_PARTY_NOTICES.md.
#
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
    st = ZStream[strm].state
    in_ = ZStream[strm].next_in
    last = in_ + (ZStream[strm].avail_in - 5)
    out = ZStream[strm].next_out
    beg = out - (start - ZStream[strm].avail_out)
    end_ = out + (ZStream[strm].avail_out - 257)
    wsize = InflateState[st].wsize
    whave = InflateState[st].whave
    wnext = InflateState[st].wnext
    window = InflateState[st].window
    hold = InflateState[st].hold
    bits = InflateState[st].bits
    lcode = InflateState[st].lencode
    dcode = InflateState[st].distcode
    lmask = (1 << InflateState[st].lenbits) - 1
    dmask = (1 << InflateState[st].distbits) - 1
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
                  ZStream[strm].msg = Machine.bytes("invalid distance too far back\0")
                  InflateState[st].mode = INF_BAD
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
              ZStream[strm].msg = Machine.bytes("invalid distance code\0")
              InflateState[st].mode = INF_BAD
              done = 1
              break
            end
          end
          break
        elsif (op & 64) == 0
          here = zr_zlib_u32(lcode, zr_inf_code_val(here) + Machine.word(hold & ((1 << op) - 1)))
        elsif (op & 32) != 0
          InflateState[st].mode = INF_TYPE
          done = 1
          break
        else
          ZStream[strm].msg = Machine.bytes("invalid literal/length code\0")
          InflateState[st].mode = INF_BAD
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
    ZStream[strm].next_in = in_
    ZStream[strm].next_out = out
    if in_ < last
      ZStream[strm].avail_in = 5 + (last - in_)
    else
      ZStream[strm].avail_in = 5 - (in_ - last)
    end
    if out < end_
      ZStream[strm].avail_out = 257 + (end_ - out)
    else
      ZStream[strm].avail_out = 257 - (out - end_)
    end
    InflateState[st].hold = hold
    InflateState[st].bits = bits
  end
end
