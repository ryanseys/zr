# frozen_string_literal: true

require "spec_helper"

describe "String: arithmetic" do
  it "bigint to s is a heap string" do
    result = zr(<<~'RUBY')
      # Integer#to_s on a Bignum answers an ordinary String, with the correct
      # length, and a concat on it copies only its own bytes.
      #
      # Interleaving other allocation is the point: it changes what sits in
      # memory next to the string.

      big = 2**200
      noise = []

      s = big.to_s
      p s.length
      p s[0, 3]
      p s.bytesize

      # through concat, the shape that overran
      20.times do |i|
        noise.push("filler-#{i}-#{'x' * i}")
        t = (2**200 + i).to_s + "-" + (2**64 + i).to_s
        p t if i == 19
      end

      # the same value reached through the poly path (a container read is poly)
      mixed = [big, "s"]
      p mixed[0].to_s.length
      p mixed[0].to_s + "!"

      # a BigRational renders by concatenating two of these
      r = Rational(2**100, 3)
      p r.to_s
      p r.inspect

      # and the small-value fast path inside the same function
      p (2**64).to_s
      p (-(2**64)).to_s
      p noise.length
    RUBY

    _(result).must_answer <<~'OUT'
      61
      "160"
      61
      "1606938044258990275541962092341162602522202993782792835301395-18446744073709551635"
      61
      "1606938044258990275541962092341162602522202993782792835301376!"
      "1267650600228229401496703205376/3"
      "(1267650600228229401496703205376/3)"
      "18446744073709551616"
      "-18446744073709551616"
      20
    OUT
  end

  it "float round half modes and string hash sub" do
    result = zr(<<~'RUBY')
      p 2.5.round(half: :even)
      p 3.5.round(half: :even)
      p 2.5.round(half: :down)
      puts "hello".sub("l", "l" => "X")
      puts "hello".gsub("l", "l" => "X")
      p 5 << 2.0
      p 100 >> 1.9
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      2
      heXlo
      heXXo
      20
      50
    OUT
  end

  it "str to i overflow" do
    result = zr(<<~'RUBY')
      # String#to_i past the int64 range gives a Bignum. It does not raise,
      # and it does not stop at INT64_MAX or INT64_MIN.

      # Below int64 limit: unchanged.
      puts "12345".to_i
      puts "-67890".to_i

      # Past int64 max: a Bignum, so the rescue does not run.
      begin
        puts "99999999999999999999999999999".to_i
      rescue RangeError
        puts "raised"
      end

      begin
        puts "-99999999999999999999999999999".to_i
      rescue RangeError
        puts "raised"
      end

      # Exactly INT64_MAX: parses fine, no raise.
      puts "9_223_372_036_854_775_807".to_i

      # One past INT64_MAX: a Bignum.
      begin
        puts "9_223_372_036_854_775_808".to_i
      rescue RangeError
        puts "raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      12345
      -67890
      99999999999999999999999999999
      -99999999999999999999999999999
      9223372036854775807
      9223372036854775808
    OUT
  end

  it "* with a huge count raises before it allocates, and a negative count raises too" do
    result = zr(<<~'RUBY')
      # String * <huge> raises ArgumentError and does not crash.
      #
      # The receiver is 1000 bytes, not 1, so `len * times` overflows the size check
      # and raises before anything is allocated. A 1-byte receiver takes the ALLOCATE
      # path instead: ruby 4.0.6 answers NoMemoryError there, and which of the two
      # NoMemoryError messages it picks depends on the machine -- a golden that
      # travels has to stay on the arithmetic side of the guard.
      begin
        puts ("x" * 1000) * (1 << 60)
      rescue ArgumentError => e
        puts "huge: " + e.message
      end
      begin
        puts "x" * -1
      rescue ArgumentError => e
        puts "neg: " + e.message
      end
      puts "ab" * 3
      puts ("hi" * 0).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      huge: argument too big
      neg: negative argument
      ababab
      ""
    OUT
  end

  it "+@ answers a mutable copy, concat and []= mutate in place, and -@ answers the string unchanged" do
    result = zr(<<~'RUBY')
      # Unary +@ on a string returns a mutable copy (so a literal can be built up),
      # and concat / []= mutate a mutable string local in place (statement position,
      # like the existing <</upcase!). -@ returns the string unchanged.

      # +"..." yields a mutable string; appends build it up
      s = +"abc"
      s << "d"
      p s
      s.concat("ef")
      p s
      s.concat("g", "h", "i")
      p s
      s.concat(33)            # an Integer appends its codepoint
      p s

      # build-in-a-loop starting from +""
      acc = +""
      3.times { |i| acc << i.to_s }
      p acc

      # in-place bang methods on a +string
      u = +"Hello"
      u.upcase!
      p u
      u.reverse!
      p u

      # []= single-index assignment (negative index counts from the end; the value
      # may be longer than one character)
      t = +"abcde"
      t[0] = "X"
      p t
      t[-1] = "Z"
      p t
      t[2] = "YY"
      p t
      # index == length appends (matches CRuby); out-of-range raises IndexError
      # carrying the original index
      g = +"abc"
      g[3] = "d"
      p g
      oob = +"abc"
      begin; oob[5] = "x"; rescue IndexError => e; puts "#{e.class}: #{e.message}"; end
      begin; oob[-4] = "x"; rescue IndexError => e; puts "#{e.class}: #{e.message}"; end

      # +@ / -@ as plain values
      p(+"plus")
      p(-"minus")

      # concat / []= also work on a dup'd string
      d = "orig".dup
      d.concat("!")
      d[0] = "O"
      p d
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      "abcdef"
      "abcdefghi"
      "abcdefghi!"
      "012"
      "HELLO"
      "OLLEH"
      "Xbcde"
      "XbcdZ"
      "XbYYdZ"
      "abcd"
      IndexError: index 5 out of string
      IndexError: index -4 out of string
      "plus"
      "minus"
      "Orig!"
    OUT
  end

  it "a + loop that touches only the string heap still drives a collection" do
    result = zr(<<~'RUBY')
      # A `String#+` loop allocates only strings, and no other objects. String
      # allocation alone must start a collection, so memory does not grow without
      # bound.
      #
      # Assert that a collection actually fires here: GC.stat["cycle"] counts
      # collections. If none runs, this prints "NO COLLECTION"; otherwise it
      # prints "collected".

      before = GC.stat["cycle"]
      s = ""
      i = 0
      while i < 50000
        s = s + "x"          # fresh result string each step; old s becomes garbage
        s = "" if s.length > 1000   # keep the live set tiny -- all the churn is collectable
        i += 1
      end
      after = GC.stat["cycle"]
      puts(after > before ? "collected" : "NO COLLECTION")
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/string/arithmetic_test.rb:18:in '<main>': undefined method '>' for nil (NoMethodError)

      puts(after > before ? "collected" : "NO COLLECTION")
                 ^
    ERR
  end

  it "sum answers the byte checksum modulo 2 to the bits, and leaves it whole outside 0...64" do
    result = zr(<<~'RUBY')
      # String#sum(bits): byte checksum modulo 2**bits (default 16; <= 0 or
      # >= 64 untruncated like CRuby).
      puts "hello".sum(8)
      p "abc".sum
      p "hello".sum(0)
      p "hi".sum(64)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      294
      532
      209
    OUT
  end

  it "to_i and Integer() give a Bignum past int64" do
    result = zr(<<~'RUBY')
      # String#to_i and Integer() on input past the int64 range give a
      # Bignum. They do not raise RangeError, and they do not saturate.

      begin
        "99999999999999999999".to_i
        puts "no exception"
      rescue RangeError
        puts "to_i raised RangeError"
      end

      begin
        "ffffffffffffffff0".to_i(16)
        puts "no exception"
      rescue RangeError
        puts "to_i(16) raised RangeError"
      end

      begin
        Integer("99999999999999999999")
        puts "no exception"
      rescue RangeError
        puts "Integer raised RangeError"
      end

      # In-range values still work.
      puts "42".to_i
      puts "ff".to_i(16)
      puts Integer("-1000")
    RUBY

    _(result).must_answer <<~'OUT'
      no exception
      no exception
      no exception
      42
      255
      -1000
    OUT
  end
end
