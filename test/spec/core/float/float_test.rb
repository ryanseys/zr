# frozen_string_literal: true

require "spec_helper"

describe "Float programs" do
  it "parsing and shortest-round-trip printing both link into the binary" do
    result = zr(<<~'RUBY')
      # Float parsing and shortest-round-trip printing, both linked into the binary.
      puts 0.1 + 0.2
      puts 1.0 / 3
      puts 1e300 * 10
      puts (2.0**-1074)
      puts format("%.10f", Math::PI)
      puts "3.14159".to_f
    RUBY

    _(result).must_answer <<~'OUT'
      0.30000000000000004
      0.3333333333333333
      1.0e+301
      5.0e-324
      3.1415926536
      3.14159
    OUT
  end

  it "mixed Integer and Float arithmetic answers a Float, and inspect prints the shortest round trip" do
    result = zr(<<~'RUBY')
      puts 1.5 + 2
      puts 2 * 3.0
      puts 7.0 / 2
      puts 1 / 3.0
      puts 0.1 + 0.2
      puts 2.5 - 2.5
      p 1.0
      p 1e20
      p 1.0 / 3
    RUBY

    _(result).must_answer <<~'OUT'
      3.5
      6.0
      3.5
      0.3333333333333333
      0.30000000000000004
      0.0
      1.0
      1.0e+20
      0.3333333333333333
    OUT
  end

  it "int operand refuses what a c int cannot hold" do
    result = zr(<<~'RUBY')
      # A digits or exponent operand is a C int: CRuby's NUM2INT refuses one
      # past it by name instead of clamping it.
      def t = yield rescue [$!.class, $!.message]

      p t { 1.5.round(2**32) }, t { 1.5.round(-2**32) }, t { 1.5.round(2**70) }
      p t { 1.5.round(2**31 - 1) }, t { 1.5.round(-2**31) }, t { 1.25.round(1) }
      p t { Math.ldexp(1.0, 2**40) }, t { Math.ldexp(1.0, -2**40) }
      p t { Math.ldexp(1.0, 2**30) }, t { Math.ldexp(1.0, -2**30) }, t { Math.ldexp(3.0, 2) }

    RUBY

    _(result).must_answer <<~'OUT'
      [RangeError, "integer 4294967296 too big to convert to 'int'"]
      [RangeError, "integer -4294967296 too small to convert to 'int'"]
      [RangeError, "bignum too big to convert into 'long'"]
      1.5
      0
      1.3
      [RangeError, "integer 1099511627776 too big to convert to 'int'"]
      [RangeError, "integer -1099511627776 too small to convert to 'int'"]
      Infinity
      0.0
      12.0
    OUT
  end

  it "Float of a String with NUL or in UTF-16, and format in UTF-16" do
    result = zr(<<~'RUBY')
      def t
        p yield
      rescue ArgumentError, EncodingError => e
        puts "#{e.class}: #{e.message}"
      end
      t { Float("1.5\0") }
      t { Float("1.5\0", exception: false) }
      t { Float("1.5".encode("UTF-16LE")) }
      t { format("%s".encode("UTF-16LE"), "x") }
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: string for Float contains null byte
      nil
      Encoding::CompatibilityError: ASCII incompatible encoding: UTF-16LE
      Encoding::CompatibilityError: ASCII incompatible encoding: UTF-16LE
    OUT
  end
end
