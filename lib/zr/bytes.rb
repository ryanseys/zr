# frozen_string_literal: true

module Zr
  # Byte-level arithmetic and encoding that every object writer and backend
  # needs: alignment, padding to a size, and LEB128 numbers. Each was its
  # own private copy in `Obj::Patch`, the ELF and Mach-O writers, the
  # aarch64 and wasm backends, the tests' IR interpreter and
  # `Machine::Lower`. This is the one copy.
  module Bytes
    module_function

    # The first multiple of `a` at or after `n`. `a` is a power of two.
    #: (Integer n, Integer a) -> Integer
    def align(n, a) = (n + a - 1) & ~(a - 1)

    # Appends zero bytes to `bytes` until it is `to` bytes long. Returns
    # `bytes`. Does nothing if `bytes` is already that long or longer.
    #: (String bytes, Integer to) -> String
    def pad(bytes, to)
      bytes << ("\0".b * (to - bytes.bytesize)) if to > bytes.bytesize
      bytes
    end

    # Appends zero bytes to `bytes` until its size is a multiple of `a`, a
    # power of two. Returns `bytes`.
    #: (String bytes, Integer a) -> String
    def pad_align(bytes, a) = pad(bytes, align(bytes.bytesize, a))

    # `n` as ULEB128: 7 bits per byte, low bits first, the high bit of a
    # byte set on every byte but the last.
    #: (Integer n) -> String
    def uleb(n)
      out = +"".b
      loop do
        byte = n & 0x7F
        n >>= 7
        if n.zero?
          out << byte.chr
          return out
        end
        out << (byte | 0x80).chr
      end
    end

    # WASM's own name for `uleb`, at the many call sites in
    # `Backend::Wasm::Codegen` that already read as "leb".
    #: (Integer n) -> String
    def leb(n) = uleb(n)

    # The number of bytes that `uleb(n)` returns, without building them.
    #: (Integer n) -> Integer
    def uleb_size(n) = n.zero? ? 1 : (n.bit_length + 6) / 7

    # `n` mapped to a non-negative integer so that a number near zero stays
    # small: 0, -1, 1, -2 become 0, 1, 2, 3. `uleb` then writes it.
    #: (Integer n) -> Integer
    def zigzag(n) = n >= 0 ? n * 2 : (-n * 2) - 1

    # `n` as SLEB128: like `uleb`, but the last byte carries the sign, so a
    # negative number also terminates.
    #: (Integer n) -> String
    def sleb(n)
      out = +"".b
      loop do
        byte = n & 0x7F
        n >>= 7
        done = (n.zero? && (byte & 0x40).zero?) || (n == -1 && (byte & 0x40) != 0)
        out << (done ? byte : byte | 0x80).chr
        return out if done
      end
    end
  end
end
