# Random: CRuby's MT19937, seeded and drawn as CRuby does it, so a
# seeded stream answers the same numbers. Floats are not drawn yet.
random_base = Class.new

class Random < random_base
  N = 624
  M = 397
  MATRIX_A = 0x9908b0df
  UPPER = 0x80000000
  LOWER = 0x7fffffff
  private_constant :N, :M, :MATRIX_A, :UPPER, :LOWER

  attr_reader :seed

  def initialize(seed = Random.new_seed)
    seed = seed.to_i if seed.is_a?(Float)
    raise TypeError, "no implicit conversion of #{seed.class} into Integer" unless seed.is_a?(Integer)

    @seed = seed
    key = []
    v = seed.abs
    while v > 0
      key << (v & 0xffffffff)
      v >>= 32
    end
    # CRuby decides by the words the seed packs into: one or none seed
    # init_genrand, more seed init_by_array, less a top word of one, its
    # packer's leading-zero guard.
    words = key.size
    key.pop if words > 1 && key.last == 1
    words <= 1 ? init_genrand(key[0] || 0) : init_by_array(key)
  end

  def self.new_seed = Primitive.zr_random_seed

  def self.default
    Primitive.attr! :hidden
    @default ||= new
  end

  def self.rand(max = nil) = default.rand(max)
  def self.bytes(size) = default.bytes(size)

  # Bytes from the system's own source, not the seeded stream.
  def self.urandom(size)
    raise ArgumentError, "negative string size (or size too big)" if size < 0

    out = "".b
    out << (Primitive.zr_random_seed & 0xff) while out.bytesize < size
    out
  end

  def self.random_number(max = nil) = default.rand(max)
  def self.seed = default.seed

  def self.srand(seed = new_seed)
    was = default.seed
    @default = new(seed)
    was
  end

  # `rand(n)`, `rand(a..b)`; a Float bound or no bound is a Float draw.
  def rand(max = nil)
    case max
    when nil then unit_float
    when Integer
      raise ArgumentError, "invalid argument - #{max}" if max <= 0

      limited(max - 1)
    when Range
      low = max.begin
      high = max.end
      raise Errno::EDOM if low.nil? || high.nil?
      if low.is_a?(Float) || high.is_a?(Float)
        span = high.to_f - low.to_f
        return wide_float(low.to_f, high.to_f, max.exclude_end?) if span.infinite?
        raise ArgumentError, "invalid argument - #{max}" if span < 0 || (span == 0 && max.exclude_end?)
        return low.to_f + span * unit_float if max.exclude_end?

        return low.to_f + span * unit_float_closed
      end

      high -= 1 if max.exclude_end?
      raise ArgumentError, "invalid argument - #{max}" if high < low

      low + limited(high - low)
    when Float
      raise Errno::EDOM unless max.finite?
      raise ArgumentError, "invalid argument - #{max}" if max.negative?

      max.zero? ? unit_float : max * unit_float
    else
      raise ArgumentError, "invalid argument - #{max.inspect}"
    end
  end

  # A span too wide for a Float draws around the middle instead, which
  # is how ruby keeps `-1e308..1e308` working. An endpoint that is not
  # finite has no middle.
  def wide_float(low, high, exclude_end)
    raise Errno::EDOM unless low.finite? && high.finite?

    half = (high / 2.0) - (low / 2.0)
    mid = (high / 2.0) + (low / 2.0)
    (((exclude_end ? unit_float : unit_float_closed) - 0.5) * half * 2) + mid
  end

  # `n` random bytes, four per draw, least significant first.
  def bytes(size)
    raise ArgumentError, "negative string size (or size too big)" if size < 0

    out = "".b
    while size >= 4
      x = next_int32
      4.times do
        out << (x & 0xff)
        x >>= 8
      end
      size -= 4
    end
    if size > 0
      x = next_int32
      size.times do
        out << (x & 0xff)
        x >>= 8
      end
    end
    out
  end

  # A double in [0, 1) from 53 random bits, as MT's genrand_res53.
  def unit_float
    Primitive.attr! :hidden
    a = next_int32 >> 5
    b = next_int32 >> 6
    (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)
  end

  # A double in [0, 1] as CRuby's int_pair_to_real_inclusive: the 64
  # random bits scaled by 2**53 + 1 and the high word kept.
  def unit_float_closed
    Primitive.attr! :hidden
    a = next_int32
    b = next_int32
    high = (a << 21) | (b >> 11)
    low = b & 0x7FF
    high += 1 if (a >> 21) >= 2048 - low
    high / 9007199254740992.0
  end

  # A draw in 0..limit, by rejection from as many 32-bit words as the
  # limit spans.
  def limited(limit)
    Primitive.attr! :hidden
    return 0 if limit == 0
    return big_limited(limit) if limit > 0xffff_ffff_ffff_ffff

    mask = limit
    mask |= mask >> 1
    mask |= mask >> 2
    mask |= mask >> 4
    mask |= mask >> 8
    mask |= mask >> 16
    mask |= mask >> 32
    while true
      val = 0
      retry_draw = false
      i = 1
      while i >= 0
        part = (mask >> (i * 32)) & 0xffffffff
        if part != 0
          val |= (next_int32 & part) << (i * 32)
          if limit < val
            retry_draw = true
            i = -1
          end
        end
        i -= 1
      end
      return val unless retry_draw
    end
  end

  # A draw in 0..limit past 64 bits, as CRuby's limited_big_rand makes
  # it: one word at a time from the top, redrawn while the words drawn
  # still sit on the limit's own, taken once one falls below.
  def big_limited(limit)
    Primitive.attr! :hidden
    words = []
    v = limit
    while v > 0
      words << (v & 0xffffffff)
      v >>= 32
    end
    while true
      mask = 0
      boundary = true
      val = 0
      again = false
      i = words.size - 1
      while i >= 0
        top = words[i]
        if mask.zero?
          mask = top
          mask |= mask >> 1
          mask |= mask >> 2
          mask |= mask >> 4
          mask |= mask >> 8
          mask |= mask >> 16
        else
          mask = 0xffffffff
        end
        if mask != 0
          r = next_int32 & mask
          if boundary
            if top < r
              again = true
              break
            end
            boundary = false if r < top
          end
          val |= r << (32 * i)
        end
        i -= 1
      end
      return val unless again
    end
  end

  def ==(other) = other.is_a?(Random) && @seed == other.seed && @mti == other.send(:mti) && @mt == other.send(:mt)

  # The state is hidden, as CRuby's is.
  def inspect = to_s

  private

  attr_reader :mt, :mti

  def init_genrand(s)
    @mt = Array.new(N, 0)
    @mt[0] = s & 0xffffffff
    i = 1
    while i < N
      prev = @mt[i - 1]
      @mt[i] = (mul32(1812433253, prev ^ (prev >> 30)) + i) & 0xffffffff
      i += 1
    end
    @mti = N
  end

  def init_by_array(key)
    init_genrand(19650218)
    i = 1
    j = 0
    k = N > key.size ? N : key.size
    while k > 0
      prev = @mt[i - 1]
      @mt[i] = ((@mt[i] ^ mul32(1664525, prev ^ (prev >> 30))) + key[j] + j) & 0xffffffff
      i += 1
      j += 1
      if i >= N
        @mt[0] = @mt[N - 1]
        i = 1
      end
      j = 0 if j >= key.size
      k -= 1
    end
    k = N - 1
    while k > 0
      prev = @mt[i - 1]
      @mt[i] = ((@mt[i] ^ mul32(1566083941, prev ^ (prev >> 30))) - i) & 0xffffffff
      i += 1
      if i >= N
        @mt[0] = @mt[N - 1]
        i = 1
      end
      k -= 1
    end
    @mt[0] = 0x80000000
    @mti = N
  end

  # `a * b` modulo 2**32 for a below 2**31 and b below 2**32, in
  # halves, so the product stays a fixnum.
  def mul32(a, b)
    Primitive.attr! :hidden
    ((a * (b & 0xffff)) + (((a * (b >> 16)) & 0xffff) << 16)) & 0xffffffff
  end

  def next_int32
    reload if @mti >= N
    y = @mt[@mti]
    @mti += 1
    y ^= y >> 11
    y ^= (y << 7) & 0x9d2c5680
    y ^= (y << 15) & 0xefc60000
    y ^= y >> 18
    y & 0xffffffff
  end

  def reload
    kk = 0
    while kk < N - M
      y = (@mt[kk] & UPPER) | (@mt[kk + 1] & LOWER)
      @mt[kk] = @mt[kk + M] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
      kk += 1
    end
    while kk < N - 1
      y = (@mt[kk] & UPPER) | (@mt[kk + 1] & LOWER)
      @mt[kk] = @mt[kk + (M - N)] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
      kk += 1
    end
    y = (@mt[N - 1] & UPPER) | (@mt[0] & LOWER)
    @mt[N - 1] = @mt[M - 1] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
    @mti = 0
  end
end

Random::Base = random_base
module Random::Formatter; end
Random::Base.include(Random::Formatter)

module Kernel
  # Kernel#rand: nil or 0 gives a Float, a Float or negative bound is
  # taken as its Integer size.
  # Kernel#rand is lenient where Random#rand raises: a bound's sign is
  # dropped, and an empty range answers nil.
  def rand(max = 0)
    generator = Random.default
    case max
    when nil then generator.send(:unit_float)
    when Float, Integer
      n = max.to_i.abs
      n == 0 ? generator.send(:unit_float) : generator.rand(n)
    when Range
      low = max.begin
      high = max.end
      if low.is_a?(Numeric) && high.is_a?(Numeric)
        return nil if max.exclude_end? ? high <= low : high < low
      end

      generator.rand(max)
    else generator.rand(max)
    end
  end
  def srand(seed = Random.new_seed) = Random.srand(seed)
  private :rand, :srand
  module_function :rand, :srand
end

# CRuby writes shuffle and sample in Ruby (its array.rb), so they
# answer their own parameters, under CRuby's names.
class Array
  def shuffle(random: Random.default)
    Primitive.attr! :ruby
    dup.shuffle!(random: random)
  end

  # CRuby's walk: from the end, each slot swaps with a draw at or
  # before it.
  def shuffle!(random: Random.default)
    Primitive.attr! :ruby
    Primitive.zr_frozen_error(self) if frozen?
    i = size
    while i > 0
      j = random.send(:limited, i - 1)
      i -= 1
      self[i], self[j] = self[j], self[i]
    end
    self
  end

  # `sample` and `sample(n)`: CRuby's draws, in CRuby's order, so a
  # seeded generator picks the same elements.
  def sample(n = (none = true), random: Random.default)
    Primitive.attr! :ruby
    len = size
    if none
      return nil if len == 0

      return self[random.send(:limited, len - 1)]
    end
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, "negative sample number" if n < 0

    n = len if n > len
    draws = []
    if n <= 10
      i = 0
      while i < n
        draws << random.send(:limited, len - i - 1)
        i += 1
      end
    end
    case n
    when 0 then return []
    when 1 then return [self[draws[0]]]
    when 2
      i, j = draws
      j += 1 if j >= i
      return [self[i], self[j]]
    when 3
      i, j, k = draws
      l = j
      g = i
      if j >= i
        l = i
        j += 1
        g = j
      end
      if k >= l
        k += 1
        k += 1 if k >= g
      end
      return [self[i], self[j], self[k]]
    end
    memo_threshold = if len < 2560 then len / 128
                     elsif len < 5120 then len / 64
                     elsif len < 10240 then len / 32
                     else len / 16
                     end
    if n <= 10
      sorted = [draws[0]]
      idx = [draws[0]]
      i = 1
      while i < n
        k = draws[i]
        j = 0
        while j < i
          break if k < sorted[j]

          k += 1
          j += 1
        end
        sorted.insert(j, k)
        idx << k
        i += 1
      end
      return idx.map { |x| self[x] }
    end
    if n <= memo_threshold / 2
      picks = Array.new(n) { |i| random.send(:limited, len - i - 1) + i }
      memo = {}
      result = []
      i = 0
      while i < n
        j = picks[i]
        i2 = memo.fetch(i, i)
        j2 = memo.fetch(j, j)
        memo[j] = i2
        result << self[j2]
        i += 1
      end
      return result
    end
    result = dup
    i = 0
    while i < n
      j = random.send(:limited, len - i - 1) + i
      result[i], result[j] = result[j], result[i]
      i += 1
    end
    result[0, n]
  end
end
