# frozen_string_literal: true

# Derived from the C half of ruby's openssl gem (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# ossl_bn.c: OpenSSL::BN over OpenSSL's BIGNUM.
module OpenSSL
  Lib.attach_all(
    BN_new: [[], :pointer],
    BN_clear_free: [%i[pointer], :void],
    BN_free: [%i[pointer], :void],
    BN_dup: [%i[pointer], :pointer],
    BN_copy: [%i[pointer pointer], :pointer],
    BN_CTX_new: [[], :pointer],
    BN_bin2bn: [%i[buffer int pointer], :pointer],
    BN_bn2bin: [%i[pointer buffer], :int],
    BN_mpi2bn: [%i[buffer int pointer], :pointer],
    BN_bn2mpi: [%i[pointer buffer], :int],
    BN_dec2bn: [%i[buffer string], :int],
    BN_hex2bn: [%i[buffer string], :int],
    BN_bn2dec: [%i[pointer], :pointer],
    BN_bn2hex: [%i[pointer], :pointer],
    BN_set_negative: [%i[pointer int], :void],
    BN_is_negative: [%i[pointer], :int],
    BN_is_zero: [%i[pointer], :int],
    BN_is_one: [%i[pointer], :int],
    BN_is_odd: [%i[pointer], :int],
    BN_num_bits: [%i[pointer], :int],
    BN_sqr: [%i[pointer pointer pointer], :int],
    BN_add: [%i[pointer pointer pointer], :int],
    BN_sub: [%i[pointer pointer pointer], :int],
    BN_mul: [%i[pointer pointer pointer pointer], :int],
    BN_div: [%i[pointer pointer pointer pointer pointer], :int],
    BN_exp: [%i[pointer pointer pointer pointer], :int],
    BN_gcd: [%i[pointer pointer pointer pointer], :int],
    BN_mod_sqr: [%i[pointer pointer pointer pointer], :int],
    BN_mod_sqrt: [%i[pointer pointer pointer pointer], :pointer],
    BN_mod_inverse: [%i[pointer pointer pointer pointer], :pointer],
    BN_mod_add: [%i[pointer pointer pointer pointer pointer], :int],
    BN_mod_sub: [%i[pointer pointer pointer pointer pointer], :int],
    BN_mod_mul: [%i[pointer pointer pointer pointer pointer], :int],
    BN_mod_exp: [%i[pointer pointer pointer pointer pointer], :int],
    BN_set_bit: [%i[pointer int], :int],
    BN_clear_bit: [%i[pointer int], :int],
    BN_mask_bits: [%i[pointer int], :int],
    BN_is_bit_set: [%i[pointer int], :int],
    BN_lshift: [%i[pointer pointer int], :int],
    BN_rshift: [%i[pointer pointer int], :int],
    BN_rand: [%i[pointer int int int], :int],
    BN_rand_range: [%i[pointer pointer], :int],
    BN_generate_prime_ex: [%i[pointer int int pointer pointer pointer], :int],
    BN_check_prime: [%i[pointer pointer pointer], :int],
    BN_cmp: [%i[pointer pointer], :int],
    BN_ucmp: [%i[pointer pointer], :int],
    BN_get_flags: [%i[pointer int], :int],
    BN_set_flags: [%i[pointer int], :void]
  )

  module Lib
    # BN_num_bytes (bn.h).
    def self.BN_num_bytes(bn) = (BN_num_bits(bn) + 7) / 8

    # BN_mod (bn.h).
    def self.BN_mod(rem, m, d, ctx) = BN_div(nil, rem, m, d, ctx)
  end

  class BNError < OpenSSLError; end

  class BN; end

  module Ossl
    BIGNUM = DataType.new("OpenSSL/BN", OpenSSL::BN, :BN_clear_free, [RuntimeError, "BN wasn't initialized!"], alloc: -> { Ossl.new_bignum }, shareable: true)

    class << self
      # ossl_bn_ctx_get: the BN_CTX every operation borrows, made once
      # for each Ractor, as ossl keeps it in Ractor-local storage.
      def bn_ctx
        ractor = Ractor.current
        Native.hidden_get(ractor, :ossl_bn_ctx) || Lib.BN_CTX_new.tap do |ctx|
          raise RuntimeError, "Cannot init BN_CTX" if ctx.zero?

          Native.hidden_set(ractor, :ossl_bn_ctx, ctx)
        end
      end

      # GetBN.
      def bn_of(object) = BIGNUM.fetch(object)

      def new_bignum
        bn = Lib.BN_new
        raise error(BNError) if bn.zero?

        bn
      end

      # ossl_bn_new: a BN holding a copy of `bn`.
      def bn_new(bn)
        copy = Lib.BN_dup(bn)
        raise error(BNError, "BN_dup") if copy.zero?

        BIGNUM.wrap(OpenSSL::BN, copy)
      end

      # try_convert_to_bn: `object` as a BN, or nil.
      def try_bn(object)
        return object if object.is_a?(OpenSSL::BN)
        return nil unless object.is_a?(Integer)

        bn = Native.allocate(OpenSSL::BN)
        BIGNUM.set(bn, integer_to_bignum(object, nil))
        bn
      end

      # GetBNPtr: `object` as a BN, whose BIGNUM the caller reads while it
      # keeps a reference to the object.
      def to_bn(object)
        try_bn(object) || raise(error(TypeError, "Cannot convert into OpenSSL::BN"))
      end

      # integer_to_bnptr: `integer`'s magnitude and sign into `orig`, or
      # into a new BIGNUM for nil.
      def integer_to_bignum(integer, orig)
        magnitude = integer.abs
        hex = magnitude.to_s(16)
        hex = "0#{hex}" if hex.size.odd?
        raise BNError, "bignum too long" if hex.size / 2 > 0x7fff_ffff

        bytes = [hex].pack("H*")
        bn = Lib.BN_bin2bn(bytes, bytes.bytesize, orig)
        raise error(BNError, "BN_bin2bn") if bn.zero?

        Lib.BN_set_negative(bn, 1) if integer.negative?
        bn
      end

      # A BN of `klass` that owns `result`, made by `yield` into a new
      # BIGNUM, which is freed when `yield` fails.
      def bn_result(klass)
        result = new_bignum
        unless yield(result)
          Lib.BN_free(result)
          raise error(BNError)
        end
        BIGNUM.wrap(klass, result)
      end

      # The text OpenSSL allocated at `address`, freed once read.
      def take_text(address)
        raise error(BNError) if address.zero?

        Lib.string(address)
      ensure
        Lib.OPENSSL_free(address) unless address.zero?
      end
    end
  end

  class BN
    def initialize(str, base = (default = true; 10))
      base = Ossl.int(base) unless default
      raise Ossl.error(ArgumentError, "invalid argument") if str.nil?

      Ossl.check_frozen(self)
      bn = Ossl.bn_of(self)
      if str.is_a?(Integer)
        Ossl.integer_to_bignum(str, bn)
        return self
      end
      if str.is_a?(BN)
        raise Ossl.error(BNError) if Lib.BN_copy(bn, Ossl.bn_of(str)).zero?

        return self
      end

      case base
      when 0
        str = Ossl.string_value(str)
        raise Ossl.error(BNError) if Lib.BN_mpi2bn(str, str.bytesize, bn).zero?
      when 2
        str = Ossl.string_value(str)
        raise Ossl.error(BNError) if Lib.BN_bin2bn(str, str.bytesize, bn).zero?
      when 10
        raise Ossl.error(BNError) if Lib.BN_dec2bn([bn].pack("J"), Ossl.cstring_value(str)).zero?
      when 16
        raise Ossl.error(BNError) if Lib.BN_hex2bn([bn].pack("J"), Ossl.cstring_value(str)).zero?
      else
        raise Ossl.error(ArgumentError, "invalid radix #{base}")
      end
      self
    end

    def initialize_copy(other)
      Ossl.check_frozen(self)
      return self if equal?(other)

      Ossl::BIGNUM.unshare(self, other)
      other = Ossl.to_bn(other)
      raise Ossl.error(BNError) if Lib.BN_copy(Ossl.bn_of(self), Ossl.bn_of(other)).zero?

      self
    end
    alias copy initialize_copy
    public :copy

    def to_s(base = 10)
      base = Ossl.int(base)
      bn = Ossl.bn_of(self)
      case base
      when 0
        length = Lib.BN_bn2mpi(bn, nil)
        out = Lib.buffer(length)
        raise Ossl.error(BNError) if Lib.BN_bn2mpi(bn, out) != length

        out
      when 2
        length = Lib.BN_num_bytes(bn)
        out = Lib.buffer(length)
        raise Ossl.error(BNError) if Lib.BN_bn2bin(bn, out) != length

        out
      when 10 then Ossl.take_text(Lib.BN_bn2dec(bn))
      when 16 then Ossl.take_text(Lib.BN_bn2hex(bn))
      else raise Ossl.error(ArgumentError, "invalid radix #{base}")
      end
    end

    def to_i = Integer(Ossl.take_text(Lib.BN_bn2hex(Ossl.bn_of(self))), 16)
    alias to_int to_i

    def to_bn = self

    def coerce(other)
      case other
      when String then [other, to_s]
      when Integer then [other, to_i]
      else
        raise Ossl.error(TypeError, "Don't know how to coerce") unless other.is_a?(BN)

        [other, self]
      end
    end

    def zero? = Lib.BN_is_zero(Ossl.bn_of(self)) != 0

    def one? = Lib.BN_is_one(Ossl.bn_of(self)) != 0

    def odd? = Lib.BN_is_odd(Ossl.bn_of(self)) != 0

    def negative?
      bn = Ossl.bn_of(self)
      Lib.BN_is_zero(bn).zero? && Lib.BN_is_negative(bn) != 0
    end

    def sqr
      bn = Ossl.bn_of(self)
      Ossl.bn_result(self.class) { |r| Lib.BN_sqr(r, bn, Ossl.bn_ctx) > 0 }
    end

    def +(other) = binary(other) { |r, a, b| Lib.BN_add(r, a, b) }

    def -(other) = binary(other) { |r, a, b| Lib.BN_sub(r, a, b) }

    def *(other) = binary(other) { |r, a, b| Lib.BN_mul(r, a, b, Ossl.bn_ctx) }

    def %(other) = binary(other) { |r, a, b| Lib.BN_mod(r, a, b, Ossl.bn_ctx) }

    def **(other) = binary(other) { |r, a, b| Lib.BN_exp(r, a, b, Ossl.bn_ctx) }

    def gcd(other) = binary(other) { |r, a, b| Lib.BN_gcd(r, a, b, Ossl.bn_ctx) }

    def mod_sqr(other) = binary(other) { |r, a, b| Lib.BN_mod_sqr(r, a, b, Ossl.bn_ctx) }

    def mod_sqrt(other) = returning(other) { |a, b| Lib.BN_mod_sqrt(nil, a, b, Ossl.bn_ctx) }

    def mod_inverse(other) = returning(other) { |a, b| Lib.BN_mod_inverse(nil, a, b, Ossl.bn_ctx) }

    def /(other)
      other = Ossl.to_bn(other)
      a = Ossl.bn_of(self)
      b = Ossl.bn_of(other)
      quotient = Ossl.new_bignum
      remainder = Lib.BN_new
      if remainder.zero?
        Lib.BN_free(quotient)
        raise Ossl.error(BNError)
      end
      if Lib.BN_div(quotient, remainder, a, b, Ossl.bn_ctx).zero?
        Lib.BN_free(quotient)
        Lib.BN_free(remainder)
        raise Ossl.error(BNError)
      end
      [Ossl::BIGNUM.wrap(self.class, quotient), Ossl::BIGNUM.wrap(self.class, remainder)]
    end

    def mod_add(other1, other2) = ternary(other1, other2) { |r, a, b, m| Lib.BN_mod_add(r, a, b, m, Ossl.bn_ctx) }

    def mod_sub(other1, other2) = ternary(other1, other2) { |r, a, b, m| Lib.BN_mod_sub(r, a, b, m, Ossl.bn_ctx) }

    def mod_mul(other1, other2) = ternary(other1, other2) { |r, a, b, m| Lib.BN_mod_mul(r, a, b, m, Ossl.bn_ctx) }

    def mod_exp(other1, other2) = ternary(other1, other2) { |r, a, b, m| Lib.BN_mod_exp(r, a, b, m, Ossl.bn_ctx) }

    def set_bit!(bit) = bit_operation(bit) { |bn, n| Lib.BN_set_bit(bn, n) }

    def clear_bit!(bit) = bit_operation(bit) { |bn, n| Lib.BN_clear_bit(bn, n) }

    def mask_bits!(bit) = bit_operation(bit) { |bn, n| Lib.BN_mask_bits(bn, n) }

    def bit_set?(bit)
      bit = Ossl.int(bit)
      Lib.BN_is_bit_set(Ossl.bn_of(self), bit) != 0
    end

    def <<(bits) = shift(bits) { |r, a, n| Lib.BN_lshift(r, a, n) }

    def >>(bits) = shift(bits) { |r, a, n| Lib.BN_rshift(r, a, n) }

    def lshift!(bits) = self_shift(bits) { |bn, n| Lib.BN_lshift(bn, bn, n) }

    def rshift!(bits) = self_shift(bits) { |bn, n| Lib.BN_rshift(bn, bn, n) }

    def self.rand(bits, *rest)
      raise ArgumentError, wrong_arity(rest.size + 1, 1..3) if rest.size > 2

      fill, odd = rest
      bottom = rest.size == 2 && odd ? 1 : 0
      top = rest.empty? ? 0 : Ossl.int(fill)
      bits = Ossl.int(bits)
      result = Lib.BN_new
      raise Ossl.error(BNError, "BN_new") if result.zero?

      if Lib.BN_rand(result, bits, top, bottom) <= 0
        Lib.BN_free(result)
        raise Ossl.error(BNError, "BN_rand")
      end
      Ossl::BIGNUM.wrap(self, result)
    end

    def self.rand_range(range)
      range = Ossl.to_bn(range)
      bn = Ossl.bn_of(range)
      result = Lib.BN_new
      raise Ossl.error(BNError, "BN_new") if result.zero?

      if Lib.BN_rand_range(result, bn) <= 0
        Lib.BN_free(result)
        raise Ossl.error(BNError, "BN_rand_range")
      end
      Ossl::BIGNUM.wrap(self, result)
    end

    singleton_class.alias_method :pseudo_rand, :rand
    singleton_class.alias_method :pseudo_rand_range, :rand_range

    def self.generate_prime(num, safe = true, add = nil, rem = nil)
      num = Ossl.int(num)
      unless add.nil?
        add = Ossl.to_bn(add)
        rem = Ossl.to_bn(rem) unless rem.nil?
      end
      add_bn = add && Ossl.bn_of(add)
      rem_bn = rem && Ossl.bn_of(rem)
      Ossl.bn_result(self) { |r| Lib.BN_generate_prime_ex(r, num, safe == false ? 0 : 1, add_bn, rem_bn, nil) != 0 }
    end

    def num_bytes = Lib.BN_num_bytes(Ossl.bn_of(self))

    def num_bits = Lib.BN_num_bits(Ossl.bn_of(self))

    def +@ = Ossl.bn_new(Ossl.bn_of(self))

    def -@
      copy = +self
      bn = Ossl.bn_of(copy)
      Lib.BN_set_negative(bn, Lib.BN_is_negative(bn).zero? ? 1 : 0)
      copy
    end

    def abs = Lib.BN_is_negative(Ossl.bn_of(self)).zero? ? +self : -self

    def cmp(other)
      other = Ossl.to_bn(other)
      Lib.BN_cmp(Ossl.bn_of(self), Ossl.bn_of(other))
    end
    alias <=> cmp

    def ucmp(other)
      other = Ossl.to_bn(other)
      Lib.BN_ucmp(Ossl.bn_of(self), Ossl.bn_of(other))
    end

    def eql?(other)
      return false unless other.is_a?(BN)

      Lib.BN_cmp(Ossl.bn_of(self), Ossl.bn_of(other)).zero?
    end

    def hash = to_s(2).hash

    def ==(other)
      bn = Ossl.bn_of(self)
      other = Ossl.try_bn(other)
      return false if other.nil?

      Lib.BN_cmp(bn, Ossl.bn_of(other)).zero?
    end
    alias === ==

    def prime?(*checks)
      raise ArgumentError, wrong_arity(checks.size, 0..1) if checks.size > 1

      answer = Lib.BN_check_prime(Ossl.bn_of(self), Ossl.bn_ctx, nil)
      raise Ossl.error(BNError, "BN_check_prime") if answer.negative?

      answer != 0
    end

    def prime_fasttest?(*args)
      raise ArgumentError, wrong_arity(args.size, 0..2) if args.size > 2

      prime?
    end

    def get_flags(flags) = Lib.BN_get_flags(Ossl.bn_of(self), Ossl.int(flags))

    def set_flags(flags)
      bn = Ossl.bn_of(self)
      Ossl.check_frozen(self)
      Lib.BN_set_flags(bn, Ossl.int(flags))
      nil
    end

    private

    # BIGNUM_2 and BIGNUM_2c: an operation of this BN and another into a
    # new BN of this one's class.
    def binary(other)
      other = Ossl.to_bn(other)
      a = Ossl.bn_of(self)
      b = Ossl.bn_of(other)
      Ossl.bn_result(self.class) { |r| yield(r, a, b) > 0 }
    end

    # BIGNUM_2cr: an operation that returns a new BIGNUM itself.
    def returning(other)
      other = Ossl.to_bn(other)
      a = Ossl.bn_of(self)
      result = yield(a, Ossl.bn_of(other))
      raise Ossl.error(BNError) if result.zero?

      Ossl::BIGNUM.wrap(self.class, result)
    end

    # BIGNUM_3c.
    def ternary(other1, other2)
      other1 = Ossl.to_bn(other1)
      other2 = Ossl.to_bn(other2)
      a = Ossl.bn_of(self)
      b = Ossl.bn_of(other1)
      m = Ossl.bn_of(other2)
      Ossl.bn_result(self.class) { |r| yield(r, a, b, m) > 0 }
    end

    # BIGNUM_BIT.
    def bit_operation(bit)
      Ossl.check_frozen(self)
      bn = Ossl.bn_of(self)
      raise Ossl.error(BNError) if yield(bn, Ossl.int(bit)) <= 0

      self
    end

    # BIGNUM_SHIFT.
    def shift(bits)
      bits = Ossl.int(bits)
      a = Ossl.bn_of(self)
      Ossl.bn_result(self.class) { |r| yield(r, a, bits) > 0 }
    end

    # BIGNUM_SELF_SHIFT.
    def self_shift(bits)
      Ossl.check_frozen(self)
      bits = Ossl.int(bits)
      raise Ossl.error(BNError) if yield(Ossl.bn_of(self), bits) <= 0

      self
    end
  end
end
