# frozen_string_literal: true

require "spec_helper"

describe "Literals programs" do
  it "hash literal with a splat raises from a later keys hash" do
    result = ze0(<<~'RUBY')
      # A hash literal that carries `**` stores its other pairs one by one;
      # a key whose `hash` raises must raise from the literal, not leave the
      # literal with no value.
      k = Object.new
      def k.hash = raise("boom")
      begin
        p({**{}, k => 1})
      rescue => e
        p [e.class, e.message]
      end
      begin
        p({**{a: 1}, k => 1}.size)
      rescue => e
        p [e.class, e.message]
      end
      p({**{a: 1}, b: 2})

    RUBY

    _(result).must_answer <<~'OUT'
      [RuntimeError, "boom"]
      [RuntimeError, "boom"]
      {a: 1, b: 2}
    OUT
  end

  it "an interpolated pattern, a bignum and the exact numeric towers are built at run time" do
    result = ze0(<<~'RUBY', path: "ze0/literals.rb")
      # frozen_string_literal: true

      # The literals whose value only the RUN TIME can build: an interpolated
      # pattern or name, an Integer past the inline payload, and the two exact
      # numeric towers. `__FILE__` and `__LINE__` are the opposite -- both are
      # constants of the compile.

      part = "wor"
      p(/hello #{part}ld/ =~ "hello world")
      p(/#{part}/i.match?("WOR"))
      p(/a#{part}c/.source, /a#{part}c/i.options, /a#{part}c/mx.source)

      # The pattern is compiled every time, so a bad one raises where it
      # stands rather than at the compile.
      broken = "["
      begin
        /#{broken}/
      rescue RegexpError => e
        p e.class
      end

      p :"sym_#{part}", :"@#{part}", :"x#{1 + 1}y"
      p :"#{part}".class, :"#{part}" == :wor

      # An Integer past 64 bits is built from its baked digits, and the
      # runtime folds it back to the inline form whenever it fits.
      big = 123_456_789_012_345_678_901_234_567_890
      p big, big + 1, big * big, -big, big.class
      p 9_223_372_036_854_775_807, 9_223_372_036_854_775_808
      p(-9_223_372_036_854_775_808, -9_223_372_036_854_775_809)
      p 18_446_744_073_709_551_616 - 18_446_744_073_709_551_615
      p 0xffff_ffff_ffff_ffff_ffff

      # Prism pre-rationalizes the decimal form, so both arrive as a pair.
      p 1r, 3r, 1.5r, (-2r)
      p((3 / 4r), (3 / 4r) + 1r, 1.5r * 2, 1r.class)

      p 2i, 1.5i, (-4i), (3i + 4), (2i * 2i), 2i.class

      p File.basename(__FILE__), __LINE__
      p __ENCODING__

      def where = [File.basename(__FILE__), __LINE__]
      p where

      p defined?(__FILE__), defined?(__LINE__), defined?(__ENCODING__)
      p defined?(:"a#{1}"), defined?(/x#{1}/), defined?(1r), defined?(2i)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      "aworc"
      1
      "aworc"
      RegexpError
      :sym_wor
      :@wor
      :x2y
      Symbol
      true
      123456789012345678901234567890
      123456789012345678901234567891
      15241578753238836750495351562536198787501905199875019052100
      -123456789012345678901234567890
      Integer
      9223372036854775807
      9223372036854775808
      -9223372036854775808
      -9223372036854775809
      1
      1208925819614629174706175
      (1/1)
      (3/1)
      (3/2)
      (-2/1)
      (3/4)
      (7/4)
      (3/1)
      Rational
      (0+2i)
      (0+1.5i)
      (0-4i)
      (4+3i)
      (-4+0i)
      Complex
      "literals.rb"
      40
      #<Encoding:UTF-8>
      ["literals.rb", 43]
      "expression"
      "expression"
      "expression"
      "expression"
      "expression"
      "expression"
      "expression"
    OUT
  end

  it "range of integer literals is one frozen object per site" do
    result = ze0(<<~'RUBY')
      def ids = 3.times.map { yield.object_id }.uniq.size

      p ids { (1..2) }
      p ids { (1...2) }
      p ids { (1..) }
      p ids { (..-3) }
      p ids { (nil..nil) }
      p ids { (1..2**70) }
      p (1..2).frozen?, (1..2).equal?(1..2)

      x = 1
      p ids { (x..2) }
      p ids { ("a".."b") }
      p ids { (1.0..2) }
      p ids { (1..2.0) }
      p ids { (:a..:b) }

      def r = (3..4)
      p r.equal?(r)
      p Range.new(1, 2).frozen?, Range.new(1, 2).equal?(Range.new(1, 2))

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      1
      1
      3
      true
      false
      3
      3
      3
      3
      3
      true
      true
      false
    OUT
  end
end
