# frozen_string_literal: true

require "spec_helper"

describe "Programs: regressions" do
  it "max, min and sample with a count answer empty for an empty array" do
    result = ze0(<<~'RUBY')
      p [].max(2)
      p [].min(2)
      p [].sample(2)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
    OUT
  end

  it "a left shift of a negative Integer keeps the sign" do
    result = ze0(<<~'RUBY')
      p(-8 << 1)
      p(-1 << 4)
    RUBY

    _(result).must_answer <<~'OUT'
      -16
      -16
    OUT
  end

  it "max_by, min_by, sort_by and sum splat the pairs of an each_with_index enumerator" do
    result = ze0(<<~'RUBY')
      # max_by / min_by / sort_by / sum { block } on an each_with_index Enumerator:
      # materialize the pairs and run the block (auto-splatting each [v, i] pair).
      a = [3, 1, 2]
      p a.each_with_index.max_by { |v, _i| v }
      p a.each_with_index.min_by { |v, _i| v }
      p a.each_with_index.sort_by { |v, _i| v }
      p a.each_with_index.sum { |v, _i| v }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 0]
      [1, 1]
      [[1, 1], [2, 2], [3, 0]]
      6
    OUT
  end

  it "dup of an array read out of a container is a copy, not an alias" do
    result = ze0(<<~'RUBY')
      # Array#dup of an array read out of a poly container must be a real copy, not
      # an alias -- mutating the copy must not corrupt the original.
      board = [["a", "b"], ["c", "d"]]
      copy = board[0].dup
      copy[1] = "X"
      p board[0]
      p copy
      ints = [[1, 2], [3, 4]]
      c = ints[0].dup
      c[1] = 99
      p ints[0]
      p c
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["a", "X"]
      [1, 2]
      [1, 99]
    OUT
  end

  it "a ternary whose one arm can only raise still compiles, and the other arm answers" do
    result = ze0(<<~'RUBY')
      # A ternary whose true arm compiles to a NoMethodError raise (an unresolvable
      # call on a poly receiver) and whose false arm is a concrete type must compile:
      # the raise arm coerces to the sibling arm's type instead of aborting with a C
      # conditional type mismatch. flag is runtime so both arms are emitted; it is
      # false here so the string/int arm is taken.
      arr = [nil]
      u = arr.first
      flag = ARGV.length > 5
      label = (flag ? u.details : "~")
      puts label
      other = (flag ? u.missing : 42)
      p other
    RUBY

    _(result).must_answer <<~'OUT'
      ~
      42
    OUT
  end

  it "each_with_object writes into the object it was handed" do
    result = ze0(<<~'RUBY')
      h = {}
      [1, 2, 3].each_with_object(h) { |x, acc| acc[x] = x * x }
      p h
    RUBY

    _(result).must_answer "{1 => 1, 2 => 4, 3 => 9}\n"
  end

  it "values_at with no index answers an empty array" do
    result = ze0(<<~'RUBY')
      p([1, 2, 3].values_at)
      p(["a", "b"].values_at)
      p([1, 2, 3].values_at(0, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      [1, 3]
    OUT
  end

  it "partition splits a Hash into the pairs that match and the pairs that do not" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2, c: 3, d: 4 }
      pr = h.partition { |_k, v| v.even? }
      p pr[0].to_h
      p pr[1].to_h
    RUBY

    _(result).must_answer <<~'OUT'
      {b: 2, d: 4}
      {a: 1, c: 3}
    OUT
  end

  it "a regexp built with %r{} escapes the slashes in its inspect but not in its source" do
    result = ze0(<<~'RUBY')
      r = %r{a/b}
      puts r.source
      puts r.inspect
      puts r.to_s
      r2 = /foo\/bar/
      puts r2.inspect
      r3 = %r{a/b/c}mi
      puts r3.inspect
      puts r3.to_s
      puts(/x/.inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      a/b
      /a\/b/
      (?-mix:a\/b)
      /foo\/bar/
      /a\/b\/c/mi
      (?mi-x:a\/b\/c)
      /x/
    OUT
  end

  it "two Sets with the same members hash alike, whatever the order" do
    result = ze0(<<~'RUBY')
      require "set"
      a = Set[1, 2, 3]
      b = Set[3, 2, 1]
      c = Set[1, 2]
      p a.hash == b.hash
      p a.hash == c.hash
      p a.eql?(b)
      p Set["x", "y"].hash == Set["y", "x"].hash
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
    OUT
  end

  it "Symbol <=> String answers nil, and Symbol <=> Symbol orders" do
    result = ze0(<<~'RUBY')
      p(:abc <=> "abc")
      p(:abc <=> "abd")
      a = :abd; b = "abc"; p(a <=> b)
      p(:abc <=> :abd)
      p(:abc <=> 1)
      p([:b, :a].sort)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      -1
      nil
      [:a, :b]
    OUT
  end

  it "String#[] and Symbol#[] take a regexp and a capture name" do
    result = ze0(<<~'RUBY')
      p :hello[/(?<x>l+)/, "x"]
      p :hello[/(?<x>z+)/, "x"]
      p "hello"[/(?<x>l+)/, "x"]
      p "hello"[/(?<y>e)/, "y"]
      nm = "x"
      p "hello"[/(?<x>l+)/, nm]
      p :hello[/(?<x>l+)/, :x]
    RUBY

    _(result).must_answer <<~'OUT'
      "ll"
      nil
      "ll"
      "e"
      "ll"
      "ll"
    OUT
  end

  it "chr and %c answer one character, not one byte" do
    result = ze0(<<~'RUBY')
      p "あいう".chr
      p "abc".chr
      p "".chr
      p "€5".chr
      p("%c" % 12354)
      p("%c" % "あ")
      p("%c" % 65)
      p("%c" % "hello")
      p("%3c" % 65)
      p("%-3c" % 65)
      p("[%c]" % 0x1F600)
    RUBY

    _(result).must_answer <<~'OUT'
      "あ"
      "a"
      ""
      "€"
      "あ"
      "あ"
      "A"
      "h"
      "  A"
      "A  "
      "[😀]"
    OUT
  end

  it "chop removes one character, and a whole CRLF" do
    result = ze0(<<~'RUBY')
      p "abcあ".chop
      p "abc".chop
      p "".chop
      p "hello\r\n".chop
      p "あいう".chop
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      "ab"
      ""
      "hello"
      "あい"
    OUT
  end

  it "encode! and scrub! answer the receiver when there is nothing to change" do
    result = ze0(<<~'RUBY')
      p("hello".encode!("UTF-8"))
      p("abc".scrub!("?"))
      s = "world"; s.encode!; p s
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "abc"
      "world"
    OUT
  end

  it "a symbol-keyed Hash literal reads back by symbol" do
    result = ze0(<<~'RUBY')
      p({x: 1})
      h = {a: 1, b: 2, c: 3}
      p h[:b]
      p h.size
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1}
      2
      3
    OUT
  end

  it "any?, all?, none? and one? judge by truthiness, and an empty array is never any?" do
    result = ze0(<<~'RUBY')
      p [123].any? { _1 }
      p [1,2,3].any? { |x| x > 2 }
      p [1,2,3].all? { _1 }
      p [1,2,3].none? { _1 }
      p [1,2,3].one? { _1 }
      p [nil, nil].any? { _1 }
      p [0, 0].all? { _1 }
      p [].any? { _1 }
      p ["a", nil].any? { _1 }
      p [1,2,3].any? { |x| x.even? }
      p ["x", "y"].all? { |s| s }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      false
      true
      false
      true
      true
      true
    OUT
  end

  it "a symbol-keyed Hash rehashes correctly when it grows past its first capacity" do
    result = ze0(<<~'RUBY')
      # Symbol-keyed Hash literal + grow past the initial capacity. The grow path's
      # capacity->size_t allocation must not trip -Walloc-size-larger-than (#3146),
      # and must rehash correctly.
      h = {x: 1}
      p h[:x]

      big = {}
      30.times { |i| big[:"key#{i}"] = i * 3 }
      p big[:key0]
      p big[:key29]
      p big.length
      p big[:missing]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      87
      30
      nil
    OUT
  end

  it "a negative subscript on the outer array writes through to the inner one" do
    result = ze0(<<~'RUBY')
      m = [[1, 4], [2, 5]]
      m[-1][1] = 99
      m[0][0] = 7
      m[-2][1] += 100
      p m
      g = [["a","b"],["c","d"]]
      g[-1][0] = "Z"
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      [[7, 104], [2, 99]]
      [["a", "b"], ["Z", "d"]]
    OUT
  end

  it "take_while chains through with_index" do
    result = ze0(<<~'RUBY')
      p [3, 3, 5, 2].take_while.with_index { |v, i| i < 2 }
    RUBY

    _(result).must_answer "[3, 3]\n"
  end

  it "transpose, fill, rotate, product and zip over an empty array" do
    result = ze0(<<~'RUBY')
      p([].transpose)
      p([].fill(1))
      p([].rotate(3))
      a = [1, 2, 3]
      p(a.product([]))
      p([].product([1, 2]))
      p([1, 2].zip([]))
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      []
      []
      [[1, nil], [2, nil]]
    OUT
  end

  it "a local alias is the same String, so an append shows through both names" do
    result = ze0(<<~'RUBY')
      # In-place mutation through a local alias is observed (shared String object).
      s1 = "hello"
      s2 = s1
      p s1.equal?(s2)
      s1 << " world"
      p s1
      p s2
      p s1.equal?(s2)

      # chained aliases share the one object
      a = "x"
      b = a
      c = b
      a << "y"
      p [a, b, c]
      p a.equal?(c)

      # a string that is aliased but never mutated is unaffected
      m = "keep"
      n = m
      p n
      p m.equal?(n)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "hello world"
      "hello world"
      true
      ["xy", "xy", "xy"]
      true
      "keep"
      true
    OUT
  end

  it "each_with_object compiles when the block never reads the memo" do
    result = ze0(<<~'RUBY')
      # each_with_object with a Hash memo the block never reads must still compile.
      [1, 2].each_with_object({}) { |x, acc| p x }
      { a: 1 }.each_with_object({}) { |(k, v), h| p k }
      { a: 1, b: 2 }.each_with_object([]) { |(k, v), acc| p v }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      :a
      1
      2
    OUT
  end
end
