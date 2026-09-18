# frozen_string_literal: true

require "spec_helper"

describe "String: conversion" do
  it "conv to str duck" do
    result = ze0(<<~'RUBY')
      # to_str ducks at String-argument sites.
      class Sep
        def to_str
          "-"
        end
      end

      sep = Sep.new
      p "a" + sep
      p [1, 2, 3].join(sep)
      p "a-b".split(sep)
      p "a-b".index(sep)
      p "x".center(5, sep)
      p "a-b".start_with?(sep, "a")
      p "b-".end_with?(sep)
      s = +"a"
      s << sep
      p s
      p "a-b-c".sub(sep, "+")
      p "a-b".delete(sep)
      p "a-b-c".count(sep)
    RUBY

    _(result).must_answer <<~'OUT'
      "a-"
      "1-2-3"
      ["a", "b"]
      1
      "--x--"
      true
      true
      "a-"
      "a+b-c"
      "ab"
      2
    OUT
  end

  it "hash str value poly coerce" do
    result = ze0(<<~'RUBY')
      # Storing a poly value (one that holds a String/Integer at runtime) into a
      # typed-value hash (Hash[String,String] / Hash[String,Integer]) must coerce the
      # poly to the hash's value representation -- the setter takes const char* /
      # mrb_int, not sp_RbVal. The receiver is a method-return hash (its value type is
      # fixed by the body, so an external poly store can't re-widen it to a poly hash).

      def fresh_strs
        h = {}
        h["seed"] = "x"
        h            # Hash[String, String]
      end

      def fresh_ints
        h = {}
        h["seed"] = 0
        h            # Hash[String, Integer]
      end

      data = { "k" => "v", "n" => 5 }   # heterogeneous -> poly values

      # expression position: a poly string value into a Hash[String,String]
      puts(fresh_strs["k"] = data["k"])   # "v"
      # expression position: a poly int value into a Hash[String,Integer]
      puts(fresh_ints["n"] = data["n"])   # 5

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      v
      5
      done
    OUT
  end

  it "mutable str into str array" do
    result = ze0(<<~'RUBY')
      # Pushing a mutable String builder (String.new + <<) into a str_array
      # must snapshot its buffer into a sweep-owned (0xfe) copy, not store the
      # sp_String pointer / alias its object-owned ->data buffer. The builder
      # is otherwise unreferenced after the push, so a GC collects it and frees
      # the buffer, leaving the array element dangling; the next mark walk
      # faults scanning it (the #1071 / #1314 use-after-free class). Pre-fix
      # this also emitted `sp_StrArray_push(arr, sp_String *)`, an
      # incompatible-pointer-type the -Werror test build rejects outright.

      # 1. `<<` (statement form) — many builders pushed under GC churn.
      arr = []
      i = 0
      while i < 4000
        s = String.new
        s << "item "
        s << i.to_s
        arr << s
        i = i + 1
      end
      puts arr.length                 #=> 4000
      puts arr[0]                     #=> item 0
      puts arr[4000 - 1]             #=> item 3999

      # 2. `push` (expression form).
      arr2 = []
      k = 0
      while k < 2000
        b = String.new
        b << "k="
        b << k.to_s
        arr2.push(b)
        k = k + 1
      end
      puts arr2.length                #=> 2000
      puts arr2[1000]                #=> k=1000

      # 3. Sum the lengths back (reads every element after GC).
      total = 0
      j = 0
      while j < arr.length
        total = total + arr[j].length
        j = j + 1
      end
      puts total                      #=> 34890

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      4000
      item 0
      item 3999
      2000
      k=1000
      34890
      done
    OUT
  end

  it "numeric coerce non numeric string" do
    result = ze0(<<~'RUBY')
      begin
        42.coerce("l")
      rescue ArgumentError => e
        p e.class
      end
      begin
        2.5.coerce("")
      rescue ArgumentError => e
        p e.class
      end
    RUBY

    _(result).must_answer "ArgumentError\nArgumentError\n"
  end

  it "to_f reads a bare leading or trailing dot" do
    result = ze0(<<~'RUBY')
      p ".5".to_f
      p "5.".to_f
      p "-.5".to_f
      p ".5e1".to_f
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      5.0
      -0.5
      5.0
    OUT
  end

  it "to_i honours an explicit base argument" do
    result = ze0(<<~'RUBY')
      # Issue #883: String#to_i with explicit base argument. Without the
      # fix, the base was silently dropped and the call returned 0 for
      # any non-decimal input.
      puts "ff".to_i(16)
      puts "1010".to_i(2)
      puts "777".to_i(8)
      puts "z".to_i(36)
      puts "-ff".to_i(16)
      puts "1_0".to_i(16)
    RUBY

    _(result).must_answer <<~'OUT'
      255
      10
      511
      35
      -255
      16
    OUT
  end

  it "to_i with a base accepts the matching literal prefix, and a sign before it" do
    result = ze0(<<~'RUBY')
      p "0x1f".to_i(16)
      p "-0x1f".to_i(16)
      p "-1f".to_i(16)
      p "0b11".to_i(2)
    RUBY

    _(result).must_answer <<~'OUT'
      31
      -31
      -31
      3
    OUT
  end

  it "to_i(0) takes the base from the literal prefix" do
    result = ze0(<<~'RUBY')
      # String#to_i(0) auto-detects the base from the literal prefix.
      puts "0xff".to_i(0)
      puts "0b10".to_i(0)
      puts "0777".to_i(0)
      puts "0o755".to_i(0)
      puts "42".to_i(0)         # no prefix → decimal
      # Sign handling.
      puts "-0xff".to_i(0)
      puts "+0b101".to_i(0)
    RUBY

    _(result).must_answer <<~'OUT'
      255
      2
      511
      493
      42
      -255
      5
    OUT
  end

  it "to_i(0) reads 0x, 0b, 0o, a bare leading zero, and a sign" do
    result = ze0(<<~'RUBY')
      puts "0xff".to_i(0)
      puts "0b101".to_i(0)
      puts "0o755".to_i(0)
      puts "0777".to_i(0)
      puts "42".to_i(0)
      puts "-0xff".to_i(0)
      puts "+0b101".to_i(0)
    RUBY

    _(result).must_answer <<~'OUT'
      255
      5
      493
      511
      42
      -255
      5
    OUT
  end

  it "symbol breadth and to proc" do
    result = ze0(<<~'RUBY')
      # Symbol Tier A + the `&:sym` block-argument conversion
      # (`Symbol#to_proc`), previously unsupported.

      p :b <=> :a
      p :hello.length
      p :a.succ
      p :HeLLo.downcase
      p :he.to_s
      p :he.inspect
      p :he.upcase
      p :he.capitalize
      p :he.empty?
      p :upcase.to_proc.call("hi")
      p [3, 1, 2].map(&:to_s)
      p ["b", "a"].map(&:upcase)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      :b
      :hello
      "he"
      ":he"
      :HE
      :He
      false
      "HI"
      ["3", "1", "2"]
      ["B", "A"]
    OUT
  end

  it "symbol to proc call" do
    result = ze0(<<~'RUBY')
      # Explicit Symbol#to_proc applied with a call: :sym.to_proc.call(recv, *args)
      # invokes the named method on the first argument. With the symbol and the call
      # site statically known, it lowers to an ordinary recv.sym(*args) method call.
      # (The &:sym block form is unaffected; a to_proc held in a variable is a
      # separate, still-unsupported case.)
      def ss(x); x; end   # string receiver (per-type helper avoids poly widening)
      def si(x); x; end   # integer receiver

      # a no-argument method on the receiver
      p :upcase.to_proc.call("hi")          # "HI"
      p :length.to_proc.call("hello")       # 5
      p :succ.to_proc.call(5)               # 6
      p :to_s.to_proc.call(42)              # "42"

      # a method that takes extra arguments (receiver first, then the rest)
      p :+.to_proc.call(2, 3)               # 5
      p :*.to_proc.call(3, 4)               # 12

      # the .() call shorthand lowers the same way
      p :downcase.to_proc.("HI")            # "hi"

      # receiver routed through a method parameter (runtime-typed path)
      p :upcase.to_proc.call(ss("world"))   # "WORLD"
      p :abs.to_proc.call(si(-7))           # 7

      # the &:sym block form still works
      p ["a", "b", "c"].map(&:upcase)       # ["A", "B", "C"]
    RUBY

    _(result).must_answer <<~'OUT'
      "HI"
      5
      6
      "42"
      5
      12
      "hi"
      "WORLD"
      7
      ["A", "B", "C"]
    OUT
  end

  it "symbol to proc forwards block" do
    result = ze0(<<~'RUBY')
      p :map.to_proc.call([1, 2]) { |x| x * 3 }
      p :each.to_proc.call([1, 2]) { |x| }
      p :select.to_proc.call([1, 2, 3]) { |x| x.odd? }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [1, 2]
      [1, 3]
    OUT
  end

  it "symbol to proc is lambda and hash values at uses default" do
    result = ze0(<<~'RUBY')
      # :name.to_proc.lambda? is true (CRuby). Hash#values_at routes each key
      # through [], so a missing key yields the hash's default, not bare nil.

      p :upcase.to_proc.lambda?
      p ["x", "y"].map(&:upcase)
      p Hash.new(0).values_at(:x, :y)
      p({ a: 1 }.values_at(:a, :z))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      ["X", "Y"]
      [0, 0]
      [1, nil]
    OUT
  end

  it "to i agrees with integer and the split forms agree" do
    result = ze0(<<~'RUBY')
      # to_i, Integer() and the split forms answer over the same texts as
      # ruby's: blanks, signs, underscores, prefixes, bases and separators
      # of every kind, and split with a block.
      texts = ["12", " 12", "12 ", "+12", "-12", "1_2", "1__2", "_12", "12_", "0x1f", "0b11", "0o17", "017", "0d19", "12abc", "abc", "", "  ", "\t\n12", "12\n", "9" * 25, "-" + "9" * 25, "1e3", "1.5", "٣"]
      texts.each { |t| print t.inspect, " ", t.to_i, " ", (Integer(t) rescue "err"), " ", t.to_i(16), " ", t.to_i(2), "\n" }
      lines = ["a,b,c", "a,,b", ",a,", "abc", "", "a b  c", " a b ", "a\tb\nc", "a--b--c", "日本語、テキスト"]
      seps = [",", "", " ", nil, "--", "、", /,/, /\s+/, /(,)/]
      lines.each do |l|
        seps.each do |s|
          [0, 2, -1].each do |limit|
            r = (s.nil? ? l.split : l.split(s, limit)) rescue $!.class
            print l.inspect, " ", s.inspect, " ", limit, " ", r.inspect, "\n"
          end
        end
      end
      out = []
      "a,b,c".split(",") { |piece| out << piece.upcase }
      p out, "a,b".split(",").map(&:frozen?), "a,b".split(",").map(&:encoding).uniq.size
      $; = "-"
      p "x-y".split
      $; = nil

    RUBY

    _(result).must_answer <<~'OUT'
      "12" 12 12 18 1
      " 12" 12 12 18 1
      "12 " 12 12 18 1
      "+12" 12 12 18 1
      "-12" -12 -12 -18 -1
      "1_2" 12 12 18 1
      "1__2" 1 err 1 1
      "_12" 0 err 0 0
      "12_" 12 err 18 1
      "0x1f" 0 31 31 0
      "0b11" 0 3 2833 3
      "0o17" 0 15 0 0
      "017" 17 15 23 1
      "0d19" 19 19 3353 0
      "12abc" 12 err 76476 1
      "abc" 0 err 2748 0
      "" 0 err 0 0
      "  " 0 err 0 0
      "\t\n12" 12 12 18 1
      "12\n" 12 12 18 1
      "9999999999999999999999999" 9999999999999999999999999 9999999999999999999999999 760590360136937640898021923225 0
      "-9999999999999999999999999" -9999999999999999999999999 -9999999999999999999999999 -760590360136937640898021923225 0
      "1e3" 1 err 483 1
      "1.5" 1 err 1 1
      "٣" 0 err 0 0
      "a,b,c" "," 0 ["a", "b", "c"]
      "a,b,c" "," 2 ["a", "b,c"]
      "a,b,c" "," -1 ["a", "b", "c"]
      "a,b,c" "" 0 ["a", ",", "b", ",", "c"]
      "a,b,c" "" 2 ["a", ",b,c"]
      "a,b,c" "" -1 ["a", ",", "b", ",", "c", ""]
      "a,b,c" " " 0 ["a,b,c"]
      "a,b,c" " " 2 ["a,b,c"]
      "a,b,c" " " -1 ["a,b,c"]
      "a,b,c" nil 0 ["a,b,c"]
      "a,b,c" nil 2 ["a,b,c"]
      "a,b,c" nil -1 ["a,b,c"]
      "a,b,c" "--" 0 ["a,b,c"]
      "a,b,c" "--" 2 ["a,b,c"]
      "a,b,c" "--" -1 ["a,b,c"]
      "a,b,c" "、" 0 ["a,b,c"]
      "a,b,c" "、" 2 ["a,b,c"]
      "a,b,c" "、" -1 ["a,b,c"]
      "a,b,c" /,/ 0 ["a", "b", "c"]
      "a,b,c" /,/ 2 ["a", "b,c"]
      "a,b,c" /,/ -1 ["a", "b", "c"]
      "a,b,c" /\s+/ 0 ["a,b,c"]
      "a,b,c" /\s+/ 2 ["a,b,c"]
      "a,b,c" /\s+/ -1 ["a,b,c"]
      "a,b,c" /(,)/ 0 ["a", ",", "b", ",", "c"]
      "a,b,c" /(,)/ 2 ["a", ",", "b,c"]
      "a,b,c" /(,)/ -1 ["a", ",", "b", ",", "c"]
      "a,,b" "," 0 ["a", "", "b"]
      "a,,b" "," 2 ["a", ",b"]
      "a,,b" "," -1 ["a", "", "b"]
      "a,,b" "" 0 ["a", ",", ",", "b"]
      "a,,b" "" 2 ["a", ",,b"]
      "a,,b" "" -1 ["a", ",", ",", "b", ""]
      "a,,b" " " 0 ["a,,b"]
      "a,,b" " " 2 ["a,,b"]
      "a,,b" " " -1 ["a,,b"]
      "a,,b" nil 0 ["a,,b"]
      "a,,b" nil 2 ["a,,b"]
      "a,,b" nil -1 ["a,,b"]
      "a,,b" "--" 0 ["a,,b"]
      "a,,b" "--" 2 ["a,,b"]
      "a,,b" "--" -1 ["a,,b"]
      "a,,b" "、" 0 ["a,,b"]
      "a,,b" "、" 2 ["a,,b"]
      "a,,b" "、" -1 ["a,,b"]
      "a,,b" /,/ 0 ["a", "", "b"]
      "a,,b" /,/ 2 ["a", ",b"]
      "a,,b" /,/ -1 ["a", "", "b"]
      "a,,b" /\s+/ 0 ["a,,b"]
      "a,,b" /\s+/ 2 ["a,,b"]
      "a,,b" /\s+/ -1 ["a,,b"]
      "a,,b" /(,)/ 0 ["a", ",", "", ",", "b"]
      "a,,b" /(,)/ 2 ["a", ",", ",b"]
      "a,,b" /(,)/ -1 ["a", ",", "", ",", "b"]
      ",a," "," 0 ["", "a"]
      ",a," "," 2 ["", "a,"]
      ",a," "," -1 ["", "a", ""]
      ",a," "" 0 [",", "a", ","]
      ",a," "" 2 [",", "a,"]
      ",a," "" -1 [",", "a", ",", ""]
      ",a," " " 0 [",a,"]
      ",a," " " 2 [",a,"]
      ",a," " " -1 [",a,"]
      ",a," nil 0 [",a,"]
      ",a," nil 2 [",a,"]
      ",a," nil -1 [",a,"]
      ",a," "--" 0 [",a,"]
      ",a," "--" 2 [",a,"]
      ",a," "--" -1 [",a,"]
      ",a," "、" 0 [",a,"]
      ",a," "、" 2 [",a,"]
      ",a," "、" -1 [",a,"]
      ",a," /,/ 0 ["", "a"]
      ",a," /,/ 2 ["", "a,"]
      ",a," /,/ -1 ["", "a", ""]
      ",a," /\s+/ 0 [",a,"]
      ",a," /\s+/ 2 [",a,"]
      ",a," /\s+/ -1 [",a,"]
      ",a," /(,)/ 0 ["", ",", "a", ","]
      ",a," /(,)/ 2 ["", ",", "a,"]
      ",a," /(,)/ -1 ["", ",", "a", ",", ""]
      "abc" "," 0 ["abc"]
      "abc" "," 2 ["abc"]
      "abc" "," -1 ["abc"]
      "abc" "" 0 ["a", "b", "c"]
      "abc" "" 2 ["a", "bc"]
      "abc" "" -1 ["a", "b", "c", ""]
      "abc" " " 0 ["abc"]
      "abc" " " 2 ["abc"]
      "abc" " " -1 ["abc"]
      "abc" nil 0 ["abc"]
      "abc" nil 2 ["abc"]
      "abc" nil -1 ["abc"]
      "abc" "--" 0 ["abc"]
      "abc" "--" 2 ["abc"]
      "abc" "--" -1 ["abc"]
      "abc" "、" 0 ["abc"]
      "abc" "、" 2 ["abc"]
      "abc" "、" -1 ["abc"]
      "abc" /,/ 0 ["abc"]
      "abc" /,/ 2 ["abc"]
      "abc" /,/ -1 ["abc"]
      "abc" /\s+/ 0 ["abc"]
      "abc" /\s+/ 2 ["abc"]
      "abc" /\s+/ -1 ["abc"]
      "abc" /(,)/ 0 ["abc"]
      "abc" /(,)/ 2 ["abc"]
      "abc" /(,)/ -1 ["abc"]
      "" "," 0 []
      "" "," 2 []
      "" "," -1 []
      "" "" 0 []
      "" "" 2 []
      "" "" -1 []
      "" " " 0 []
      "" " " 2 []
      "" " " -1 []
      "" nil 0 []
      "" nil 2 []
      "" nil -1 []
      "" "--" 0 []
      "" "--" 2 []
      "" "--" -1 []
      "" "、" 0 []
      "" "、" 2 []
      "" "、" -1 []
      "" /,/ 0 []
      "" /,/ 2 []
      "" /,/ -1 []
      "" /\s+/ 0 []
      "" /\s+/ 2 []
      "" /\s+/ -1 []
      "" /(,)/ 0 []
      "" /(,)/ 2 []
      "" /(,)/ -1 []
      "a b  c" "," 0 ["a b  c"]
      "a b  c" "," 2 ["a b  c"]
      "a b  c" "," -1 ["a b  c"]
      "a b  c" "" 0 ["a", " ", "b", " ", " ", "c"]
      "a b  c" "" 2 ["a", " b  c"]
      "a b  c" "" -1 ["a", " ", "b", " ", " ", "c", ""]
      "a b  c" " " 0 ["a", "b", "c"]
      "a b  c" " " 2 ["a", "b  c"]
      "a b  c" " " -1 ["a", "b", "c"]
      "a b  c" nil 0 ["a", "b", "c"]
      "a b  c" nil 2 ["a", "b", "c"]
      "a b  c" nil -1 ["a", "b", "c"]
      "a b  c" "--" 0 ["a b  c"]
      "a b  c" "--" 2 ["a b  c"]
      "a b  c" "--" -1 ["a b  c"]
      "a b  c" "、" 0 ["a b  c"]
      "a b  c" "、" 2 ["a b  c"]
      "a b  c" "、" -1 ["a b  c"]
      "a b  c" /,/ 0 ["a b  c"]
      "a b  c" /,/ 2 ["a b  c"]
      "a b  c" /,/ -1 ["a b  c"]
      "a b  c" /\s+/ 0 ["a", "b", "c"]
      "a b  c" /\s+/ 2 ["a", "b  c"]
      "a b  c" /\s+/ -1 ["a", "b", "c"]
      "a b  c" /(,)/ 0 ["a b  c"]
      "a b  c" /(,)/ 2 ["a b  c"]
      "a b  c" /(,)/ -1 ["a b  c"]
      " a b " "," 0 [" a b "]
      " a b " "," 2 [" a b "]
      " a b " "," -1 [" a b "]
      " a b " "" 0 [" ", "a", " ", "b", " "]
      " a b " "" 2 [" ", "a b "]
      " a b " "" -1 [" ", "a", " ", "b", " ", ""]
      " a b " " " 0 ["a", "b"]
      " a b " " " 2 ["a", "b "]
      " a b " " " -1 ["a", "b", ""]
      " a b " nil 0 ["a", "b"]
      " a b " nil 2 ["a", "b"]
      " a b " nil -1 ["a", "b"]
      " a b " "--" 0 [" a b "]
      " a b " "--" 2 [" a b "]
      " a b " "--" -1 [" a b "]
      " a b " "、" 0 [" a b "]
      " a b " "、" 2 [" a b "]
      " a b " "、" -1 [" a b "]
      " a b " /,/ 0 [" a b "]
      " a b " /,/ 2 [" a b "]
      " a b " /,/ -1 [" a b "]
      " a b " /\s+/ 0 ["", "a", "b"]
      " a b " /\s+/ 2 ["", "a b "]
      " a b " /\s+/ -1 ["", "a", "b", ""]
      " a b " /(,)/ 0 [" a b "]
      " a b " /(,)/ 2 [" a b "]
      " a b " /(,)/ -1 [" a b "]
      "a\tb\nc" "," 0 ["a\tb\nc"]
      "a\tb\nc" "," 2 ["a\tb\nc"]
      "a\tb\nc" "," -1 ["a\tb\nc"]
      "a\tb\nc" "" 0 ["a", "\t", "b", "\n", "c"]
      "a\tb\nc" "" 2 ["a", "\tb\nc"]
      "a\tb\nc" "" -1 ["a", "\t", "b", "\n", "c", ""]
      "a\tb\nc" " " 0 ["a", "b", "c"]
      "a\tb\nc" " " 2 ["a", "b\nc"]
      "a\tb\nc" " " -1 ["a", "b", "c"]
      "a\tb\nc" nil 0 ["a", "b", "c"]
      "a\tb\nc" nil 2 ["a", "b", "c"]
      "a\tb\nc" nil -1 ["a", "b", "c"]
      "a\tb\nc" "--" 0 ["a\tb\nc"]
      "a\tb\nc" "--" 2 ["a\tb\nc"]
      "a\tb\nc" "--" -1 ["a\tb\nc"]
      "a\tb\nc" "、" 0 ["a\tb\nc"]
      "a\tb\nc" "、" 2 ["a\tb\nc"]
      "a\tb\nc" "、" -1 ["a\tb\nc"]
      "a\tb\nc" /,/ 0 ["a\tb\nc"]
      "a\tb\nc" /,/ 2 ["a\tb\nc"]
      "a\tb\nc" /,/ -1 ["a\tb\nc"]
      "a\tb\nc" /\s+/ 0 ["a", "b", "c"]
      "a\tb\nc" /\s+/ 2 ["a", "b\nc"]
      "a\tb\nc" /\s+/ -1 ["a", "b", "c"]
      "a\tb\nc" /(,)/ 0 ["a\tb\nc"]
      "a\tb\nc" /(,)/ 2 ["a\tb\nc"]
      "a\tb\nc" /(,)/ -1 ["a\tb\nc"]
      "a--b--c" "," 0 ["a--b--c"]
      "a--b--c" "," 2 ["a--b--c"]
      "a--b--c" "," -1 ["a--b--c"]
      "a--b--c" "" 0 ["a", "-", "-", "b", "-", "-", "c"]
      "a--b--c" "" 2 ["a", "--b--c"]
      "a--b--c" "" -1 ["a", "-", "-", "b", "-", "-", "c", ""]
      "a--b--c" " " 0 ["a--b--c"]
      "a--b--c" " " 2 ["a--b--c"]
      "a--b--c" " " -1 ["a--b--c"]
      "a--b--c" nil 0 ["a--b--c"]
      "a--b--c" nil 2 ["a--b--c"]
      "a--b--c" nil -1 ["a--b--c"]
      "a--b--c" "--" 0 ["a", "b", "c"]
      "a--b--c" "--" 2 ["a", "b--c"]
      "a--b--c" "--" -1 ["a", "b", "c"]
      "a--b--c" "、" 0 ["a--b--c"]
      "a--b--c" "、" 2 ["a--b--c"]
      "a--b--c" "、" -1 ["a--b--c"]
      "a--b--c" /,/ 0 ["a--b--c"]
      "a--b--c" /,/ 2 ["a--b--c"]
      "a--b--c" /,/ -1 ["a--b--c"]
      "a--b--c" /\s+/ 0 ["a--b--c"]
      "a--b--c" /\s+/ 2 ["a--b--c"]
      "a--b--c" /\s+/ -1 ["a--b--c"]
      "a--b--c" /(,)/ 0 ["a--b--c"]
      "a--b--c" /(,)/ 2 ["a--b--c"]
      "a--b--c" /(,)/ -1 ["a--b--c"]
      "日本語、テキスト" "," 0 ["日本語、テキスト"]
      "日本語、テキスト" "," 2 ["日本語、テキスト"]
      "日本語、テキスト" "," -1 ["日本語、テキスト"]
      "日本語、テキスト" "" 0 ["日", "本", "語", "、", "テ", "キ", "ス", "ト"]
      "日本語、テキスト" "" 2 ["日", "本語、テキスト"]
      "日本語、テキスト" "" -1 ["日", "本", "語", "、", "テ", "キ", "ス", "ト", ""]
      "日本語、テキスト" " " 0 ["日本語、テキスト"]
      "日本語、テキスト" " " 2 ["日本語、テキスト"]
      "日本語、テキスト" " " -1 ["日本語、テキスト"]
      "日本語、テキスト" nil 0 ["日本語、テキスト"]
      "日本語、テキスト" nil 2 ["日本語、テキスト"]
      "日本語、テキスト" nil -1 ["日本語、テキスト"]
      "日本語、テキスト" "--" 0 ["日本語、テキスト"]
      "日本語、テキスト" "--" 2 ["日本語、テキスト"]
      "日本語、テキスト" "--" -1 ["日本語、テキスト"]
      "日本語、テキスト" "、" 0 ["日本語", "テキスト"]
      "日本語、テキスト" "、" 2 ["日本語", "テキスト"]
      "日本語、テキスト" "、" -1 ["日本語", "テキスト"]
      "日本語、テキスト" /,/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /,/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /,/ -1 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /\s+/ -1 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ 0 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ 2 ["日本語、テキスト"]
      "日本語、テキスト" /(,)/ -1 ["日本語、テキスト"]
      ["A", "B", "C"]
      [false, false]
      1
      ["x", "y"]
    OUT
  end

  it "to i and a string split scan bytes in the kernel" do
    result = ze0(<<~'RUBY')
      # String#to_i in base 10 and a split by a String read their bytes in
      # the kernel: the same answers as ruby's for blanks, signs,
      # underscores, a `0d` prefix, numbers past a fixnum, and for pieces
      # with limits, empty pieces, multibyte separators and encodings.
      p "42".to_i, " \t\n\v\f\r42".to_i, "-42".to_i, "+42".to_i, "4_2".to_i, "4__2".to_i, "_42".to_i, "42_".to_i, "42abc".to_i, "abc".to_i, "".to_i
      p "0d42".to_i, "-0d42".to_i, " 0D42".to_i, "00d42".to_i, "10d".to_i, "0_d5".to_i, "0d".to_i, "0x1f".to_i, "0b101".to_i, "0o17".to_i, "017".to_i
      p "9223372036854775807".to_i, "4611686018427387903".to_i, "4611686018427387904".to_i, "-4611686018427387904".to_i, "123456789012345678901234567890".to_i, "000000000000000000000042".to_i
      p "1e5".to_i, "1.9".to_i, " 42".to_i, "４２".to_i, "42\0".to_i, "\0 42".to_i, "1_000_000".to_i, "12".to_i(10), "12".to_i(16), "z".to_i(36)
      p "a,b,c".split(","), "a,,b,,".split(","), "a,,b,,".split(",", -1), "a,b,c".split(",", 2), "a,b,c".split(",", 1), ",a".split(","), "".split(","), ",".split(",")
      p "a--b--c".split("--"), "a--b".split("-"), "abc".split("abc"), "abcabc".split("abc", -1), "aXbXc".split("X", 0), "a b  c".split(" "), "a\tb".split("\t")
      p "héllo wörld".split("ö"), "日本語、テキスト、です".split("、"), "日本".split("本", -1), "ab".split("c"), "a,b".split(",", 3), "a,b,c,d".split(",", -2)
      p "a,b".split(",").map(&:encoding).uniq, "a,b".b.split(",").first.encoding, "x".encode("UTF-16LE").split("x".encode("UTF-16LE")).size
      p (("a,b".split("é".encode("ISO-8859-1"))) rescue $!.class), ("ab".split("\xff") rescue $!.class), "ab".split("b".b)
      p "a,b,c".split(",") { |piece| print piece.upcase, " " }, "csv,line,here".split(",").map(&:size)


    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      -42
      42
      42
      4
      0
      42
      42
      0
      0
      42
      -42
      42
      0
      10
      0
      0
      0
      0
      0
      17
      9223372036854775807
      4611686018427387903
      4611686018427387904
      -4611686018427387904
      123456789012345678901234567890
      42
      1
      1
      0
      0
      42
      0
      1000000
      12
      18
      35
      ["a", "b", "c"]
      ["a", "", "b"]
      ["a", "", "b", "", ""]
      ["a", "b,c"]
      ["a,b,c"]
      ["", "a"]
      []
      []
      ["a", "b", "c"]
      ["a", "", "b"]
      []
      ["", "", ""]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a", "b"]
      ["héllo w", "rld"]
      ["日本語", "テキスト", "です"]
      ["日", ""]
      ["ab"]
      ["a", "b"]
      ["a", "b", "c", "d"]
      [#<Encoding:UTF-8>]
      #<Encoding:BINARY (ASCII-8BIT)>
      0
      ["a,b"]
      ArgumentError
      ["a"]
      A B C "a,b,c"
      [3, 4, 4]
    OUT
  end
end
