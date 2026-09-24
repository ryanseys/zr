# frozen_string_literal: true

require "spec_helper"

describe "Integer programs" do
  it "arithmetic and compare" do
    result = zr(<<~'RUBY')
      puts 1 + 2
      puts 7 - 10
      puts 6 * 7
      puts 7 / 2
      puts -7 / 2
      puts 7 % 3
      puts 2 ** 10
      puts (1 + 2) * 3
      puts 1 < 2
      puts 2 < 1
      puts 3 <= 3
      puts 3 >= 4
      puts 5 == 5
      puts 5 == 6
      puts 1 == 1.0
      puts 1.5 < 2
      puts "a" == "a"
      puts "a" == "b"
      puts 2 > 1.5
    RUBY

    _(result).must_answer <<~'OUT'
      3
      -3
      42
      3
      -4
      1
      1024
      9
      true
      false
      true
      false
      true
      false
      true
      true
      true
      false
      true
    OUT
  end

  it "bignum math" do
    result = zr(<<~'RUBY')
      # Arbitrary-precision integers: the bignum library is linked and the results
      # are exact.
      puts (2**200).to_s
      puts (3**64) / 7
      puts 100.downto(1).reduce(:*).to_s.length
      puts (10**30 + 1) % 97
    RUBY

    _(result).must_answer <<~'OUT'
      1606938044258990275541962092341162602522202993782792835301376
      490526260041787497808264155611
      158
      86
    OUT
  end

  it "bit operators bignum bounds and float ids" do
    result = zr(<<~'RUBY')
      # A bit operator coerces as CRuby's bit_coerce does and names a Float
      # by inspect; upto and downto walk toward a Bignum bound; a Float's
      # object_id is an Integer whatever word it has.
      def t = yield rescue [$!.class, $!.message]

      p t { 1 & 1e300 }, t { 1 | 1e300 }, t { 1 ^ 2.5 }, t { 1 & 1.5 }, t { 1 & 2r }, t { (2**70) & 1.5 }
      p t { 1.upto(2**64) { break } }, t { n = 0; 5.upto(2**64) { |i| n = i; break if i > 7 }; n }, t { 3.downto(-(2**64)) { break :b } }
      p t { (2**64).downto(2**64 - 2).to_a }, t { 1.upto(-(2**64)).to_a }, t { 1.upto(2**64).size }, t { 5.downto(-(2**64)).first(2) }
      p t { 1e20.object_id.class }, t { x = 1e20; x.object_id == x.object_id }, t { 1e300.object_id.class }, t { y = 1e300; y.object_id == y.object_id }, t { 0.5.object_id.class }

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "1.0e+300 can't be coerced into Integer"]
      [TypeError, "1.0e+300 can't be coerced into Integer"]
      [TypeError, "2.5 can't be coerced into Integer"]
      [TypeError, "1.5 can't be coerced into Integer"]
      [TypeError, "Rational can't be coerced into Integer"]
      [TypeError, "1.5 can't be coerced into Integer"]
      nil
      8
      :b
      [18446744073709551616, 18446744073709551615, 18446744073709551614]
      []
      18446744073709551616
      [5, 4]
      Integer
      true
      Integer
      true
      Integer
    OUT
  end

  it "division by zero" do
    result = zr(<<~'RUBY', path: "zr/division_by_zero.rb")
      puts 6 / 3
      puts 6 / 0
    RUBY

    _(result).must_answer "2\n", stderr: <<~'ERR', status: 1
      zr/division_by_zero.rb:2:in 'Integer#/': divided by 0 (ZeroDivisionError)
      	from zr/division_by_zero.rb:2:in '<main>'
    ERR
  end

  it "overflow to bignum" do
    result = zr(<<~'RUBY')
      x = 9223372036854775807
      puts x + 1
      puts x * 2
      puts 0 - x - x
      puts x + 1 - 1
    RUBY

    _(result).must_answer <<~'OUT'
      9223372036854775808
      18446744073709551614
      -18446744073709551614
      9223372036854775807
    OUT
  end

  it "shift by 64 or more moves every bit" do
    result = zr(<<~'RUBY')
      # A shift count past the word moves every bit out; the machine's own
      # shift would take the count mod 64.
      p 5 << -64, -5 << -64, 5 << -63, -5 << -63, 5 << -62, 8 << -2, 1 << -1
      p 5 >> 64, -5 >> 64, 5 >> 63, -5 >> 62, 8 >> 2
      p 5 << -(2**70), -5 << -(2**70)

    RUBY

    _(result).must_answer <<~'OUT'
      0
      -1
      0
      -1
      0
      2
      0
      0
      -1
      0
      -1
      2
      0
      -1
    OUT
  end
end
