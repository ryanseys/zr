# frozen_string_literal: true

require "spec_helper"

describe "String: arithmetic" do
  it "bigint to s is a heap string" do
    result = ze0(<<~'RUBY')
      # Integer#to_s on a Bignum answers an ordinary String, so it must live on the
      # string heap with its marker byte.
      #
      # It used to be a bare malloc'd buffer. Nothing reads the byte before such a
      # chunk deliberately, but sp_str_byte_len does -- it is how every spinel string
      # reports its length -- so the length came out of whatever the allocator had
      # put there, and the next concat memcpy'd that many bytes. Under GC stress that
      # is a heap-buffer-overflow inside sp_str_concat; the visible symptom is a SEGV
      # in memcpy with a concat on the stack.
      #
      # Interleaving other allocation is the point: it decides what sits before the
      # chunk, which is what the misread length came from.

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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # String#to_i overflow handling. Pre-fix: undefined behavior on
      # int64 wrap (#743) — addressed by overflow-detected saturation.
      # Per #842 the saturate path is gone; overflow now raises
      # RangeError so a `rescue` can react instead of silently
      # returning INT64_MAX/MIN.

      # Below int64 limit: unchanged.
      puts "12345".to_i
      puts "-67890".to_i

      # At/over int64 max: raises RangeError.
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

      # One past INT64_MAX: raises.
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

  it "string multiply overflow" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # String#* overflow raises "string size too big"; ruby 4.0.6 says "argument
      # too big".
      #
      # Issue #836: String * <huge> raises ArgumentError instead of
      # segfaulting (the implicit malloc-NULL + memcpy chain).
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

  it "string mutation plus" do
    result = ze0(<<~'RUBY')
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

  it "string plus heap gc" do
    result = ze0(<<~'RUBY')
      # Regression for matz/spinel#1450. A `String#+` loop allocates only on the
      # string heap (no object-heap allocation), and before the fix the string heap
      # was swept only from sp_gc_collect, which fires on OBJECT-heap pressure
      # (sp_gc_bytes). So a string-only workload never collected and RSS grew without
      # bound. The fix drives collection off the string heap's own live-byte count.
      #
      # Assert that a collection actually fires here: GC.stat["cycle"] counts
      # sp_gc_collect runs, and since this loop never touches the object heap, the
      # ONLY thing that can advance it is the string-heap trigger. Pre-fix this prints
      # "NO COLLECTION"; post-fix it prints "collected".
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

    _(result).must_answer "", stderr: "core/string/arithmetic_test.rb:20:in '<main>': undefined method '>' for nil (NoMethodError)\n\nputs(after > before ? \"collected\" : \"NO COLLECTION\")\n           ^\n", status: 1
  end

  it "string sum bits" do
    result = ze0(<<~'RUBY')
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

  it "string to i overflow raises" do
    result = ze0(<<~'RUBY')
      # String#to_i / Integer() on input exceeding int64 raises
      # RangeError rather than saturating silently. spinel's int model
      # is int64-only, so the CRuby Bignum promotion path lowers to a
      # user-catchable RangeError.

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
