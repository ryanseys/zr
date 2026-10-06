# frozen_string_literal: true

# Random: CRuby's MT19937, seeded and drawn as CRuby does it, so a
# seeded stream returns the same numbers.
#
# CRuby keeps the generator's words in a struct of its own and puts the
# draws on Random::Base, which leaves Random itself with only `==`. The
# words are in hidden slots here for the same reason: a program sees no
# instance variable on a generator.
random_base = Class.new

class Random < random_base
  # Two generators are equal when they are at the same position in the
  # same seeded stream.
  def ==(other)
    other.is_a?(Random) && seed == other.seed && mti == other.send(:mti) && mt == other.send(:mt)
  end

  def self.new_seed = Primitive.zr_random_seed

  private

  # The whole state of the other generator, so the copy draws what it
  # would have drawn next.
  def initialize_copy(other)
    super
    %i[__seed__ __mt__ __mti__].each do |part|
      value = Primitive.zr_hidden_get(other, part)
      Primitive.zr_hidden_set(self, part, value.is_a?(Array) ? value.dup : value)
    end
    self
  end

  # The generator's 624 words as one Integer, the first word lowest.
  def state
    all = 0
    mt.reverse_each { |word| all = (all << 32) | word }
    all
  end

  # How many draws are left before the words are made again, counting
  # the one that makes them, as CRuby's MT counts `left`.
  def left = N - mti + 1

  def marshal_dump = [state, left, seed]

  # rand_mt_load: the words, the position in them, and the seed. The
  # last two are optional.
  def marshal_load(dump)
    raise TypeError, "wrong argument type #{dump.class} (expected Array)" unless dump.is_a?(Array)
    raise ArgumentError, +"wrong dump data" unless dump.size.between?(1, 3)

    words, rest, seed = dump
    rest = 1 if dump.size < 2
    seed = 0 if dump.size < 3
    mask = 0xffff_ffff
    Primitive.zr_hidden_set(self, :__mt__, Array.new(N) { |i| (words >> (32 * i)) & mask })
    rest = Primitive.zr_index_operand_m(rest)
    raise ArgumentError, +"wrong value" unless rest.between?(1, N)

    set_mti(N - rest + 1)
    Primitive.zr_hidden_set(self, :__seed__, Integer(seed))
    self
  end

  class << self
    private

    def state = default.send(:state)
    def left = default.send(:left)
  end

  public

  def self.default
    Primitive.attr! :hidden
    @default ||= new
  end

  # random_s_rand
  def self.rand(*args) = Random.send(:checked, Random.send(:rand_random, Random, args), args)
  def self.bytes(size) = default.bytes(size)

  # Bytes from the system's own source, not the seeded stream.
  def self.urandom(size)
    raise ArgumentError, +"negative string size (or size too big)" if size < 0

    out = "".b
    out << (Primitive.zr_random_seed & 0xff) while out.bytesize < size
    out
  end

  def self.seed = default.seed

  def self.srand(seed = new_seed)
    was = default.seed
    @default = new(seed)
    was
  end
end

Random::Base = random_base

# Random::Formatter's own draws, which random.c defines for every
# generator and for any object that responds to `bytes`, SecureRandom
# included. A Random draws from its stream, any other object from its bytes.
module Random::Formatter
  def random_number(*args)
    value = Random.send(:rand_random, self, args)
    value = Random.send(:rand_random, self, []) if value.nil?
    raise ArgumentError, "invalid argument - #{args[0]}" if value == false

    value
  end
  alias rand random_number
end
Random::Base.include(Random::Formatter)
Random::Base.extend(Random::Formatter)

# random.c's draws over a generator or over an object's bytes. `rnd` is
# the stream a draw reads, as try_get_rnd finds it, or nil.
class Random
  class << self
    # The 32-bit words of a non-negative Integer, the lowest first, none
    # for zero. The hexadecimal digits split it in linear time, where a
    # shift copies it once a word.
    def words32(n)
      Primitive.attr! :hidden
      return [] if n.zero?

      hex = n.to_s(16)
      Array.new((hex.bytesize + 7) / 8) do |i|
        stop = hex.bytesize - (8 * i)
        hex.byteslice([stop - 8, 0].max...stop).to_i(16)
      end
    end
    private :words32

    private

    def generator_of(obj)
      Primitive.attr! :hidden
      return default if obj.equal?(Random)

      obj.is_a?(Random) ? obj : nil
    end

    # obj_random_bytes: `n` bytes that the object's public `bytes` returns.
    def bytes_of(obj, n)
      Primitive.attr! :hidden
      bytes = obj.public_send(:bytes, n)
      raise TypeError, "wrong argument type #{conversion_name(bytes)} (expected String)" unless bytes.is_a?(String)
      raise RangeError, "random data too short #{bytes.bytesize}" if bytes.bytesize < n
      raise RangeError, "random data too long #{bytes.bytesize}" if bytes.bytesize > n

      bytes
    end

    # rb_int_pair_to_real: 53 random bits as [0, 1), or the 64 bits of
    # the pair scaled into [0, 1].
    def int_pair_to_real(a, b, excl)
      Primitive.attr! :hidden
      return ((a >> 5) * 67108864.0 + (b >> 6)) * (1.0 / 9007199254740992.0) if excl

      high = (a << 21) | (b >> 11)
      low = b & 0x7FF
      high += 1 if (a >> 21) >= 2048 - low
      high / 9007199254740992.0
    end

    def random_real(obj, rnd, excl)
      Primitive.attr! :hidden
      a, b = rnd ? [rnd.send(:next_int32), rnd.send(:next_int32)] : bytes_of(obj, 8).unpack("VV")
      int_pair_to_real(a, b, excl)
    end

    # random_ulong_limited: a draw in 0..limit.
    def ulong_limited(obj, rnd, limit)
      Primitive.attr! :hidden
      return 0 if limit.zero?
      return rnd.send(:limited, limit) if rnd

      width = limit.bit_length
      n = width > 32 ? 8 : 4
      mask = (1 << width) - 1
      full = (1 << (n * 8)) - 1
      bits = rest = 0
      loop do
        if (mask & ~rest) != 0
          bits = bytes_of(obj, n).unpack1(n == 4 ? "V" : "Q<")
          rest = full
        end
        value = bits & mask
        bits >>= width
        rest >>= width
        return value unless limit < value
      end
    end

    def ulong_limited_big(obj, rnd, limit)
      Primitive.attr! :hidden
      return rnd.send(:big_limited, limit) if rnd

      words = (limit.bit_length + 31) / 32
      mask = 0xffffffff >> ((words * 32) - limit.bit_length)
      tops = Random.send(:words32, limit).reverse
      loop do
        draws = bytes_of(obj, words * 4).unpack("V*")
        draws[0] &= mask
        again = false
        words.times do |i|
          if tops[i] < draws[i]
            again = true
            break
          end
          break if draws[i] < tops[i]
        end
        next if again

        all = 0
        draws.each { |word| all = (all << 32) | word }
        return all
      end
    end

    # rb_random_ulong_limited: what Array#shuffle and #sample draw, from
    # an object's own `rand` where it has no stream.
    def limited_for(obj, limit)
      Primitive.attr! :hidden
      rnd = generator_of(obj)
      return rnd.send(:limited, limit) if rnd

      value = obj.public_send(:rand, limit + 1)
      value = Integer.try_convert(value) or raise TypeError, "no implicit conversion of #{conversion_name(value)} into Integer"
      raise RangeError, "random number too small #{value}" if value.negative?
      raise RangeError, "random number too big #{value}" if value > limit

      value
    end

    # rand_int: nil where a restrictive draw has no numbers to take.
    def rand_int(obj, rnd, max, restrictive)
      Primitive.attr! :hidden
      if Primitive.zr_fixnum_p_m(max)
        return nil if max.zero?
        if max.negative?
          return nil if restrictive

          max = -max
        end
        return ulong_limited(obj, rnd, max - 1)
      end
      if max.negative?
        return nil if restrictive

        max = -max
      end
      max -= 1
      return ulong_limited(obj, rnd, max) if Primitive.zr_fixnum_p_m(max)

      ulong_limited_big(obj, rnd, max)
    end

    # rand_range: false for what is no range, nil for an empty one.
    def rand_range(obj, rnd, range)
      Primitive.attr! :hidden
      if range.is_a?(Range) || (range.respond_to?(:begin) && range.respond_to?(:end) && range.respond_to?(:exclude_end?))
        low = range.begin
        high = range.end
        excl = range.exclude_end?
      else
        return false
      end
      domain_error if low.nil? || high.nil?
      return false unless high.respond_to?(:-)

      span = high - low
      domain_error if span.nil?
      value = nil
      if !span.is_a?(Float) && (whole = Integer.try_convert(span))
        max = whole - (excl ? 1 : 0)
        if Primitive.zr_fixnum_p_m(whole)
          value = ulong_limited(obj, rnd, max) if max >= 0
        elsif whole.positive?
          value = Primitive.zr_fixnum_p_m(max) ? ulong_limited(obj, rnd, max) : ulong_limited_big(obj, rnd, max)
        end
      elsif (width = float_of(span))
        mid = 0.5
        scale = 1
        if width.infinite?
          min = finite(Float(low)) / 2.0
          width = finite(Float(high)) / 2.0
          scale = 2
          mid = width + min
          width -= min
        elsif width.nan?
          domain_error
        end
        if width > 0.0
          r = random_real(obj, rnd, excl)
          return ((r - 0.5) * width * scale) + mid if scale > 1

          value = r * width
        elsif width == 0.0 && !excl
          value = 0.0
        end
      end
      return nil if value.nil?
      return low + value if Primitive.zr_fixnum_p_m(low) && Primitive.zr_fixnum_p_m(value)
      return value + low if value.is_a?(Integer) && !Primitive.zr_fixnum_p_m(value)
      if value.is_a?(Float) && (base = float_of(low))
        return value + base
      end

      low + value
    end

    # rand_random: a draw of the kind that the argument selects; nil for
    # a bound with nothing under it, false for a value that selects no draw.
    def rand_random(obj, args)
      Primitive.attr! :hidden
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..1)" if args.size > 1

      rnd = generator_of(obj)
      return random_real(obj, rnd, true) if args.empty?

      max = args[0]
      return nil if max.nil?
      if !max.is_a?(Float) && (whole = Integer.try_convert(max))
        return rand_int(obj, rnd, whole, true)
      end
      if (bound = float_of(max))
        bound = finite(bound)
        return nil if bound.negative?

        r = random_real(obj, rnd, true)
        return bound > 0.0 ? r * bound : r
      end
      rand_range(obj, rnd, max)
    end

    # check_random_number
    def checked(value, args)
      Primitive.attr! :hidden
      Primitive.zr_index_operand_m(args[0]) if value == false
      raise ArgumentError, "invalid argument - #{args[0]}" if value.nil?

      value
    end

    # rb_check_to_float: a Float, or the value of a Numeric's to_f.
    def float_of(value)
      Primitive.attr! :hidden
      return value if value.is_a?(Float)

      value.is_a?(Numeric) ? Float(value) : nil
    end

    def finite(value)
      Primitive.attr! :hidden
      domain_error unless value.finite?

      value
    end

    def domain_error
      Primitive.attr! :hidden
      raise Errno::EDOM
    end
  end
end

# The draws themselves, where CRuby keeps them: a generator gets `rand`,
# `bytes` and `seed` from Random::Base, and the words of the state never
# leave this class.
class Random::Base
  N = 624
  M = 397
  MATRIX_A = 0x9908b0df
  UPPER = 0x80000000
  LOWER = 0x7fffffff
  private_constant :N, :M, :MATRIX_A, :UPPER, :LOWER

  def initialize(seed = Random.new_seed)
    # rb_to_int: a Float truncates; a Rational or a real Complex converts.
    seed = seed.to_i if seed.is_a?(Float)
    seed = seed.to_i if seed.is_a?(Rational) || seed.is_a?(Complex)
    # rb_to_int: nil is named as a value, and to_int converts the rest.
    raise TypeError, +"no implicit conversion of nil into Integer" if seed.nil?

    seed = Primitive.zr_index_operand_m(seed) unless seed.is_a?(Integer)

    Primitive.zr_hidden_set(self, :__seed__, seed)
    key = Random.send(:words32, seed.abs)
    # CRuby decides by the words the seed packs into: one or none seed
    # init_genrand, more seed init_by_array, less a top word of one, its
    # packer's leading-zero guard.
    words = key.size
    key.pop if words > 1 && key.last == 1
    words <= 1 ? init_genrand(key[0] || 0) : init_by_array(key)
  end

  def seed = Primitive.zr_hidden_get(self, :__seed__)

  # random_rand: rand_random, where a bound with nothing under it is an
  # ArgumentError and a value that selects no draw fails as NUM2LONG does.
  def rand(*args) = Random.send(:checked, Random.send(:rand_random, self, args), args)

  # `n` random bytes, four per draw, least significant first.
  def bytes(size)
    size = to_integer(size)
    raise ArgumentError, +"negative string size (or size too big)" if size < 0

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

  private

  # A draw in 0..limit, by rejection from as many 32-bit words as the
  # limit spans.
  def limited(limit)
    Primitive.attr! :hidden
    return 0 if limit == 0
    return big_limited(limit) unless Primitive.zr_fixnum_p_m(limit) || limit <= 0xffff_ffff_ffff_ffff

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
    words = Random.send(:words32, limit)
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

  # The generator's words, and the position in them: CRuby keeps this
  # state in a struct, so no instance variable contains it here.
  def mt
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__mt__)
  end

  def mti
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__mti__)
  end

  def set_mti(v)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :__mti__, v)
  end

  def init_genrand(s)
    Primitive.attr! :hidden
    words = Array.new(N, 0)
    words[0] = s & 0xffffffff
    i = 1
    while i < N
      prev = words[i - 1]
      words[i] = (mul32(1812433253, prev ^ (prev >> 30)) + i) & 0xffffffff
      i += 1
    end
    Primitive.zr_hidden_set(self, :__mt__, words)
    set_mti(N)
  end

  def init_by_array(key)
    Primitive.attr! :hidden
    init_genrand(19650218)
    words = mt
    i = 1
    j = 0
    k = N > key.size ? N : key.size
    while k > 0
      prev = words[i - 1]
      words[i] = ((words[i] ^ mul32(1664525, prev ^ (prev >> 30))) + key[j] + j) & 0xffffffff
      i += 1
      j += 1
      if i >= N
        words[0] = words[N - 1]
        i = 1
      end
      j = 0 if j >= key.size
      k -= 1
    end
    k = N - 1
    while k > 0
      prev = words[i - 1]
      words[i] = ((words[i] ^ mul32(1566083941, prev ^ (prev >> 30))) - i) & 0xffffffff
      i += 1
      if i >= N
        words[0] = words[N - 1]
        i = 1
      end
      k -= 1
    end
    words[0] = 0x80000000
    set_mti(N)
  end

  # `a * b` modulo 2**32 for a below 2**31 and b below 2**32, in
  # halves, so the product stays a fixnum.
  def mul32(a, b)
    Primitive.attr! :hidden
    ((a * (b & 0xffff)) + (((a * (b >> 16)) & 0xffff) << 16)) & 0xffffffff
  end

  def next_int32
    Primitive.attr! :hidden
    reload if mti >= N
    words = mt
    at = mti
    y = words[at]
    set_mti(at + 1)
    y ^= y >> 11
    y ^= (y << 7) & 0x9d2c5680
    y ^= (y << 15) & 0xefc60000
    y ^= y >> 18
    y & 0xffffffff
  end

  def reload
    Primitive.attr! :hidden
    words = mt
    kk = 0
    while kk < N - M
      y = (words[kk] & UPPER) | (words[kk + 1] & LOWER)
      words[kk] = words[kk + M] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
      kk += 1
    end
    while kk < N - 1
      y = (words[kk] & UPPER) | (words[kk + 1] & LOWER)
      words[kk] = words[kk + (M - N)] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
      kk += 1
    end
    y = (words[N - 1] & UPPER) | (words[0] & LOWER)
    words[N - 1] = words[M - 1] ^ (y >> 1) ^ (y.odd? ? MATRIX_A : 0)
    set_mti(0)
  end
end

module Kernel
  # rb_f_rand: a range as Random draws it, else the bound's Integer, its
  # sign dropped, and a Float where either leaves nothing to draw.
  def rand(max = nil)
    rnd = Random.send(:default)
    unless max.nil?
      value = Random.send(:rand_range, Random, rnd, max)
      return value unless value == false

      max = to_integer(max)
      unless max.zero?
        value = Random.send(:rand_int, Random, rnd, max, false)
        return value unless value.nil?
      end
    end
    Random.send(:random_real, Random, rnd, true)
  end
  def srand(seed = Random.new_seed) = Random.srand(seed)
  private :rand, :srand
  module_function :rand, :srand
end

# CRuby writes shuffle and sample in Ruby (its array.rb), so they
# return their own parameters, under CRuby's names.
class Array
  # A plain copy shuffled, as rb_ary_shuffle shuffles rb_ary_dup's.
  def shuffle(random: Random.default)
    Primitive.attr! :ruby
    Array.new(self).send(:shuffled!, random)
  end

  def shuffle!(random: Random.default)
    Primitive.attr! :ruby
    shuffled!(random)
  end

  # CRuby's walk: from the end, each slot swaps with a draw at or
  # before it.
  def shuffled!(random)
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if frozen?
    len = i = Primitive.zr_ary_len_m(self)
    while i > 0
      j = Random.send(:limited_for, random, i - 1)
      i -= 1
      raise RuntimeError, +"modified during shuffle" if Primitive.zr_ary_len_m(self) != len
      held = Primitive.zr_ary_aref1_m(self, i)
      Primitive.zr_ary_aset_at(self, i, Primitive.zr_ary_aref1_m(self, j))
      Primitive.zr_ary_aset_at(self, j, held)
    end
    self
  end

  # `sample` and `sample(n)`: CRuby's draws, in CRuby's order, so a
  # seeded generator picks the same elements.
  def sample(n = (none = true), random: Random.default)
    Primitive.attr! :ruby
    len = Primitive.zr_ary_len_m(self)
    if none
      return nil if len == 0

      # rb_ary_sample draws only for two or more, and reads the element
      # with a bounds check, as the draw may change the Array.
      return Primitive.zr_ary_aref1_m(self, len < 2 ? 0 : Random.send(:limited_for, random, len - 1))
    end
    n = Primitive.zr_index_operand_m(n)
    raise ArgumentError, +"negative sample number" if n < 0

    n = len if n > len
    draws = []
    if n <= 10
      i = 0
      while i < n
        draws << Random.send(:limited_for, random, len - i - 1)
        i += 1
      end
      # A draw that changed the Array: a draw past its new end samples
      # nothing.
      if Primitive.zr_ary_len_m(self) < len
        len = Primitive.zr_ary_len_m(self)
        return [] if draws.any? { |d| d >= len }
        n = len if n > len
      end
    end
    case n
    when 0 then return []
    when 1 then return [self[draws[0]]]
    when 2
      i, j = draws
      j += 1 if j >= i
      return [Primitive.zr_ary_aref1_m(self, i), Primitive.zr_ary_aref1_m(self, j)]
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
      return [Primitive.zr_ary_aref1_m(self, i), Primitive.zr_ary_aref1_m(self, j), Primitive.zr_ary_aref1_m(self, k)]
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
      return idx.map { |x| Primitive.zr_ary_aref1_m(self, x) }
    end
    if n <= memo_threshold / 2
      picks = Array.new(n) { |i| Random.send(:limited_for, random, len - i - 1) + i }
      memo = {}
      result = []
      i = 0
      while i < n
        j = picks[i]
        i2 = memo.fetch(i, i)
        j2 = memo.fetch(j, j)
        memo[j] = i2
        result << Primitive.zr_ary_aref1_m(self, j2)
        i += 1
      end
      return result
    end
    result = dup
    i = 0
    while i < n
      j = Random.send(:limited_for, random, len - i - 1) + i
      result[i], result[j] = result[j], result[i]
      i += 1
    end
    result[0, n]
  end
end
