# frozen_string_literal: true

require "spec_helper"

describe "Builtins: slicing" do
  it "builtin collection via enumerable" do
    result = zr(<<~'RUBY')
      # A collection method CRuby defines on the class itself walks that class's own
      # storage -- `rb_ary_collect` never calls `each`. zeo routed 23 of these rows
      # through `Enumerable`, whose bodies iterate by SENDING `each`, so overriding
      # `each` at runtime changed all of them at once.
      #
      # Invisible until a runtime override of a builtin iterator could take effect
      # (tests/issue_runtime_override_builtin_iterator.rb). The `inherited_row!`
      # rows stay -- reflection needs `Array.instance_method(:map).owner` to answer
      # `Array` -- and only the bodies changed.
      #
      # The rows that really ARE Enumerable's in CRuby (`Range#map`, `Hash#map`) are
      # deliberately absent: they follow a patched `each` in ruby too.

      a = [4, 5, 6]
      Array.send(:define_method, :each) { |&b| b.call(:patched); self }

      # `each` itself is patched -- the control line.
      seen = []
      a.each { |v| seen << v }
      p seen

      # ...and nothing below is, because Array owns every one of these.
      p a.map { |v| v * 2 }
      p a.collect { |v| v - 1 }
      p a.select { |v| v > 4 }
      p a.filter { |v| v.even? }
      p a.reject { |v| v > 4 }
      p a.find { |v| v > 4 }
      p a.detect { |v| v > 5 }
      p a.all? { |v| v > 3 }
      p a.any? { |v| v > 5 }
      p a.none? { |v| v > 9 }
      p a.one? { |v| v == 5 }
      p a.count
      p a.count(5)
      p a.count { |v| v > 4 }
      p a.sum
      p a.sum(10)
      p a.max
      p a.max(2)
      p a.min
      p a.min(2)
      p a.minmax
      p a.take(2)
      p a.drop(1)
      p a.take_while { |v| v < 6 }
      p a.drop_while { |v| v < 6 }
      rv = []
      a.reverse_each { |v| rv << v }
      p rv

      # The argument-less predicates read truthiness, not a block.
      p [nil, false].any?
      p [nil, 1].any?
      p [].all?
      p [1, nil].none?
      p [nil, 1].one?

      # Range's four, and Hash's one.
      r = (1..4)
      Range.send(:define_method, :each) { |&b| b.call(:rpatched); self }
      p r.count
      p r.minmax
      rr = []
      r.reverse_each { |v| rr << v }
      p rr

      h = { x: 1, y: 2 }
      Hash.send(:define_method, :each) { |&b| b.call(:hpatched, nil); self }
      p h.any?
      p h.any? { |k, v| v > 1 }
      p({}.any?)
    RUBY

    _(result).must_answer <<~'OUT'
      [:patched]
      [8, 10, 12]
      [3, 4, 5]
      [5, 6]
      [4, 6]
      [4]
      5
      6
      true
      true
      true
      true
      3
      1
      2
      15
      25
      6
      [6, 5]
      4
      [4, 5]
      [4, 6]
      [4, 5]
      [5, 6]
      [4, 5]
      [6]
      [6, 5, 4]
      false
      true
      true
      false
      true
      4
      [1, 4]
      [4, 3, 2, 1]
      true
      true
      false
    OUT
  end

  it "builtin reopen dup override beats kernel dup" do
    result = zr(<<~'RUBY')
      # A `dup` override beats universal `Kernel#dup` on both the static String
      # site and a Poly site (the any-builtin-overrides fall-through); `clone`
      # -- not overridden -- stays the universal shallow copy.

      class String
        def dup
          "dupped"
        end
      end

      s = "orig"
      puts s.dup
      puts [s].first.dup
      puts s.clone
    RUBY

    _(result).must_answer <<~'OUT'
      dupped
      dupped
      orig
    OUT
  end

  it "builtin reopen methods take blocks and capture self" do
    result = zr(<<~'RUBY')
      # Blocks through a builtin reopen: `yield` + an optional parameter, and an
      # escaping block that captures both a mutated local (a Captured cell) and
      # `self` (the `__self: RubyValue` clone path).

      class Integer
        def repeat(sep = "-")
          out = ""
          i = 0
          while i < self
            out = out + yield(i).to_s
            out = out + sep if i < self - 1
            i = i + 1
          end
          out
        end

        def add_each(arr)
          total = 0
          arr.each do |x|
            total = total + x + self
          end
          total
        end
      end

      puts 3.repeat { |i| i * 2 }
      puts 2.repeat("+") { |i| i + 1 }
      puts 10.add_each([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      0-2-4
      1+2
      36
    OUT
  end

  it "builtin reopen nil hash and range" do
    result = zr(<<~'RUBY')
      # The receiver-kind breadth: NilClass (no static TyKind -- fully dynamic),
      # Hash (implicit native `size`), and Range (static `self.last`/`self.first`
      # fast paths inside the reopen body).

      class NilClass
        def describe
          "nothing"
        end
      end

      class Hash
        def pair_count
          size
        end
      end

      class Range
        def span
          self.last - self.first
        end
      end

      puts nil.describe
      puts({ a: 1, b: 2 }.pair_count)
      puts (3..9).span
    RUBY

    _(result).must_answer <<~'OUT'
      nothing
      2
      6
    OUT
  end

  it "builtin reopen override beats native length" do
    result = zr(<<~'RUBY')
      # Overriding an EXISTING native method: the user `length` wins at a static
      # call site (where `try_collection_dispatch` would answer 3), at a dynamic
      # Poly site, and `size` -- a separate method in real Ruby, NOT an alias of
      # the override -- stays native.

      class String
        def length
          42
        end
      end

      s = "abc"
      puts s.length
      puts [s].first.length
      puts "xy".size
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      2
    OUT
  end

  it "instance exec parity" do
    result = zr(<<~'RUBY')
      # Consolidated CRuby-4.0.6 parity anchor for direct instance_exec: one
      # file exercising the supported core shapes in combination. Every line's
      # output is cross-checked against `ruby` (the .expected is the oracle).

      class Acc
        def initialize(base)
          @base = base
        end

        def base
          @base
        end

        def combine(x, y)
          @base + x + y
        end
      end

      class AccPlus < Acc
      end

      a = AccPlus.new(100)

      # positional args bound to block params; body calls a rebound-self method
      puts a.instance_exec(3, 4) { |x, y| combine(x, y) }      #=> 107

      # expression position: call value is the block's last expression
      puts a.instance_exec(5) { |x| base + x }                 #=> 105

      # outer-local capture: read + write-back into the caller's scope
      total = 0
      a.instance_exec { total = base + 1 }
      puts total                                               #=> 101

      # capture accumulation across multiple calls
      sum = 0
      a.instance_exec { sum = sum + base }
      a.instance_exec { sum = sum + base }
      puts sum                                                 #=> 200

      # block body-local + multi-statement
      puts a.instance_exec(2) { |x| t = base + x; t * 2 }      #=> 204

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      107
      105
      101
      200
      204
      done
    OUT
  end

  it "range query and step surface" do
    result = zr(<<~'RUBY')
      # Every `Range` query and `#step` shape, against ruby 4.0.6: the closed forms
      # an unbounded range answers without walking, the negative-count refusals, and
      # the bad-stride messages -- which all come from `begin + step`.
      def t(label)
        begin
          p [label, yield]
        rescue Exception => e
          p [label, e.class.name, e.message]
        end
      end
      t("rev endless")  { (1..).reverse_each.first(2) }
      t("rev beginless"){ (..5).reverse_each.first(3) }
      t("rev int")      { (1..5).reverse_each.to_a }
      t("rev str")      { ("a".."e").reverse_each.to_a }
      t("rev float")    { (1.0..5.0).reverse_each.to_a }
      t("rev beginfl")  { (..5.0).reverse_each.first(2) }
      t("last -1")      { (1..5).last(-1) }
      t("min -1")       { (1..5).min(-1) }
      t("max -1")       { (1..5).max(-1) }
      t("first -1")     { (1..5).first(-1) }
      t("minmax endless"){ (1..).minmax }
      t("minmax beginless"){ (..5).minmax }
      t("minmax float") { (1.0..5.0).minmax }
      t("minmax floatx"){ (1.0...5.0).minmax }
      t("count endless"){ (1..).count }
      t("count beginless"){ (..5).count }
      t("to_a beginless"){ (..5).to_a }
      t("minmax block") { (1..5).minmax { |a,b| b<=>a } }
      t("eql same")     { (1..5).eql?(1..5) }
      t("eql float")    { (1..5).eql?(1.0..5.0) }
      t("eqeq float")   { (1..5) == (1.0..5.0) }
      t("eql int")      { (1..5).eql?(1) }
      t("cover r1")     { (1..5).cover?(1...6) }
      t("cover r2")     { (1..5).cover?(2..9) }
      t("cover r3")     { (1..5).cover?(1.0..5.0) }
      t("cover r4")     { (1..5).cover?(1.0...5.5) }
      t("cover r5")     { (1...5).cover?(1..4) }
      t("=== range")    { (1..5) === (1.0..5.0) }
      t("include range"){ (1..5).include?(1..2) }
      t("cover beginless"){ (1..5).cover?(nil..3) }
      t("cover endless"){ (1..5).cover?(2..) }
      t("beginless cover"){ (nil..5).cover?(1..3) }
      t("hash")         { (1..5).hash == (1..5).hash }
      t("step size inf"){ (1..).step(2).size }
      t("step size")    { (1..5).step(2).size }
      t("step noarg")   { (1..3).step.to_a }
      t("step str")     { ("a".."e").step(2).to_a }
      t("pct")          { ((1..10) % 3).to_a }
      t("step neg")     { (1..10).step(-1).inspect }
      t("step beginless"){ (..5).step(2) { |x| x } }
      t("step badf")    { (1.0..10.0).step("x").to_a }
      t("step bads")    { ("a".."e").step(:s).to_a }
      t("step badi")    { (1..10).step(nil).to_a }

      # The `min`/`max`/`minmax` closed forms: `range.c` READS the endpoints rather
      # than walking, so an empty, exclusive, Float, endless or beginless range
      # answers without an iteration a monkey-patched `each` could reach.
      t("min i"){ (1..4).min }; t("max i"){ (1..4).max }
      t("min ix"){ (1...4).min }; t("max ix"){ (1...4).max }
      t("min s"){ ("a".."e").min }; t("max s"){ ("a".."e").max }
      t("min sx"){ ("a"..."e").min }; t("max sx"){ ("a"..."e").max }
      t("min f"){ (1.0..5.0).min }; t("max f"){ (1.0..5.0).max }
      t("min fx"){ (1.0...5.0).min }; t("max fx"){ (1.0...5.0).max }
      t("min empty"){ (5..1).min }; t("max empty"){ (5..1).max }
      t("min emptyx"){ (5...1).min }; t("max emptyx"){ (5...1).max }
      t("min same x"){ (3...3).min }; t("max same x"){ (3...3).max }
      t("min endless"){ (1..).min }; t("max beginless"){ (..5).max }
      t("max beginless x"){ (...5).max }
      t("min n"){ (1..5).min(2) }; t("max n"){ (1..5).max(2) }
      t("min blk"){ (1..5).min { |a,b| b<=>a } }; t("max blk"){ (1..5).max { |a,b| b<=>a } }
      t("minmax"){ (1..5).minmax }; t("minmax s"){ ("a".."e").minmax }
      t("minmax x"){ (1...5).minmax }; t("minmax sx"){ ("a"..."e").minmax }
      t("max fx begin"){ (1.0...5).max }
      t("max str excl"){ ("a"..."e").max }
      t("max n beginless"){ (..5).max(2) }
      t("max n"){ (1..9).max(3) }
      t("max n str"){ ("a".."e").max(2) }
      t("max n excl"){ (1...9).max(3) }
      t("max 0"){ (1..9).max(0) }
      t("max big"){ (1..3).max(10) }
      t("max n float"){ (1.0..5.0).max(2) }
      t("min n"){ (1..9).min(3) }
      t("min n str"){ ("a".."e").min(2) }
      t("last n"){ (1..9).last(3) }
      t("first n"){ (1..9).first(3) }
      t("minmax beginless int"){ (..5).minmax }
    RUBY

    _(result).must_answer <<~'OUT'
      ["rev endless", "TypeError", "can't iterate from NilClass"]
      ["rev beginless", [5, 4, 3]]
      ["rev int", [5, 4, 3, 2, 1]]
      ["rev str", ["e", "d", "c", "b", "a"]]
      ["rev float", "TypeError", "can't iterate from Float"]
      ["rev beginfl", "TypeError", "can't iterate from NilClass"]
      ["last -1", "ArgumentError", "negative array size"]
      ["min -1", "ArgumentError", "negative array size (or size too big)"]
      ["max -1", "ArgumentError", "negative array size (or size too big)"]
      ["first -1", "ArgumentError", "negative array size (or size too big)"]
      ["minmax endless", "RangeError", "cannot get the maximum of endless range"]
      ["minmax beginless", "RangeError", "cannot get the minimum of beginless range"]
      ["minmax float", [1.0, 5.0]]
      ["minmax floatx", "TypeError", "cannot exclude non Integer end value"]
      ["count endless", Infinity]
      ["count beginless", Infinity]
      ["to_a beginless", "TypeError", "can't iterate from NilClass"]
      ["minmax block", [5, 1]]
      ["eql same", true]
      ["eql float", false]
      ["eqeq float", true]
      ["eql int", false]
      ["cover r1", true]
      ["cover r2", false]
      ["cover r3", true]
      ["cover r4", false]
      ["cover r5", true]
      ["=== range", false]
      ["include range", false]
      ["cover beginless", false]
      ["cover endless", false]
      ["beginless cover", true]
      ["hash", true]
      ["step size inf", Infinity]
      ["step size", 3]
      ["step noarg", [1, 2, 3]]
      ["step str", ["a", "c", "e"]]
      ["pct", [1, 4, 7, 10]]
      ["step neg", "((1..10).step(-1))"]
      ["step beginless", "ArgumentError", "#step iteration for beginless ranges is meaningless"]
      ["step badf", "TypeError", "String can't be coerced into Float"]
      ["step bads", "TypeError", "no implicit conversion of Symbol into String"]
      ["step badi", "TypeError", "nil can't be coerced into Integer"]
      ["min i", 1]
      ["max i", 4]
      ["min ix", 1]
      ["max ix", 3]
      ["min s", "a"]
      ["max s", "e"]
      ["min sx", "a"]
      ["max sx", "d"]
      ["min f", 1.0]
      ["max f", 5.0]
      ["min fx", 1.0]
      ["max fx", "TypeError", "cannot exclude non Integer end value"]
      ["min empty", nil]
      ["max empty", nil]
      ["min emptyx", nil]
      ["max emptyx", nil]
      ["min same x", nil]
      ["max same x", nil]
      ["min endless", 1]
      ["max beginless", 5]
      ["max beginless x", 4]
      ["min n", [1, 2]]
      ["max n", [5, 4]]
      ["min blk", 5]
      ["max blk", 1]
      ["minmax", [1, 5]]
      ["minmax s", ["a", "e"]]
      ["minmax x", [1, 4]]
      ["minmax sx", ["a", "d"]]
      ["max fx begin", "TypeError", "cannot exclude end value with non Integer begin value"]
      ["max str excl", "d"]
      ["max n beginless", [5, 4]]
      ["max n", [9, 8, 7]]
      ["max n str", ["e", "d"]]
      ["max n excl", [8, 7, 6]]
      ["max 0", []]
      ["max big", [3, 2, 1]]
      ["max n float", "TypeError", "can't iterate from Float"]
      ["min n", [1, 2, 3]]
      ["min n str", ["a", "b"]]
      ["last n", [7, 8, 9]]
      ["first n", [1, 2, 3]]
      ["minmax beginless int", "RangeError", "cannot get the minimum of beginless range"]
    OUT
  end

  it "string range walk surface" do
    result = zr(<<~'RUBY')
      # The `succ` walk `String#upto` and a String/Symbol Range share
      # (`rb_str_upto_each`): its single-character, all-digit and byte-ordered
      # branches, plus what a `break` in each form answers.
      def t(l); p [l, (yield)]; rescue Exception => e; p [l, e.class.name, e.message]; end
      t("str range"){ ("a".."e").to_a }
      t("str range x"){ ("a"..."e").to_a }
      t("str 2ch"){ ("aa".."ac").to_a }
      t("str y-ab"){ ("y".."ab").to_a }
      t("digits"){ ("9".."11").to_a }
      t("digits pad"){ ("08".."11").to_a }
      t("digits x"){ ("9"..."11").to_a }
      t("sym"){ (:a..:e).to_a }
      t("sym2"){ (:aa..:ac).to_a }
      t("upto"){ "a".upto("e").to_a }
      t("upto excl"){ "a".upto("e", true).to_a }
      t("upto digits"){ "9".upto("11").to_a }
      t("upto pad"){ "08".upto("10").to_a }
      t("upto rev"){ "e".upto("a").to_a }
      t("upto same"){ "a".upto("a").to_a }
      t("upto ret"){ "a".upto("c") { |s| s } }
      t("include"){ ("a".."e").include?("bb") }
      t("cover"){ ("a".."e").cover?("bb") }
      t("step str"){ ("a".."z").step(5).to_a }
      t("step sym"){ (:a..:j).step(3).to_a }
      t("each break"){ ("a".."z").step(2) { |s| break s } }
      t("upto break"){ "a".upto("z") { |s| break s } }
      t("range size"){ ("a".."e").size }
      t("min/max"){ [("a".."e").min, ("a".."e").max] }
      t("succ carry"){ ("az".."bc").to_a }
    RUBY

    _(result).must_answer <<~'OUT'
      ["str range", ["a", "b", "c", "d", "e"]]
      ["str range x", ["a", "b", "c", "d"]]
      ["str 2ch", ["aa", "ab", "ac"]]
      ["str y-ab", []]
      ["digits", ["9", "10", "11"]]
      ["digits pad", ["08", "09", "10", "11"]]
      ["digits x", ["9", "10"]]
      ["sym", [:a, :b, :c, :d, :e]]
      ["sym2", [:aa, :ab, :ac]]
      ["upto", ["a", "b", "c", "d", "e"]]
      ["upto excl", ["a", "b", "c", "d"]]
      ["upto digits", ["9", "10", "11"]]
      ["upto pad", ["08", "09", "10"]]
      ["upto rev", []]
      ["upto same", ["a"]]
      ["upto ret", "a"]
      ["include", false]
      ["cover", true]
      ["step str", ["a", "f", "k", "p", "u", "z"]]
      ["step sym", [:a, :d, :g, :j]]
      ["each break", "a"]
      ["upto break", "a"]
      ["range size", nil]
      ["min/max", ["a", "e"]]
      ["succ carry", ["az", "ba", "bb", "bc"]]
    OUT
  end
end
