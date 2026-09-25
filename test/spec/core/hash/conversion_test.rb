# frozen_string_literal: true

require "spec_helper"

describe "Hash: conversion" do
  it "empty hash receiver call" do
    result = zr(<<~'RUBY')
      # A bare empty-hash literal as a receiver coerces to the same str-keyed poly
      # hash the emitter builds for {}, so direct calls dispatch.
      p({}.size)
      p({}.empty?)
      p({} == {})
      p [].size
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      true
      0
    OUT
  end

  it "an Integer-keyed, Integer-valued hash nests, boxes and reads back through a poly access" do
    result = zr(<<~'RUBY')
      # Integer-keyed Integer-valued hash: nesting, boxing, poly access
      p({ 1 => { 2 => 3 } })
      p({ 1 => { 2 => 3 }, 4 => { 5 => 6 } })
      p({ 1 => { 2 => 3 } }[1])
      h = { 1 => { 2 => 3 } }
      p h[1][2]
      a = [{ 1 => 2 }, { 3 => 4 }]
      p a
      p a[0][1]
      p a[1][3]
      p a[0][9]
      p({ 1 => 10, 2 => 20 }.is_a?(Hash))
      p({ 1 => 10, 2 => 20 }.to_a)
      p({ 1 => 10, 2 => 20 }.any?([1, 10]))
      p({ 1 => 10, 2 => 20 }.sort_by { |k, v| -v })
      p({ 1 => 10, 2 => 20 }.reduce(0) { |s, (k, v)| s + v })
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => {2 => 3}}
      {1 => {2 => 3}, 4 => {5 => 6}}
      {2 => 3}
      3
      [{1 => 2}, {3 => 4}]
      2
      4
      nil
      true
      [[1, 10], [2, 20]]
      true
      [[2, 20], [1, 10]]
      30
    OUT
  end

  it "method to proc curry stored" do
    result = zr(<<~'RUBY')
      # A Method stored in a local, then .to_proc.curry'd, still resolves the
      # target's arity/return through the assignment chain.
      def greet(a, b) = "#{a},#{b}"
      m = method(:greet)
      g = m.to_proc.curry
      p g["x"]["y"]
      h = method(:greet).to_proc.curry
      p h["a"]["b"]
    RUBY

    _(result).must_answer <<~'OUT'
      "x,y"
      "a,b"
    OUT
  end

  it "polypoly hash assoc to proc" do
    result = zr(<<~'RUBY')
      # A Hash with keys and values of any type: Hash#assoc and #rassoc read the
      # right entry, and Hash#to_proc looks up the key it gets as an argument.

      # a default-proc hash is PolyPoly; assoc/rassoc
      h = Hash.new { |hh, k| hh[k] = 42 }
      h.merge!(foo: :bar)
      p h.assoc(:foo)
      p h.assoc(42)
      p h.rassoc(:bar)

      # heterogeneous-key hash to_proc
      g = { 1 => "a", :b => "c", "d" => 2 }
      pr = g.to_proc
      p pr.call(1)
      p pr.call(:b)
      p pr.call("d")
      p [1, :b, "d"].map(&g)
    RUBY

    _(result).must_answer <<~'OUT'
      [:foo, :bar]
      nil
      [:foo, :bar]
      "a"
      "c"
      2
      ["a", "c", 2]
    OUT
  end

  it "struct to h" do
    result = zr(<<~'RUBY')
      # Struct#to_h builds a symbol-keyed hash of member name => value.
      # Checked by lookup + length (inspect format varies across Ruby).
      Person = Struct.new(:name, :age, :city)
      h = Person.new("Alice", 30, "NYC").to_h
      p h[:name]
      p h[:age]
      p h[:city]
      p h.length
    RUBY

    _(result).must_answer <<~'OUT'
      "Alice"
      30
      "NYC"
      3
    OUT
  end

  it "to h maps elements through its block" do
    result = zr(<<~'RUBY')
      p [[1, 2], [3, 4]].to_h
      p [[1, 2], [3, 4]].to_h { |a, b| [b, a] }
      p({ a: 1, b: 2 }.to_h { |k, v| [v, k] })
      p (1..3).to_h { |i| [i, i * i] }
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 2, 3 => 4}
      {2 => 1, 4 => 3}
      {1 => :a, 2 => :b}
      {1 => 1, 2 => 4, 3 => 9}
    OUT
  end

  it "to h on boxed hash" do
    result = zr(<<~'RUBY')
      # Hash#to_h is the identity, so a BOXED receiver keeps the variant it really
      # holds. A String-keyed hash from a defaulted parameter keeps String keys.
      # An array of pairs keeps its keys when they are not Symbols.
      def tag(name, opts = {})
        merged = { "name" => name }.merge(opts.to_h)
        merged.map { |k, v| "#{k}=#{v}" }.join(" ")
      end
      p tag("a")
      p tag("b", { "x" => "1" })
      p tag("c", { y: 2 })

      def norm(v)
        v.to_h
      end
      p norm({ "s" => 1 })
      p norm({ s: 1 })
      p norm(nil)
      p norm([[1, 2]])
      p({ "a" => 1 }.to_h)
      p({ a: 1 }.to_h)
    RUBY

    _(result).must_answer <<~'OUT'
      "name=a"
      "name=b x=1"
      "name=c y=2"
      {"s" => 1}
      {s: 1}
      {}
      {1 => 2}
      {"a" => 1}
      {a: 1}
    OUT
  end

  it "to h with block" do
    result = zr(<<~'RUBY')
      # Array/Enumerable#to_h with a block maps each element to a [key, value] pair
      # and collects the pairs into a hash.
      p [1, 2, 3].to_h { |x| [x, x * x] }
      p %w[a bb ccc].to_h { |s| [s, s.length] }
      p (1..3).to_h { |n| [n.to_s, n] }
      p({a: 1, b: 2}.to_h { |k, v| [k, v * 10] })
      p ["a", "b"].each_with_index.to_h { |s, i| [s, i] }

      # blockless to_h still builds a hash from an array of pairs
      p [[1, 2], [3, 4]].to_h

      h = [1, 2].to_h { |x| [x, x + 1] }
      p h[2]
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 1, 2 => 4, 3 => 9}
      {"a" => 1, "bb" => 2, "ccc" => 3}
      {"1" => 1, "2" => 2, "3" => 3}
      {a: 10, b: 20}
      {"a" => 0, "b" => 1}
      {1 => 2, 3 => 4}
      3
    OUT
  end
end
