# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/kernel_jit"
require_relative "../support/harness/kernel_host"

# WASI has no libm and no strtod in a zr module, so the WASI layer
# defines them itself (lib/zr/runtime/kernel/os/wasi/libm*.rb and
# strtod.rb). Compiled for this host, they give the same values as
# CRuby's Math, Float and String#to_f.
class WasiLibmTest < Minitest::Test
  FILES = "os/wasi/{libm,strtod}*.rb"

  VALUES = [1.0, -1.0, 0.5, 3.0, 44.7815, -2.675, 1.0e20, 1.0e-300, 5.0e-324, -2.2250738585072014e-308,
            Float::MAX, Float::MIN, Float::EPSILON].freeze

  def self.kernel = @kernel ||= Zr::Harness::KernelJIT.new(FILES)

  def test_frexp_is_crubys
    VALUES.each do |x|
      assert_equal Math.frexp(x), frexp(x), x.inspect
    end
  end

  def test_frexp_returns_zero_infinity_and_nan_unchanged
    assert_equal [0.0, 0], frexp(0.0)
    assert_equal [Float::INFINITY, 0], frexp(Float::INFINITY)
    assert_predicate frexp(Float::NAN).first, :nan?
  end

  def test_ldexp_is_crubys
    VALUES.product([0, 1, -1, 52, -52, 1023, -1022, -1074, 1100, -1100, 2000, -2000]).each do |x, n|
      want = Math.ldexp(x, n)
      got = self.class.kernel.call("ldexp", x, n)

      assert_equal [want].pack("G"), [got].pack("G"), "ldexp(#{x}, #{n})"
    end
  end

  # --- strtod ---------------------------------------------------------------

  STRTOD_HARD = %w[
    0 -0 0.0 -0.0 1 -1 1.5 0.1 0.2 0.3 0.30000000000000004 123456789012345678901234567890
    2.2250738585072011e-308 2.2250738585072012e-308 2.2250738585072014e-308 2.225073858507201e-308
    1e23 8.533e+68 4.1006e-184 9.998e+307 9.9538452227e-280 6.47660115e-260 7.4e+47 5.92e+48
    9007199254740993 9007199254740992 9007199254740991 9007199254740994 9007199254740995
    18014398509481985 18014398509481987 9223372036854775807 9223372036854775808 18446744073709551615
    5e-324 4.9406564584124654e-324 2.4703282292062327e-324 2.4703282292062328e-324 2.47e-324 2.5e-324
    1e-324 7e-324 1e-400 1.7976931348623157e308 1.7976931348623158e308 1.797693134862315807e308
    1.7976931348623159e308 1.8e308 1e309 1e400 1e10000 1e-10000 1e99999999999 0e99999999 -1e400
    4.35679034e-310 1.3e22 1e22 1e15 1234567e30 1e37 1e38 9007199254740991e22 9007199254740993e-22
    0.000000000000000000000000000000001 100000000000000000000000000000000e-30 1.000000000000000111
    1.00000000000000011102230246251565404236316680908203125 1.00000000000000011102230246251565404236316680908203124
    1.00000000000000011102230246251565404236316680908203126 1.00000000000000033306690738754696212708950042724609375
  ].freeze

  def test_strtod_rounds_hard_cases_as_crubys_float
    STRTOD_HARD.each { |text| assert_strtod Float(text), text, text.size }
  end

  def test_strtod_rounds_random_decimals_as_crubys_float
    rng = Random.new(20_261_011)
    3000.times do
      text = "#{rng.rand(1..9)}.#{Array.new(rng.rand(0..25)) { rng.rand(10) }.join}e#{rng.rand(-345..310)}"
      text = "-#{text}" if rng.rand(2).zero?

      assert_strtod Float(text), text, text.size
    end
  end

  # Each case is the exact midpoint of two doubles, and the midpoint
  # with one more digit above or below it, as decimal text.
  def test_strtod_rounds_halfway_cases_to_even
    rng = Random.new(7)
    doubles = [1.0, Float::MAX.prev_float, Float::MIN, Float::MIN.prev_float, 5.0e-324, 1.0e23, 2.0**53, 0.1] +
              Array.new(150) { [rng.rand(2**64)].pack("Q").unpack1("D") }.filter_map { |x| x.abs if x.finite? }
    doubles.each do |x|
      mid = (x.to_r + x.next_float.to_r) / 2
      text = exact_decimal(mid)

      # A dyadic fraction ends in 5; a midpoint above 2**53 is an integer.
      above = text.include?(".") ? "#{text}1" : "#{text}.1"
      below = text.include?(".") ? "#{text.delete_suffix("5")}4#{"9" * 20}" : "#{Integer(text) - 1}.#{"9" * 20}"
      [text, above, below].each { |t| assert_strtod exact_double(t), t, t.size }
    end
  end

  def test_strtod_reads_long_inputs
    smallest_half = exact_decimal(Rational(1, 2**1075))
    [
      "1#{"0" * 400}e-400", "9007199254740992.5#{"0" * 900}1", "9007199254740992.5#{"0" * 900}",
      "9007199254740993#{"0" * 900}e-900", "0.#{"0" * 1000}1e1000", "#{"9" * 1000}e-1000", "1#{"2" * 1200}",
      smallest_half, "#{smallest_half}1", "#{smallest_half.delete_suffix("5")}4", "1#{"0" * 310}", "1#{"0" * 308}"
    ].each { |text| assert_strtod exact_double(text), text, text.size }
  end

  def test_strtod_reads_hex_floats
    {
      "0x1.8p+3" => 12.0, "0X1.8P3" => 12.0, "0xA" => 10.0, "-0x1p-1" => -0.5, "0x.8" => 0.5, "0x1p-1074" => 5.0e-324,
      "0x1p-1075" => 0.0, "0x1.8p-1075" => 5.0e-324, "0x1.0000000000001p-1074" => 5.0e-324, "0x1.8p-1074" => 1.0e-323,
      "0x1.fffffffffffff8p1023" => Float::INFINITY, "0x1.fffffffffffff7ffp1023" => Float::MAX,
      "0x1.00000000000008p0" => 1.0, "0x1.00000000000018p0" => 1.0 + (2 * Float::EPSILON),
      "0x1.000000000000080000000001p0" => 1.0 + Float::EPSILON, "0x123456789abcdef0123p0" => 0x123456789abcdef0123.to_f,
      "0x0.000000000000000000001p0" => 2.0**-84, "0x1p+99999999" => Float::INFINITY, "0x1p-99999999" => 0.0,
      "0x1.fffffffffffffp-1023" => Float::MIN, "0x1.ffffffffffffe8p-1023" => Float::MIN.prev_float, "0x0.fffffffffffff8p-1022" => Float::MIN
    }.each { |text, want| assert_strtod want, text, text.size }
  end

  # The end pointer: how far strtod read.
  def test_strtod_stops_where_c_stops
    {
      "1.5abc" => [1.5, 3], "1e" => [1.0, 1], "1e+" => [1.0, 1], "1e+5x" => [100_000.0, 4], "1.e5" => [100_000.0, 4],
      "  -12" => [-12.0, 5], "\t\n+7" => [7.0, 4], "." => [0.0, 0], "-" => [0.0, 0], "" => [0.0, 0], "  x" => [0.0, 0],
      "0x" => [0.0, 1], "0xg" => [0.0, 1], "0x.p1" => [0.0, 1], "0x1p" => [1.0, 3], "0x1p-" => [1.0, 3], ".5" => [0.5, 2],
      "inf" => [Float::INFINITY, 3], "-Infinity" => [-Float::INFINITY, 9], "INFINITx" => [Float::INFINITY, 3],
      "1_000" => [1.0, 1], "12.34.5" => [12.34, 5], "00012" => [12.0, 5]
    }.each { |text, (want, stop)| assert_strtod want, text, stop }
  end

  def test_strtod_reads_nan
    { "nan" => 3, "-NaN" => 4, "nan(abc_1)" => 10, "nan(" => 3, "nan(a b)" => 3 }.each do |text, stop|
      value, read = strtod(text)

      assert_predicate value, :nan?, text
      assert_equal stop, read, text
    end
  end

  def test_strtod_takes_a_null_end_pointer
    buf = c_string("2.5")

    assert_in_delta 2.5, self.class.kernel.call("strtod", buf.to_i, 0), 0.0
  end

  # --- libm -------------------------------------------------------------------

  INF = Float::INFINITY
  NAN = Float::NAN

  # Values at the edges: zeros, infinities, NaN, subnormals, the ends of
  # the range, and some exact values.
  SPECIAL = [0.0, -0.0, INF, -INF, NAN, 5.0e-324, -5.0e-324, 1.0e-320, Float::MIN, -Float::MIN, Float::MIN.prev_float,
             Float::MAX, -Float::MAX, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 3.0, -3.0, 10.0, 1.0e-300, -1.0e-300, 1.0e300,
             -1.0e300, Float::EPSILON, 1.0 + Float::EPSILON, 1.0 - (Float::EPSILON / 2)].freeze

  # The C libm of this host, for the functions that Ruby has no plain
  # method for (fmod, pow, fma).
  def self.host_libm(name, arity)
    @host_libm ||= {}
    @host_libm[name] ||= Fiddle::Function.new(Fiddle::Handle::DEFAULT[name], [Fiddle::TYPE_DOUBLE] * arity, Fiddle::TYPE_DOUBLE)
  end

  def test_fmod_is_exact
    pairs = SPECIAL.product(SPECIAL) + random_pairs(1, 3000) +
            [[1.0e300, 3.0], [-1.0e300, 7.0e-300], [5.0e-324, 3.0e-324], [Float::MAX, Float::MIN], [7.5, -2.0], [-7.5, 2.0]]

    check_binary("fmod", pairs, 0) { |x, y| self.class.host_libm("fmod", 2).call(x, y) }
  end

  def test_hypot_is_within_one_ulp
    check_binary("hypot", SPECIAL.product(SPECIAL), 1) { |x, y| Math.hypot(x, y) }
    check_binary("hypot", random_pairs(2, 3000) + [[3.0, 4.0], [1.0e300, 1.0e300], [1.0e-300, 1.0e-300], [5.0e-324, 5.0e-324]], 1) do |x, y|
      Math.hypot(x, y)
    end
  end

  def test_pow_is_within_one_ulp
    pow = ->(x, y) { self.class.host_libm("pow", 2).call(x, y) }
    check_binary("pow", SPECIAL.product(SPECIAL + [0.25, -0.25, 1.5, 4.0, -4.0, 1.0e20, -1.0e20, 2.0**-70]), 1, &pow)
    rng = Random.new(3)
    pairs = Array.new(1500) { [rng.rand * 4, (rng.rand - 0.5) * 200] } +
            Array.new(1000) { [(rng.rand - 0.5) * 20, rng.rand(-40..40).to_f] } +
            Array.new(1000) { [random_double(rng).abs, rng.rand - 0.5] } +
            Array.new(500) { [1.0 + ((rng.rand - 0.5) * 1.0e-6), (rng.rand - 0.5) * 1.0e9] } +
            [[2.0, 1023.0], [2.0, 1024.0], [2.0, -1074.0], [2.0, -1075.0], [0.5, 1074.5], [10.0, 308.25], [10.0, -323.5],
             [-2.0, 1023.0], [-2.0, -1075.0], [Float::MIN, 0.5], [5.0e-324, 0.25], [1.0e-310, -0.9]]

    check_binary("pow", pairs, 1, &pow)
  end

  def test_exp_is_within_one_ulp
    check_unary("exp", SPECIAL + [709.782712893384, 709.79, -745.1332191019411, -745.14, -708.4, -740.0], 1) { |x| Math.exp(x) }
    rng = Random.new(4)
    xs = Array.new(2000) { (rng.rand - 0.5) * 1500 } + Array.new(1000) { (rng.rand - 0.5) * 2 } +
         Array.new(500) { (rng.rand - 0.5) * 1.0e-10 } + Array.new(300) { -708 - (rng.rand * 37) }

    check_unary("exp", xs, 1) { |x| Math.exp(x) }
  end

  def test_expm1_is_within_one_ulp
    rng = Random.new(5)
    xs = SPECIAL + [709.78, 709.79, -38.0, -40.0, 0.34657359027997264, 0.3465735902799727, 1.0397207708399179, 56 * Math.log(2)] +
         Array.new(1500) { (rng.rand - 0.5) * 100 } + Array.new(1000) { (rng.rand - 0.5) * 3 } +
         Array.new(500) { (rng.rand - 0.5) * 1.0e-8 } + Array.new(500) { random_double(rng) }

    check_unary("expm1", xs, 1) { |x| Math.expm1(x) }
  end

  # Values for the logarithms: near 1, every exponent, and subnormals.
  def log_values(seed)
    rng = Random.new(seed)
    SPECIAL + [0.9375, 0.9374999999999999, 1.064697265625, 1.0646972656249998, 0.95751953125, 1.04425048828125,
               0.7071067811865476, 1.4142135623730951, 0.29289321881345254, -0.29289321881345254, 1.0e-320, 3.0e-310] +
      Array.new(1500) { random_double(rng).abs } + Array.new(1000) { 1.0 + ((rng.rand - 0.5) * 0.2) } +
      Array.new(500) { rng.rand * 1000 } + Array.new(300) { rng.rand * 1.0e-310 } + Array.new(200) { -rng.rand * 10 }
  end

  def test_log_is_within_one_ulp
    check_unary("log", log_values(6), 1) { |x| x.negative? ? NAN : Math.log(x) }
  end

  def test_log2_is_within_one_ulp
    check_unary("log2", log_values(7), 1) { |x| x.negative? ? NAN : Math.log2(x) }
  end

  def test_log10_is_within_one_ulp
    check_unary("log10", log_values(8) + [10.0, 100.0, 1.0e22, 1.0e-5], 1) { |x| x.negative? ? NAN : Math.log10(x) }
  end

  def test_log1p_is_within_one_ulp
    rng = Random.new(9)
    xs = log_values(9) + [-1.0, -0.9999999999999999, -1.5, -0.2928932188134524, 0.41421356237309503, 1.0e-17, -1.0e-17] +
         Array.new(1000) { rng.rand - 1.0 } + Array.new(500) { (rng.rand - 0.5) * 1.0e-6 }

    check_unary("log1p", xs, 1) { |x| x < -1 ? NAN : Math.log1p(x) }
  end

  # Values for the trigonometric functions: the doubles next to multiples
  # of pi/2 (where the reduction cancels), the edges of each reduction
  # case, and large arguments, which need the reduction of
  # __rem_pio2_large.
  def trig_values(seed)
    rng = Random.new(seed)
    near = (1..40).flat_map do |k|
      m = k * Math::PI / 2
      [m, m.prev_float, m.next_float, -m]
    end
    near += [Math::PI / 4, (Math::PI / 4).next_float, 0.6744, 0.6745, 2.0**-26, 2.0**-27, 2.0**-28, 2.0**20 * Math::PI / 2,
             (2.0**20 * Math::PI / 2).next_float, 1.0e22, 1.0e300, Float::MAX, 6381956970095103.0 * (2**797),
             5.319372648326541e+255, 1.7976931348623157e+308, 2.0**1023, 2.0**200, 2.0**120, 2.0**60, 2.0**30]
    SPECIAL + near + Array.new(1500) { (rng.rand - 0.5) * 20 } + Array.new(800) { (rng.rand - 0.5) * 2.0e6 } +
      Array.new(800) { random_double(rng) } + Array.new(300) { (rng.rand - 0.5) * 1.0e-7 }
  end

  def test_sin_is_within_one_ulp
    check_unary("sin", trig_values(10), 1) { |x| Math.sin(x) }
  end

  def test_cos_is_within_one_ulp
    check_unary("cos", trig_values(11), 1) { |x| Math.cos(x) }
  end

  # macOS's tan is up to 2 ulp from the exact value (tan(-0.9855017167263247)
  # for one); musl's is within 1 ulp. So tan is compared with macOS's
  # within 2 ulp, and with a precise value within 1 ulp.
  def test_tan_is_within_two_ulp_of_macos
    check_unary("tan", trig_values(12), 2) { |x| Math.tan(x) }
  end

  def test_tan_is_within_one_ulp_of_the_exact_value
    rng = Random.new(13)
    xs = [-7.015526294645335, -4.00614210013174, 8.108719095499172, -0.9855017167263247, 2.1718382815680126, 0.7, 0.9,
          1.5707963267948966, 1.0e22, 1.0e40, 2.0**100] + Array.new(200) { (rng.rand - 0.5) * 20 }

    check_unary("tan", xs, 1) { |x| precise_tan(x) }
  end

  # Values for the hyperbolic functions: the edges of each case, and
  # arguments where exp overflows, which go through __expo2.
  def hyperbolic_values(seed)
    rng = Random.new(seed)
    SPECIAL + [709.7, 709.79, 710.0, 710.47, 710.48, -710.4, 711.0, 20.0, 20.000000000000004, 0.5493061443340548,
               0.25541281188299525, 0.6931471805599453, 2.0**-26, 2.0**-27, 2.0**26, 2.0**25, 0.125, 1.125, 2.0] +
      Array.new(1500) { (rng.rand - 0.5) * 50 } + Array.new(1000) { (rng.rand - 0.5) * 2 } +
      Array.new(500) { (rng.rand - 0.5) * 1500 } + Array.new(500) { random_double(rng) }
  end

  def test_sinh_is_within_one_ulp
    check_unary("sinh", hyperbolic_values(14), 1) { |x| Math.sinh(x) }
  end

  def test_cosh_is_within_one_ulp
    check_unary("cosh", hyperbolic_values(15), 1) { |x| Math.cosh(x) }
  end

  # musl's tanh, asinh, acosh and atanh are up to 2 ulp from the exact
  # value in some ranges (their comments say where); macOS's are closer.
  def test_tanh_is_within_two_ulp
    check_unary("tanh", hyperbolic_values(16), 2) { |x| Math.tanh(x) }
  end

  def test_asinh_is_within_two_ulp
    check_unary("asinh", hyperbolic_values(17), 2) { |x| Math.asinh(x) }
  end

  def test_acosh_is_within_two_ulp
    rng = Random.new(18)
    xs = hyperbolic_values(18).map(&:abs) + [1.0, 1.0000000000000002, 0.9999999999999999, -1.0, 0.5] +
         Array.new(1000) { 1 + (rng.rand * 0.2) } + Array.new(500) { 1 + (rng.rand * 1.0e-8) }

    check_unary("acosh", xs, 2) { |x| x < 1 ? NAN : Math.acosh(x) }
  end

  def test_atanh_is_within_two_ulp
    rng = Random.new(19)
    xs = SPECIAL + [0.5, 0.49999999999999994, -0.5, 0.9999999999999999, -0.9999999999999999, 2.0**-32, 2.0**-33] +
         Array.new(2000) { (rng.rand * 2) - 1 } + Array.new(500) { (rng.rand - 0.5) * 1.0e-9 }

    check_unary("atanh", xs, 2) { |x| x.abs > 1 ? NAN : Math.atanh(x) }
  end

  # Values in [-1, 1] for asin and acos, the edges of each case, and some
  # out of the domain.
  def unit_values(seed)
    rng = Random.new(seed)
    SPECIAL + [0.975, 0.9750000000000001, 0.97499999999999998, 1.0.prev_float, -1.0.next_float, 0.5.prev_float,
               2.0**-26, 2.0**-57, 2.0**-58, 1.5, -1.5] +
      Array.new(2000) { (rng.rand * 2) - 1 } + Array.new(500) { 1 - (rng.rand * 1.0e-6) } +
      Array.new(300) { (rng.rand - 0.5) * 1.0e-8 }
  end

  def test_asin_is_within_one_ulp
    check_unary("asin", unit_values(20), 1) { |x| x.abs > 1 ? NAN : Math.asin(x) }
  end

  def test_acos_is_within_one_ulp
    check_unary("acos", unit_values(21), 1) { |x| x.abs > 1 ? NAN : Math.acos(x) }
  end

  def test_atan_is_within_one_ulp
    rng = Random.new(22)
    xs = SPECIAL + [0.4375, 0.4374999999999999, 0.6875, 1.1875, 2.4375, 2.0**66, 2.0**-27] +
         Array.new(1500) { (rng.rand - 0.5) * 10 } + Array.new(1000) { random_double(rng) }

    check_unary("atan", xs, 1) { |x| Math.atan(x) }
  end

  def test_atan2_is_within_one_ulp
    rng = Random.new(23)
    edges = SPECIAL + [1.0e-20, -1.0e-20, 1.0e20, -1.0e20]
    pairs = edges.product(edges) + random_pairs(23, 2000) +
            Array.new(500) { [(rng.rand - 0.5) * 4, (rng.rand - 0.5) * 4] } +
            Array.new(200) { [rng.rand * 1.0e-30, -rng.rand] }

    check_binary("atan2", pairs, 1) { |y, x| Math.atan2(y, x) }
  end

  def test_cbrt_is_within_one_ulp
    rng = Random.new(24)
    xs = SPECIAL + [8.0, 27.0, -27.0, 1.0e-310, 2.0**-1074, 3.0e-320] + Array.new(2000) { random_double(rng) } +
         Array.new(1000) { (rng.rand - 0.5) * 100 }

    check_unary("cbrt", xs, 1) { |x| Math.cbrt(x) }
  end

  # Values for erf and erfc: the edges of each case of erf.c.
  def erf_values(seed)
    rng = Random.new(seed)
    SPECIAL + [0.84375, 0.8437499999999999, 1.25, 1.2499999999999998, 2.857142857142857, 2.857142857142858, 6.0, 5.999999999999999,
               28.0, 27.999999999999996, 0.25, 0.24999999999999997, 2.0**-28, 2.0**-56, 2.0**-57, 26.5, -5.9] +
      Array.new(2000) { (rng.rand - 0.5) * 12 } + Array.new(800) { (rng.rand - 0.5) * 52 } + Array.new(300) { (rng.rand - 0.5) * 1.0e-8 }
  end

  # macOS's erf is up to 3 ulp from the exact value
  # (erf(0.47369317167132863) for one), and its erfc up to 5 ulp
  # (erfc(22.06002724043096)); past 27 its erfc gives 0 where the value
  # rounds to 5e-324. musl's are within 1 ulp. So they are compared with
  # macOS's within 4 and 8 ulp, and with a precise value within 1 ulp.
  def test_erf_is_within_four_ulp_of_macos
    check_unary("erf", erf_values(25), 4) { |x| Math.erf(x) }
  end

  def test_erfc_is_within_eight_ulp_of_macos
    check_unary("erfc", erf_values(26), 8) { |x| Math.erfc(x) }
  end

  def test_erf_and_erfc_are_within_one_ulp_of_the_exact_value
    rng = Random.new(27)
    xs = [-0.22388468102979164, 0.47369317167132863, 0.04606646816455262, -0.8029727352504135, 0.84375, 1.25, 2.857142857142858,
          5.999999999999999, 1.0e-10] + Array.new(150) { (rng.rand * 8) - 2 }

    check_unary("erf", xs, 1) { |x| nearest_double(Rational(precise_erf(x), 2**1600)) }
    check_unary("erfc", xs, 1) { |x| nearest_double(Rational((2**1600) - precise_erf(x), 2**1600)) }
  end

  # Values for tgamma and lgamma_r: integers, half integers, the poles,
  # the edges of each case of lgamma_r.c, and the ends of the range.
  def gamma_values(seed)
    rng = Random.new(seed)
    SPECIAL + (-30..30).map(&:to_f) + (-30..30).map { |n| n + 0.5 } +
      [171.0, 171.6, 171.7, 172.0, 184.0, -184.5, -183.5, -170.5, 2.0**-54, 2.0**-55, 2.0**-70, 2.0**-71, 23.0, 24.0, 22.5,
       0.9, 0.7316, 0.23164, 1.7316, 1.23164, 1.4616321449683622, 7.999999999999999, 8.0, 2.0**58, 2.0**57, 1.0e300] +
      Array.new(1500) { (rng.rand - 0.5) * 60 } + Array.new(500) { rng.rand * 2 } + Array.new(300) { rng.rand * 180 } +
      Array.new(300) { -rng.rand * 190 }
  end

  def test_tgamma_of_special_values_and_small_integers_is_exact
    # Pairs, not a Hash: 0.0 and -0.0 are one key of a Hash.
    cases = [[0.0, INF], [-0.0, -INF], [INF, INF], [-INF, NAN], [NAN, NAN], [-1.0, NAN], [-2.0, NAN], [-1.0e300, NAN],
             [172.0, INF], [184.0, INF], [1.0e300, INF], [-184.5, -0.0], [-185.5, 0.0], [2.0**-60, 2.0**60]] +
            (1..23).map { |n| [n.to_f, (1...n).reduce(1, :*).to_f] }

    cases.each do |x, want|
      got = self.class.kernel.call("tgamma", x)

      refute differs?(want, got, 0), "tgamma(#{x}) = #{got}, not #{want}"
    end
  end

  # musl's tgamma is up to 7 ulp from macOS's for x > 0, and its
  # reflection formula loses digits near the poles of x < 0, where it can
  # be 1000 ulp away.
  def test_tgamma_is_within_eight_ulp_of_macos_for_positive_x
    xs = gamma_values(28).select(&:positive?)

    check_unary("tgamma", xs, 8) { |x| self.class.host_libm("tgamma", 1).call(x) }
  end

  def test_tgamma_is_near_macos_for_negative_x
    gamma_values(29).select { |x| x.negative? && x.finite? && x != x.floor && x > -184 }.each do |x|
      want = self.class.host_libm("tgamma", 1).call(x)
      got = self.class.kernel.call("tgamma", x)

      if want.finite?
        assert_in_delta want, got, want.abs * 1.0e-9, "tgamma(#{x})"
      else
        refute differs?(want, got, 0), "tgamma(#{x}) = #{got}, not #{want}"
      end
    end
  end

  def test_lgamma_r_of_special_values_is_exact_with_its_sign
    [[0.0, INF, 1], [-0.0, INF, -1], [INF, INF, 1], [-INF, INF, 1], [1.0, 0.0, 1], [2.0, 0.0, 1], [-1.0, INF, 1], [-2.0, INF, 1],
     [-0.5, Math.log(2 * Math.sqrt(Math::PI)), -1], [3.0, Math.log(2.0), 1], [2.0**-80, 80 * Math.log(2.0), 1],
     [-(2.0**-80), 80 * Math.log(2.0), -1]].each do |x, want, want_sign|
      got, sign = lgamma_r(x)

      refute differs?(want, got, 1), "lgamma_r(#{x}) = #{got}, not #{want}"
      assert_equal want_sign, sign, "lgamma_r(#{x}) sign"
    end
    assert_predicate lgamma_r(NAN).first, :nan?
  end

  # musl's lgamma_r is up to 4 ulp from macOS's for x > 0 (macOS's
  # lgamma(1.5) is the one off there). Near the zeros of lgamma of x < 0
  # its error is absolute, not relative.
  def test_lgamma_r_is_within_four_ulp_of_macos_for_positive_x
    gamma_values(30).select { |x| x.positive? && x.finite? }.each do |x|
      want, want_sign = Math.lgamma(x)
      got, sign = lgamma_r(x)

      refute differs?(want, got, 4), "lgamma_r(#{x}) = #{got}, not #{want}"
      assert_equal want_sign, sign, "lgamma_r(#{x}) sign"
    end
  end

  def test_lgamma_r_is_near_macos_with_its_sign_for_negative_x
    gamma_values(31).select { |x| x.negative? && x.finite? && x != x.floor }.each do |x|
      want, want_sign = Math.lgamma(x)
      got, sign = lgamma_r(x)

      assert_in_delta want, got, [want.abs, 1.0].max * 1.0e-9, "lgamma_r(#{x})"
      assert_equal want_sign, sign, "lgamma_r(#{x}) sign"
    end
  end

  def test_fma_is_exact
    rng = Random.new(32)
    edges = [0.0, -0.0, INF, -INF, NAN, 1.0, -1.0, 5.0e-324, Float::MIN, Float::MAX, 1.0 + Float::EPSILON, 2.0**-537, 3.0]
    triples = edges.product(edges, edges) +
              Array.new(1500) { [random_double(rng), random_double(rng), random_double(rng)] } +
              Array.new(1500) do
                x = (rng.rand - 0.5) * 100
                y = (rng.rand - 0.5) * 100
                # z near -x*y: the sum cancels.
                [x, y, -(x * y) * (1 + ((rng.rand - 0.5) * 1.0e-14))]
              end +
              Array.new(1000) { [(rng.rand + 0.5) * 2.0**-520, (rng.rand + 0.5) * 2.0**-520, (rng.rand - 0.5) * 2.0**-1030] } +
              Array.new(500) { [(rng.rand + 0.5) * 2.0**512, (rng.rand + 0.5) * 2.0**511, -(rng.rand * Float::MAX)] } +
              [[2.0**-537, 2.0**-537, 0.0], [Float::MIN, 0.5, 0.0], [Float::MIN, 1.0 - Float::EPSILON / 2, 0.0],
               [Float::MIN, 1.0 - Float::EPSILON / 4, Float::MIN.prev_float * 0], [1.0 + Float::EPSILON, 1.0 - Float::EPSILON, -1.0],
               [Float::MAX, 2.0, -Float::MAX], [Float::MAX, 1.0 + Float::EPSILON, 0.0], [0.1, 10.0, -1.0]]
    fma = self.class.host_libm("fma", 3)
    bad = triples.filter_map do |x, y, z|
      want = fma.call(x, y, z)
      got = self.class.kernel.call("fma", x, y, z)
      "fma(#{x}, #{y}, #{z}) = #{got}, not #{want}" if differs?(want, got, 0)
    end

    assert_empty bad.first(10), "#{bad.size} of #{triples.size} differ"
  end

  private

  # Doubles of random bits: every exponent, both signs.
  def random_double(rng)
    loop do
      x = [rng.rand(2**64)].pack("Q").unpack1("D")
      return x if x.finite?
    end
  end

  def random_pairs(seed, n)
    rng = Random.new(seed)
    Array.new(n / 2) { [random_double(rng), random_double(rng)] } +
      Array.new(n / 2) { [(rng.rand - 0.5) * 2000, (rng.rand - 0.5) * 20] }
  end

# Whether `got` is not `want`. A zero, an infinity or NaN must be
# exact, its sign too; another result can be `max_ulps` away, because
# macOS's libm and musl's can round a transcendental function
# differently.
def differs?(want, got, max_ulps)
  return ulps(want, got) > max_ulps if max_ulps.positive? && want.finite? && !want.zero?

  !(want.nan? && got.nan?) && bits(want) != bits(got)
end

# The distance in ulps between two doubles; 0 for two NaNs.
  def ulps(a, b)
    return 0 if a.nan? && b.nan?
    return 2**64 if a.nan? || b.nan?

    (ordered(a) - ordered(b)).abs
  end

  def ordered(x)
    b = [x].pack("G").unpack1("q>")
    b.negative? ? -(b & 0x7FFF_FFFF_FFFF_FFFF) : b
  end

  def check_unary(name, xs, max_ulps)
    bad = xs.filter_map do |x|
      want = yield(x)
      got = self.class.kernel.call(name, x)
      "#{name}(#{x.inspect}) = #{got.inspect}, not #{want.inspect}" if differs?(want, got, max_ulps)
    end

    assert_empty bad.first(10), "#{bad.size} of #{xs.size} differ by more than #{max_ulps} ulp"
  end

  def check_binary(name, pairs, max_ulps)
    bad = pairs.filter_map do |x, y|
      want = yield(x, y)
      got = self.class.kernel.call(name, x, y)
      "#{name}(#{x.inspect}, #{y.inspect}) = #{got.inspect}, not #{want.inspect}" if differs?(want, got, max_ulps)
    end

    assert_empty bad.first(10), "#{bad.size} of #{pairs.size} differ by more than #{max_ulps} ulp"
  end

  # lgamma_r(x) and the sign that it stores.
  def lgamma_r(x)
    sign = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    value = self.class.kernel.call("lgamma_r", x, sign.to_i)
    [value, sign[0, 4].unpack1("l")]
  end

  def frexp(x)
    e = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
    m = self.class.kernel.call("frexp", x, e.to_i)
    [m, e[0, 4].unpack1("l")]
  end

  def c_string(text)
    buf = Fiddle::Pointer.malloc(text.bytesize + 1, Fiddle::RUBY_FREE)
    buf[0, text.bytesize + 1] = "#{text}\0"
    buf
  end

  # The value that strtod reads from `text`, and how many bytes it read.
  def strtod(text)
    buf = c_string(text)
    stop = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
    value = self.class.kernel.call("strtod", buf.to_i, stop.to_i)
    [value, stop[0, 8].unpack1("Q") - buf.to_i]
  end

  def assert_strtod(want, text, stop)
    got, read = strtod(text)

    assert_equal bits(want), bits(got), "strtod(#{text[0, 80].inspect}): #{got} for #{want}"
    assert_equal stop, read, "strtod(#{text[0, 80].inspect}) stop"
  end

  def bits(x) = [x].pack("G").unpack1("Q>")

  # The double nearest to the decimal `text`, from its exact value.
  # CRuby's Float drops the digits after a limit, so for a long text it
  # can round a value just above a halfway point down; C's strtod (musl,
  # darwin) does not.
  def exact_double(text) = nearest_double(text.to_r)

  # The double nearest to the rational `r`, rounded half to even.
  def nearest_double(r)
    return 0.0 if r.zero?
    return -nearest_double(-r) if r.negative?

    e = r.numerator.bit_length - r.denominator.bit_length
    e -= 1 while Rational(2)**e > r
    e += 1 while Rational(2)**(e + 1) <= r
    low = [e - 52, -1074].max
    q, rem = (r / (Rational(2)**low)).divmod(1)
    q += 1 if rem > Rational(1, 2) || (rem == Rational(1, 2) && q.odd?)
    Math.ldexp(q.to_f, low)
  end

  PI_TEXT = "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651" \
            "328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196"

  # tan(x) to about 2**-300, in fixed point: x less the nearest multiple
  # k of pi/2, then the Taylor series of sin and cos. For |x| up to about
  # 1e100, which the 200 digits of pi cover.
  def precise_tan(x)
    one = 2**300
    half_pi = (PI_TEXT.to_r * one / 2).round
    big = (x.to_r * one).round
    k = Rational(big, half_pi).round
    r = big - (k * half_pi)
    r2 = r * r / one
    sin = 0
    t = r
    i = 1
    until t.zero?
      sin += t
      t = -t * r2 / one / ((i + 1) * (i + 2))
      i += 2
    end
    cos = 0
    t = one
    i = 0
    until t.zero?
      cos += t
      t = -t * r2 / one / ((i + 1) * (i + 2))
      i += 2
    end
    nearest_double(k.odd? ? Rational(-cos, sin) : Rational(sin, cos))
  end

  # erf(x) * 2**1600, by its Taylor series: 2/sqrt(pi) times the sum of
  # (-1)**n x**(2n+1)/(n!(2n+1)). The series loses about x*x*1.44 bits, so
  # erfc(x) from it is precise for x up to about 8.
  def precise_erf(x)
    one = 2**1600
    sqrt_pi = Integer.sqrt((PI_TEXT.to_r * one * one).round)
    big = (x.to_r * one).round
    x2 = big * big / one
    term = big
    sum = 0
    n = 0
    until term.zero?
      sum += term / ((2 * n) + 1)
      n += 1
      term = -term * x2 / one / n
    end
    2 * sum * one / sqrt_pi
  end

  # The decimal text of the dyadic rational `r`, every digit exact.
  def exact_decimal(r)
    k = 0
    k += 1 until (r * (2**k)).denominator == 1
    digits = (r * (10**k)).to_i.to_s.rjust(k + 1, "0")
    k.zero? ? digits : "#{digits[0...-k]}.#{digits[-k..]}"
  end
end

# The same checks, with the kernel's Ruby run on CRuby (`Machine::Host`).
class WasiLibmHostTest < WasiLibmTest
  def self.kernel = @kernel ||= Zr::Harness::KernelHost.new(FILES)
end
