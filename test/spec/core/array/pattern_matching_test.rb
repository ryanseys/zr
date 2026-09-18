# frozen_string_literal: true

require "spec_helper"

describe "Array: pattern matching" do
  it "first, last, take, drop and the deconstruct rows answer on an empty array too" do
    result = ze0(<<~'RUBY')
      # Array/Comparable conformance (KieranP #2287,#2289-2294)
      class Ver
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      p(Ver.new(5).respond_to?(:<))       # #2287 Comparable-mixin operators
      p(Ver.new(5).respond_to?(:between?))
      p([] + [1])                         # #2289 empty array literal operand
      p([1] + [])
      p([] - [1])
      p([1, "a", 2] - ["a"])              # #2290 different element types
      p([1, 2] - [2, "a"])
      p([1, 2] & [2, 3])
      p([1, 2] | ["a"])
      p([].push(1))                       # #2291 mutate empty literal directly
      p([] << 5)
      p([1, 2].unshift(nil))              # #2292 unshift nil into a numeric array
      p([1.1, 2.2].unshift(nil))
      p([1, 2].unshift(nil, nil))
      p([1.1, 2.2].include?(2.2))         # #2293 Float array include?
      p([1.1, 2.2].include?(9.9))
      p([].nil?)                          # #2294 nil? on an empty array literal
      p([].empty?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [1]
      [1]
      []
      [1, 2]
      [1]
      [2]
      [1, 2, "a"]
      [1]
      [5]
      [nil, 1, 2]
      [nil, 1.1, 2.2]
      [nil, nil, 1, 2]
      true
      false
      false
      true
    OUT
  end

  it "a case/in array pattern checks the required element values, not only the length" do
    result = ze0(<<~'RUBY')
      # A case/in array pattern must check required element values, not only length.
      def si(x); x; end
      def ss(x); x; end

      r1 = case si([1, 2, 3])
           in [9, *] then "matched"
           else "no"
           end
      p r1                       # "no" -- head 1 != 9

      r2 = case si([1, 2, 3])
           in [1, *] then "matched"
           else "no"
           end
      p r2                       # "matched" -- head 1 == 1

      r3 = case si([1, 2, 3])
           in [1, 2, 3] then "exact"
           in [1, 2, x] then "prefix"
           else "no"
           end
      p r3                       # "exact"

      r4 = case si([1, 2, 9])
           in [1, 2, 3] then "exact"
           in [1, 2, x] then "bound #{x}"
           else "no"
           end
      p r4                       # "bound 9" -- falls to the binding clause, binds x

      r5 = case si([1, 2, 3])
           in [1, b, 3] then "mid #{b}"
           else "no"
           end
      p r5                       # "mid 2" -- literal ends match, middle binds

      r6 = case si([1, 2, 3])
           in [1, b, 9] then "mid #{b}"
           else "no"
           end
      p r6                       # "no" -- trailing literal 9 != 3

      r7 = case ss(["x", "y"])
           in ["x", *] then "x-head"
           else "no"
           end
      p r7                       # "x-head"

      r8 = case ss(["x", "y"])
           in ["z", *] then "z-head"
           else "no"
           end
      p r8                       # "no" -- "x" != "z"
    RUBY

    _(result).must_answer <<~'OUT'
      "no"
      "matched"
      "exact"
      "bound 9"
      "mid 2"
      "no"
      "x-head"
      "no"
    OUT
  end

  it "a case/in array pattern reads a poly scrutinee's length and elements through the poly path" do
    result = ze0(<<~'RUBY')
      # A case/in array pattern over a poly-typed scrutinee must read its length and
      # elements through the poly path (sp_poly_length / sp_poly_index_poly behind a
      # tag guard), never `->len` on a bare value. One helper fed several element
      # kinds keeps the scrutinee poly so the typed-array fast path never applies.
      def s(x); x; end

      def head1?(v)
        case s(v)
        in [1, *] then "one-head"
        else "no"
        end
      end
      p head1?([1, 2, 3])     # "one-head"
      p head1?([9, 2, 3])     # "no" -- head 9 != 1
      p head1?(["a", "b"])    # "no" -- string array, head != 1
      p head1?([1])           # "one-head" -- the rest may be empty

      def exact?(v)
        case s(v)
        in [1, 2, 3] then "exact"
        in [1, 2, x] then "prefix #{x}"
        else "no"
        end
      end
      p exact?([1, 2, 3])     # "exact"
      p exact?([1, 2, 9])     # "prefix 9"
      p exact?(["a", "b"])    # "no"

      def nested?(v)
        case s(v)
        in [1, [2, 3], 4] then "nested"
        else "no"
        end
      end
      p nested?([1, [2, 3], 4])   # "nested"
      p nested?([1, [2, 9], 4])   # "no" -- inner trailing 9 != 3
      p nested?([1, 2, 4])        # "no" -- middle element is not a sub-array

      def nonarray?(v)
        case s(v)
        in [1, *] then "arr"
        else "no"
        end
      end
      p nonarray?(5)          # "no" -- a poly scrutinee that is not an array
      p nonarray?([1, 2])     # "arr"
    RUBY

    _(result).must_answer <<~'OUT'
      "one-head"
      "no"
      "no"
      "one-head"
      "exact"
      "prefix 9"
      "no"
      "nested"
      "no"
      "no"
      "no"
      "arr"
    OUT
  end

  it "a trailing comma in an array pattern is an implicit rest" do
    result = ze0(<<~'RUBY')
      case [0, 1, 2, 3]
      in [0, 1, ] then puts "matched"
      else puts "no"
      end
      case [5]
      in [0, 1, ] then puts "wrong"
      else puts "too short"
      end
    RUBY

    _(result).must_answer "matched\ntoo short\n"
  end

  it "case in array pattern binds pre and rest" do
    result = ze0(<<~'RUBY')
      case [1, 2, 3]
      in [Integer => a, *rest]
        puts a
        puts rest.length
      end
    RUBY

    _(result).must_answer "1\n2\n"
  end

  it "case in array pattern pre and post splat" do
    result = ze0(<<~'RUBY')
      case [1, 2, 3, 4, 5]
      in [*pre, 3, *post]
        puts pre.length
        puts post.length
      end
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "case in nested array" do
    result = ze0(<<~'RUBY')
      # A nested array pattern in `case/in` (`in [a, [b, c], d]`) destructures the
      # sub-array element, binding its inner targets, and matches only when the
      # element is itself a correctly-shaped array. Previously the nested element was
      # skipped (inner targets bound nil) and matched on outer length alone.
      # Each scrutinee routes through its own method param (so the runtime path runs);
      # separate helpers keep each param type concrete and avoid cross-case widening.

      # nested match
      def n1(x); x; end
      case n1([1, [2, 3], 4])
      in [a, [b, c], d] then p [a, b, c, d]      # [1, 2, 3, 4]
      end

      # middle is the wrong length -> no match
      def n2(x); x; end
      case n2([1, [2], 4])
      in [a, [b, c], d] then p :y
      else p :no                                  # :no
      end

      # a typed int array can never match a nested-array pattern -> no match
      def n3(x); x; end
      case n3([1, 5, 4])
      in [a, [b, c], d] then p :y
      else p :no                                  # :no
      end

      # deeply nested
      def n4(x); x; end
      case n4([1, [2, [3, 4]]])
      in [a, [b, [c, d]]] then p [a, b, c, d]     # [1, 2, 3, 4]
      end

      # nested + trailing rest
      def n5(x); x; end
      case n5([1, [2, 3], 4, 5])
      in [a, [b, c], *r] then p [a, b, c, r]      # [1, 2, 3, [4, 5]]
      end

      # nested capture: bind the whole sub-array and its parts
      def n6(x); x; end
      case n6([1, [2, 3]])
      in [a, [b, c] => pair] then p [a, b, c, pair]  # [1, 2, 3, [2, 3]]
      end

      # string sub-array as the first element
      def n7(x); x; end
      case n7([["a", "b"], 1])
      in [[x, y], z] then p [x, y, z]             # ["a", "b", 1]
      end

      # flat pattern still works (regression)
      def n8(x); x; end
      case n8([1, "two", 3])
      in [a, b, c] then p [a, b, c]               # [1, "two", 3]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      :no
      :no
      [1, 2, 3, 4]
      [1, 2, 3, [4, 5]]
      [1, 2, 3, [2, 3]]
      ["a", "b", 1]
      [1, "two", 3]
    OUT
  end

  it "case in object deconstruct dispatches to array pattern" do
    result = ze0(<<~'RUBY')
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
        def deconstruct
          [@x, @y]
        end
      end
      p1 = Point.new(1, 2)
      case p1
      in [px, py]
        puts "array: #{px}, #{py}"
      end
    RUBY

    _(result).must_answer "array: 1, 2\n"
  end

  it "deconstruct must return an array" do
    result = ze0(<<~'RUBY')
      # `deconstruct` must answer an Array and `deconstruct_keys` a Hash. A
      # wrong return RAISES -- it does not fall through to the next `in` clause.
      #
      # The value used to be waved through with `matched = 1` and only failed
      # one frame later, in an accessor that panics; that entry is `extern "C"`
      # and cannot unwind, so the panic ended the process instead of raising.
      # Checking where the value ARRIVES is the fix, and the rule behind it: an
      # accessor that panics may not be called from a non-unwinding boundary.

      bad_array = Class.new { def deconstruct = :not_array }
      begin
        case bad_array.new
        in [x]
          p x
        end
      rescue TypeError => e
        puts e.message
      end

      bad_hash = Class.new { def deconstruct_keys(_keys) = :not_hash }
      begin
        case bad_hash.new
        in { a: }
          p a
        end
      rescue TypeError => e
        puts e.message
      end

      # It raises rather than trying the next clause -- an `else` does not catch
      # it either.
      begin
        case bad_array.new
        in [x]
          p x
        in Object
          puts "fell through"
        end
      rescue TypeError => e
        puts e.message
      end

      # The working protocol is untouched, in both halves.
      class Pair
        def deconstruct = [1, 2]
        def deconstruct_keys(_keys) = { a: 1, b: 2 }
      end

      case Pair.new
      in [x, y]
        p [x, y]
      end
      case Pair.new
      in { a:, b: }
        p [a, b]
      end

      # A raising `deconstruct` propagates its own exception, not a TypeError.
      raiser = Class.new { def deconstruct = raise(ArgumentError, "from deconstruct") }
      begin
        case raiser.new
        in [_x]
          nil
        end
      rescue ArgumentError => e
        puts e.message
      end

      # An Array and a Hash still match directly, with no protocol call at all.
      case [1, 2]
      in [p1, p2]
        p [p1, p2]
      end
      case({ a: 1 })
      in { a: }
        p a
      end
    RUBY

    _(result).must_answer <<~'OUT'
      deconstruct must return Array
      deconstruct_keys must return Hash
      deconstruct must return Array
      [1, 2]
      [1, 2]
      from deconstruct
      [1, 2]
      1
    OUT
  end

  it "nested array pattern deconstruct" do
    result = ze0(<<~'RUBY')
      S001 = Struct.new(:a, :b)
      arr001 = [S001.new(1, 2)]
      r001 = (case arr001; in [S001[x001, y001]] then [x001, y001]; end rescue $!.class); p r001
      r002 = (case arr001; in [[p1, p2]] then [p1, p2]; end rescue $!.class); p r002
      r003 = (case S001.new(3, 4); in S001[u, v] then [u, v]; end rescue $!.class); p r003
      r004 = (case [[1, 2]]; in [[m, n]] then [m, n]; end rescue $!.class); p r004
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [3, 4]
      [1, 2]
    OUT
  end

  it "oneline in array" do
    result = ze0(<<~'RUBY')
      # One-line `expr in pattern` with an array pattern yields a boolean.
      def s(x); x; end
      a = (s([1, 2, 3]) in [1, *]);    p a
      b = (s([1, 2, 3]) in [1, 2, 3]); p b
      c = (s([1, 2, 3]) in [1, 2]);    p c
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
    OUT
  end

  it "struct values values at dig and filtered deconstruct keys" do
    result = ze0(<<~'RUBY')
      Point = Struct.new(:x, :y)
      p Point.new(3, 4).values
      p Point.new(3, 4).values_at(0, -1)
      Config = Struct.new(:name, :opts)
      c = Config.new("web", { port: 8080 })
      p c.dig(:opts, :port)
      p c.dig(:opts, :missing)
      S = Struct.new(:a, :b, :c)
      p S.new(1, 2, 3).deconstruct_keys([:a, :c])
      p S.new(1, 2, 3).deconstruct_keys([:z, :a])
      p S.new(1, 2, 3).deconstruct_keys([:a, :b, :c, :d])
      D = Data.define(:a, :b)
      p D.new(a: 1, b: 2).deconstruct_keys([:a])
      p D.new(a: 1, b: 2).deconstruct_keys(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [3, 4]
      8080
      nil
      {a: 1, c: 3}
      {}
      {}
      {a: 1}
      {a: 1, b: 2}
    OUT
  end
end
