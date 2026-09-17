# frozen_string_literal: true

require "spec_helper"

describe "Array: conversion" do
  it "array chain no arg" do
    result = ze0(<<~'RUBY')
      # Array#chain with no argument: the eager .chain.to_a is just the receiver's
      # own elements.
      p([1, 2, 3].chain.to_a)
      p([1, 2].chain([3, 4]).to_a)
      p([1, 2].chain([3], [4, 5]).to_a)
      a = []
      p a.chain.to_a
      p(["x", "y"].chain.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      []
      ["x", "y"]
    OUT
  end

  it "array combination" do
    result = ze0(<<~'RUBY')
      # Array#combination(n) without a block materializes into the n-combinations via to_a.
      def s(x); x; end
      p s([1, 2, 3]).combination(2).to_a
      p s([1, 2, 3]).combination(1).to_a
      p s([1, 2, 3]).combination(3).to_a
      p s([1, 2, 3]).combination(0).to_a
      p s([1, 2, 3]).combination(4).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [1, 3], [2, 3]]
      [[1], [2], [3]]
      [[1, 2, 3]]
      [[]]
      []
    OUT
  end

  it "array flatten to ary" do
    result = ze0(<<~'RUBY')
      class Pair
        def to_ary = [1, 2]

        def inspect = "#<Pair>"
      end

      p [Pair.new].flatten
      p [Pair.new].flatten(1)
      p [[1, Pair.new]].flatten
      p [Pair.new].flatten!
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [1, 1, 2]
      [1, 2]
    OUT
  end

  it "array float conformance" do
    result = ze0(<<~'RUBY')
      # Array/Float/Integer conformance (KieranP #2295-2302)
      p([1.1, 1.1, 2.2].uniq)          # #2295 FloatArray#uniq
      p Array.new                       # #2296 bare Array.new as direct p arg
      a = []
      p a.sum(0.0)                      # #2297 empty array sum with Float init
      p([1, 2, 3].sum(0.5))             # poly-array Float-init sum
      p([2, 2].all?(2))                 # #2298 all? with a value pattern
      p([1, 2, 3].none?(4..9))          # #2299 none? with a Range pattern
      p([1, 5, 3].any?(4..9))           # any? Range pattern
      p(["ab", "cd"].none?(/a/))        # #2300 none? with a Regexp pattern
      p(["ab", "cd"].any?(/a/))         # any? Regexp pattern
      p((-0.0).abs)                     # #2301 Float#abs of negative zero
      p((0.0 * -1.0).magnitude)         # Float#magnitude negative zero
      p(5.downto(1.5).to_a)             # #2302 downto with a Float limit
      p(1.upto(3.5).to_a)               # upto with a Float limit
    RUBY

    _(result).must_answer <<~'OUT'
      [1.1, 2.2]
      []
      0.0
      6.5
      true
      true
      true
      false
      true
      0.0
      0.0
      [5, 4, 3, 2]
      [1, 2, 3]
    OUT
  end

  it "array permutation" do
    result = ze0(<<~'RUBY')
      # Array#permutation on integer arrays, mirroring combination: blockless returns
      # an array of the k-element permutations; the block form yields each one.
      p [1, 2, 3].permutation(2).to_a
      p [1, 2, 3].permutation.to_a          # argless = full-length permutations
      p [1, 2, 3].permutation(0).to_a       # one empty permutation
      p [1, 2].permutation(5).to_a          # k > length -> none
      p [1, 2, 3].permutation(2).map { |pr| pr.sum }
      acc = []
      [1, 2, 3].permutation(2) { |pr| acc << pr.sum }
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]
      [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]]
      [[]]
      []
      [3, 4, 3, 5, 4, 5]
      [3, 4, 3, 5, 4, 5]
    OUT
  end

  it "array to h pair check" do
    result = ze0(<<~'RUBY')
      # Array#to_h wants each element to be a two-element array. A longer or shorter
      # one is an ArgumentError and a non-array a TypeError; the extra elements were
      # simply dropped and a short one read a nil value.
      p(([[1,2,3]].to_h rescue $!.message))
      p(([[1]].to_h rescue $!.message))
      p(([[1,2],[3]].to_h rescue $!.message))
      p([[1,2],[3,4]].to_h)
      p([["a",1]].to_h)
      p([[:a,1],[:b,2]].to_h)
      p(([[1,2],3].to_h rescue $!.message))
    RUBY

    _(result).must_answer <<~'OUT'
      "wrong array length at 0 (expected 2, was 3)"
      "wrong array length at 0 (expected 2, was 1)"
      "wrong array length at 1 (expected 2, was 1)"
      {1 => 2, 3 => 4}
      {"a" => 1}
      {a: 1, b: 2}
      "wrong element type Integer at 1 (expected array)"
    OUT
  end

  it "conv to ary duck" do
    result = ze0(<<~'RUBY')
      # to_ary ducks at Array-argument sites.
      class Pair
        def to_ary
          [8, 9]
        end
      end

      pair = Pair.new
      p [1] + pair
      p [8, 1] & pair
      p [8, 1] - pair
      p [1] | pair
      p [1].concat(pair)
      p [1, 2].zip(pair)
      p [[1, 2], pair].transpose
      p [1].product(pair)
      p [1].replace(pair)
      p [8, 7].intersect?(pair)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 8, 9]
      [8]
      [1]
      [1, 8, 9]
      [1, 8, 9]
      [[1, 8], [2, 9]]
      [[1, 8], [2, 9]]
      [[1, 8], [1, 9]]
      [8, 9]
      true
    OUT
  end

  it "hash flatten depth" do
    result = ze0(<<~'RUBY')
      # Hash#flatten(depth): to_a.flatten(depth) semantics -- depth >= 2 expands
      # array values, 0 keeps the pairs, negative flattens completely (the
      # argless interleave keeps its fast arm).
      h = { a: [1, 2], b: 3 }
      p h.flatten
      p h.flatten(0)
      p h.flatten(1)
      p h.flatten(2)
      p h.flatten(-1)
      g = { x: [1, [2, 3]], y: 4 }
      p g.flatten(2)
      p g.flatten(3)
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, [1, 2], :b, 3]
      [[:a, [1, 2]], [:b, 3]]
      [:a, [1, 2], :b, 3]
      [:a, 1, 2, :b, 3]
      [:a, 1, 2, :b, 3]
      [:x, 1, [2, 3], :y, 4]
      [:x, 1, 2, 3, :y, 4]
    OUT
  end

  it "integer digits invalid radix" do
    result = ze0(<<~'RUBY')
      # Integer#digits validates its radix: a base below 2 raises ArgumentError (a
      # negative base gives "negative radix", 0 or 1 give "invalid radix N"), and a
      # negative receiver raises Math::DomainError. The radix was silently coerced to
      # 10 and a negative receiver silently made positive.
      def d(x, b); x.digits(b); end
      p d(123, 10)                       # [3, 2, 1]
      p d(123, 16)                       # [11, 7]

      begin; d(123, 1); rescue ArgumentError => e; puts e.message; end   # invalid radix 1
      begin; d(123, 0); rescue ArgumentError => e; puts e.message; end   # invalid radix 0
      begin; d(123, -5); rescue ArgumentError => e; puts e.message; end  # negative radix

      def dn(x); x.digits; end
      # A negative receiver raises Math::DomainError; assert the message (the class
      # renders under its flattened runtime name, a separate display item).
      begin; dn(-123); rescue => e; puts e.message; end                  # out of domain

      # The no-arg form still defaults to base 10.
      p dn(90)                           # [0, 9]
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 2, 1]
      [11, 7]
      invalid radix 1
      invalid radix 0
      negative radix
      out of domain
      [0, 9]
    OUT
  end
end
