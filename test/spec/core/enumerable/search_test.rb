# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: searching and matching" do
  it "enum with index value" do
    result = ze0(<<~'RUBY')
      # with_index on a STORED Enumerator with its return value captured: the
      # block form drains the snapshot, drives the block with the offset index,
      # and returns the enumerator's each return -- the source receiver for an
      # each-family enumerator. (The discarded-return statement form and the
      # immediate arr.each/map.with_index chains keep their own emitters.)
      e = [1, 2, 3].each
      v = e.with_index(10) { |x, i| [x, i] }
      p v
      acc = []
      w = e.with_index { |x, i| acc << [x, i] }
      p w
      p acc
      # chain forms keep their own typing/emitters
      m = [4, 5].map.with_index(1) { |x, i| x * i }
      p m
      r = [7, 8].each.with_index { |x, i| acc << x + i }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [[1, 0], [2, 1], [3, 2]]
      [4, 10]
      [7, 8]
    OUT
  end

  it "grep, grep_v, sum and each_entry answer on a user class that writes each" do
    result = ze0(<<~'RUBY')
      # Enumerable (via a user class with #each) versions of grep/grep_v/sum/each_entry,
      # the receiver KieranP's #2479/#2480/#2504/#2516 duplicates exercise. The bug was
      # the __enum_to_a lowering picking the wrong element/result type.
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p(Nums.new("apple", "banana", "cherry").grep(/an/))
      p(Nums.new("apple", "banana", "cherry").grep_v(/an/))
      p(Nums.new("a", "b", "c").sum(""))
      p(Nums.new(1.5, 2.5, 3.0).sum)
      p(Nums.new(1.5, 2.5, 3.0).sum { |x| x * 2 })
      a = Nums.new(3, 1, 2)
      r = a.each_entry { |x| }
      p r.equal?(a)
    RUBY

    _(result).must_answer <<~'OUT'
      ["banana"]
      ["apple", "cherry"]
      "abc"
      7.0
      14.0
      true
    OUT
  end

  it "the short-circuiting rows stop an endless each, and a user break still belongs to its own call" do
    result = ze0(<<~'RUBY')
      # A user class whose `each` never ends is still usable, because the
      # short-circuiting Enumerable methods stop the SOURCE rather than scanning a
      # materialized copy of it. `first`/`take`/`find`/`include?` always did;
      # `take_while` used to collect first and so ran forever.
      #
      # The last line is the one that keeps the two kinds of stop apart: a `break` in
      # the USER's block belongs to the enclosing call, and must not be read as the
      # internal `rb_iter_break` these methods use to halt an endless source.
      class Inf
        include Enumerable
        def each; i = 1; loop { yield i; i += 1 }; end
      end
      p(Inf.new.first)
      p(Inf.new.first(3))
      p(Inf.new.take(3))
      p(Inf.new.find { |x| x > 3 })
      p(Inf.new.include?(3))
      p(Inf.new.take_while { |x| x < 4 })
      p(Inf.new.lazy.map { |x| x * 2 }.first(3))
      p(Inf.new.each { |x| break x * 10 })

      class Fin
        include Enumerable
        def each; yield 1; yield 2; yield 3; end
      end
      p(Fin.new.first)
      p(Fin.new.take(2))
      p(Fin.new.include?(9))
      p(Fin.new.map { |x| x * 2 })
      p(Fin.new.sort)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2, 3]
      [1, 2, 3]
      4
      true
      [1, 2, 3]
      [2, 4, 6]
      10
      1
      [1, 2]
      false
      [2, 4, 6]
      [1, 2, 3]
    OUT
  end

  it "the Enumerator rows answer, and a bad argument raises TypeError" do
    result = ze0(<<~'RUBY')
      # Enumerable/Enumerator surface (#2479, #2480, #2486, #2504, #2505, #2516)
      class C
        include Enumerable
        def each; yield 3; yield 1; yield 2; end
      end
      c = C.new
      p(c.grep(1..2))                       # 2479 grep with Range
      p(c.grep_v(2))                        # 2479 grep_v
      p(c.each_entry.class)                 # 2480 blockless each_entry -> Enumerator
      e = [10, 20].each
      e.each_with_index { |x, i| p [x, i] } # 2486 each_with_index on an Enumerator
      p(c.slice_before { |x| x == 1 }.to_a) # 2505 slice_before on a user Enumerable
      p([1.5, 2.5].sum)                     # 2516 Float sum with default init
      begin; [1, 2].sum(""); rescue => ex; p ex.class; end   # 2504 numeric sum, String init
      begin; c.sum("X"); rescue => ex; p ex.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 1]
      Enumerator
      [10, 0]
      [20, 1]
      [[3], [1, 2]]
      4.0
      TypeError
      TypeError
    OUT
  end

  it "env grep lazy followups" do
    result = ze0(<<~'RUBY')
      # ENV snapshot GC safety (#2842), grep with reference/module patterns
      # (#2843), hash/ENV lazy chains (#2845), ENV mutator chaining and the
      # bang trio (#2844), and slice_before/after === patterns (#2847).
      300.times { |i| ENV["ZZBIG_#{i}"] = "v" * 200 }
      20.times do
        n = 0
        ENV.each_value { |v| n += 1 }
        raise "bad" unless n > 300
      end
      puts "ok"
      p [[1, 2], [3, 4]].grep(Array).length
      p [1, [2], {3 => 4}, "x"].grep(Array)
      p [1, [2], {3 => 4}, "x"].grep(Hash)
      p [1, [2], "x"].grep(Object).length
      p [1, 2.5, "x", :s].grep(Comparable)
      p [1, [2], "x"].grep(Enumerable)
      p [1, 2, 3].grep(Array)
      p [1, "a", 2].grep_v(String)
      class UU2; end
      p [UU2.new, 1].grep(UU2).length
      h = {"a" => 1}
      p ENV.grep(Array).length >= 0 rescue p :env_grep_fail
      p({ a: 1, b: 2 }.lazy.select { |k, v| v > 0 }.first(1))
      h = { "x" => 1, "y" => 2 }
      p h.lazy.map { |k, v| k }.first(2)
      ENV['ZZ_L'] = '9'
      p ENV.lazy.select { |k, v| k == 'ZZ_L' }.first(1)
      a = [["x", 1], ["y", 2]]
      p a.lazy.map { |k, v| k }.first(2)
      p [1, 2, 3, 1, 2].slice_before(2..3).to_a
      p %w[a bb c].slice_before(/b/).to_a
      p [1, 2, 3].slice_after(Integer).to_a
      p [1, "x", 2, "y"].slice_before(String).to_a
      p [1, 2, 3, 1, 2].slice_after(2..3).to_a
      p [1, 2, 3, 1].slice_before(2).to_a
      p [1, 2.5, 3].slice_before(2.0..3.0).to_a
      ENV.delete('ZZ_A'); ENV.delete('ZZ_B')
      ENV.update('ZZ_A' => '1').update('ZZ_B' => '2')
      p ENV['ZZ_A']
      p ENV['ZZ_B']
      p ENV.reject! { |k, v| false }
      p ENV.class
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      2
      [[2]]
      [{3 => 4}]
      3
      [1, 2.5, "x", :s]
      [[2]]
      []
      [1, 2]
      1
      true
      [[:a, 1]]
      ["x", "y"]
      [["ZZ_L", "9"]]
      ["x", "y"]
      [[1], [2], [3, 1], [2]]
      [["a"], ["bb", "c"]]
      [[1], [2], [3]]
      [[1], ["x", 2], ["y"]]
      [[1, 2], [3], [1, 2]]
      [[1], [2, 3, 1]]
      [[1], [2.5], [3]]
      "1"
      "2"
      nil
      Object
    OUT
  end

  it "grep proc pattern" do
    result = ze0(<<~'RUBY')
      even001 = ->(x) { x.even? }
      p [1, 2, 3, 4].grep(even001)
      even002 = ->(x) { x.even? }; p [1, 2, 3, 4].grep_v(even002)
      p [1, 2, 3, 4].grep(->(x) { x.even? })
      even004 = ->(x) { x.even? }
      p(even004 === 4)
      p [1,2,3].grep(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [1, 3]
      [2, 4]
      true
      [1, 2, 3]
    OUT
  end

  it "grep v runtime recv" do
    result = ze0(<<~'RUBY')
      # receiver routed through a method param exercises the runtime loop path
      def gv(a) = a.grep_v(2)
      def gp(a) = a.grep(2)
      def gvr(a) = a.grep_v(2..3)

      p gv([1, 2, 3, 2, 4])
      p gp([1, 2, 3, 2, 4])
      p gvr([1, 2, 3, 4, 5])

      # literal receiver, integer pattern
      p [1, 2, 3, 2, 4].grep_v(2)

      # poly (mixed) array with an integer pattern
      def gpoly(a) = a.grep_v(2)
      p gpoly([1, "x", 2, 3, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 4]
      [2, 2]
      [1, 4, 5]
      [1, 3, 4]
      [1, "x", 3]
    OUT
  end

  it "lv widen from callee arg slot" do
    result = ze0(<<~'RUBY')
      # Phase 3: LV back-propagation from callee arg slot.
      #
      # Body-derived widening of a callee's param (via
      # narrow_param_hash_types_from_body_writes) doesn't reach
      # the caller's local variable. The call site then passes
      # sp_StrIntHash * into a sp_StrPolyHash * slot.
      #
      # Shape (real-blog parse_request / parse_form_into):
      #
      #   def assign(into, k, v)
      #     # heterogeneous body — widens `into` to str_poly_hash
      #     if k.include?("[")
      #       into[k] = {}
      #     else
      #       into[k] = v
      #     end
      #   end
      #
      #   def parse(input, into)
      #     input.split("&").each { |p| assign(into, p, "v") }
      #   end
      #
      #   def run
      #     params = {}                     # str_int_hash by default
      #     parse("a=1&b=2", params)        # callee widens; params LV
      #                                     # needs to widen too
      #     params
      #   end
      #
      # Pre-fix the `params = {}` literal compiles as
      # sp_StrIntHash_new() and the call passes it to the
      # StrPolyHash slot — warns under -Wincompatible-pointer-types.
      # With this pass, params widens to str_poly_hash and the
      # literal lowers to sp_StrPolyHash_new() directly.

      module Form
        def self.assign(into, k, v)
          if k.include?("[")
            into[k] = {}
          else
            into[k] = v
          end
        end

        def self.parse(input, into)
          input.split("&").each { |p| assign(into, p, "v") }
        end

        def self.run
          params = {}
          parse("a=1&b=2", params)
          params["a"]
        end
      end

      puts Form.run
    RUBY

    _(result).must_answer "\n"
  end

  it "nested index write poly index" do
    result = ze0(<<~'RUBY')
      # `rows[r][c] = "*"` where `r` comes from a destructured block parameter. The
      # store has two lowerings: one that writes through the outer container's slot,
      # and one that fetches the element by value and writes into that copy. The
      # addressable test required an INTEGER index, so a boxed one fell to the
      # by-value form and the assignment was silently dropped -- no error, and the
      # expression still answered its right-hand side (#4078).
      rows = ["abc"].map(&:dup)
      pairs = [[0, 1]]
      pairs.each { |r, c| rows[r][c] = "*" }
      p rows

      # the shapes that already worked, so they still do
      ok1 = ["abc"].map(&:dup)
      [[0, 1]].each { |r, c| ok1[r][c] = "*" }
      p ok1

      ok2 = ["abc"].map(&:dup)
      idx = [1]
      idx.each { |c| ok2[0][c] = "*" }
      p ok2

      # more than one pair, and a second row
      many = ["abc", "def"].map(&:dup)
      [[0, 1], [1, 0]].each { |r, c| many[r][c] = "*" }
      p many

      # an Integer array inner, which takes the widen-and-store path
      grid = [[1, 2], [3, 4]]
      gp = [[0, 1]]
      gp.each { |r, c| grid[r][c] = 9 }
      p grid

      # a Hash outer keyed by a String: the slot helpers address by integer, so this
      # one must NOT take the addressable path
      h = { "k" => [1, 2] }
      kk = [["k", 0]]
      kk.each { |k, i| h[k][i] = 7 }
      p h

      # three levels deep
      deep = [[["a"]]]
      [[0, 0]].each { |x, y| deep[x][y][0] = "b" }
      p deep
    RUBY

    _(result).must_answer <<~'OUT'
      ["a*c"]
      ["a*c"]
      ["a*c"]
      ["a*c", "*ef"]
      [[1, 9], [3, 4]]
      {"k" => [7, 2]}
      [[["b"]]]
    OUT
  end

  it "struct member shadows enumerable" do
    result = ze0(<<~'RUBY')
      # A Struct/Data member accessor always beats the inherited Enumerable
      # surface: CRuby defines accessors directly on the subclass, so a member
      # named `count` (or `min`, `first`, ...) shadows Enumerable's method of
      # the same name. The synthesized-#each Enumerable lowering wrapped every
      # non-chain method into __enum_to_a without checking the member table, so
      # `Data.define(:count).new(count: 7).count` returned the MEMBER TOTAL (1)
      # instead of the member value (7) - and a Data model folded through #with
      # froze at its first value.

      Model = Data.define(:count)
      m = Model.new(count: 7)
      puts m.count
      m2 = m.with(count: m.count + 1)
      puts m2.count

      Pair = Data.define(:count, :min)
      pr = Pair.new(count: 40, min: 9)
      puts pr.count
      puts pr.min

      # Struct spelling: members named after Enumerable terminals still read as
      # members...
      SFirst = Struct.new(:first, :count)
      s = SFirst.new(10, 20)
      puts s.first
      puts s.count

      # ...while Enumerable methods NOT named after a member still ride the
      # synthesized each (the wave's feature stays intact; Struct, unlike Data,
      # includes Enumerable in CRuby).
      Wide = Struct.new(:a, :b, :c)
      w = Wide.new(3, 1, 2)
      puts w.sum
      puts w.include?(2)
      puts w.map { |v| v * 10 }.join(",")
      puts w.min
    RUBY

    _(result).must_answer <<~'OUT'
      7
      8
      40
      9
      10
      20
      6
      true
      30,10,20
      1
    OUT
  end

  it "user enumerable reach" do
    result = ze0(<<~'RUBY')
      # Three ways an object of a class that includes Enumerable failed to reach the
      # mixin: called with an implicit self from another method of the class, read
      # out of a container (where it is boxed and every poly op answered for an empty
      # collection), and handed to zip as the argument rather than the receiver.
      class Nums
        include Enumerable

        def initialize(*xs)
          @xs = xs
        end

        def each
          @xs.each { |x| yield x }
        end

        # implicit self: the redirect keyed on a receiver node, and this call has none
        def total; sum; end
        def size_via_count; count; end
        def biggest; max; end
      end

      n = Nums.new(1, 2, 3)
      p n.total
      p n.size_via_count
      p n.biggest

      # boxed in a container: the poly ops fell to a default that answered 0/nil/false
      [Nums.new(1, 2)].each { |o| p o.sum }
      [Nums.new(1, 2)].each { |o| p o.count }
      [Nums.new(4, 5)].each { |o| p o.max }
      [Nums.new(4, 5)].each { |o| p o.min }
      [Nums.new(4, 5)].each { |o| p o.to_a }
      [Nums.new(4, 5)].each { |o| p o.include?(5) }

      # as zip's argument, not its receiver
      p Nums.new(1, 2).zip(Nums.new(3, 4))
      p [1, 2].zip(Nums.new(5, 6))

      # the forms that already worked keep working
      p n.sum
      p n.to_a
      p n.sort
      def via_param(o); o.sum; end
      p via_param(Nums.new(7, 8))
    RUBY

    _(result).must_answer <<~'OUT'
      6
      3
      3
      3
      2
      5
      4
      [4, 5]
      true
      [[1, 3], [2, 4]]
      [[1, 5], [2, 6]]
      6
      [1, 2, 3]
      [1, 2, 3]
      15
    OUT
  end

  it "with index" do
    result = ze0(<<~'RUBY')
      # map/each/select.with_index with an optional offset. The receiver is a
      # blockless enumerator; with_index binds the element plus a running index.
      # Route receivers through per-type method params to exercise the runtime path
      # (distinct helpers so the params stay monomorphic, not unified to poly).
      def ints(a) = a
      def strs(a) = a

      nums = ints([10, 20, 30])
      p nums.map.with_index { |x, i| x + i }        # [10, 21, 32]
      p nums.map.with_index(1) { |x, i| x * i }     # [10, 40, 90]
      p nums.collect.with_index(100) { |x, i| i }   # [100, 101, 102]

      words = strs(["a", "b", "c", "d"])
      p words.map.with_index { |s, i| "#{i}:#{s}" } # ["0:a", "1:b", "2:c", "3:d"]
      p words.select.with_index { |s, i| i.even? }  # ["a", "c"]
      p words.reject.with_index { |s, i| i.even? }  # ["b", "d"]

      # each.with_index returns the receiver; collect side effects via an accumulator
      acc = []
      ret = nums.each.with_index(10) { |x, i| acc << (i * 1000 + x) }
      p acc                                          # [10010, 11020, 12030]
      p ret                                          # [10, 20, 30]

      # a runtime-empty but concretely-typed receiver still yields []
      p nums.select.with_index { |x, i| i > 99 }     # []
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 21, 32]
      [10, 40, 90]
      [100, 101, 102]
      ["0:a", "1:b", "2:c", "3:d"]
      ["a", "c"]
      ["b", "d"]
      [10010, 11020, 12030]
      [10, 20, 30]
      []
    OUT
  end

  it "with index enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless <enumerator>.with_index(offset) returns a materialized Enumerator
      # over the [element, index] pairs, a first-class value supporting to_a / next /
      # peek / size. The block and terminal-chain forms must keep working.

      # --- blockless: a first-class Enumerator over [element, index] pairs ---
      e = [10, 20, 30].each.with_index
      p e.class
      p e.to_a
      p e.size
      p e.next
      p e.next
      p e.peek
      p e.next

      # --- with an explicit offset ---
      o = [10, 20, 30].each.with_index(1)
      p o.to_a
      p o.next

      # --- on a String#each_char enumerator ---
      p "abc".each_char.with_index(1).to_a

      # --- assigned, then materialized ---
      pairs = %w[a b c].each.with_index(10)
      arr = pairs.to_a
      p arr.length
      p arr

      # --- existing block form (yields |element, index|) still works ---
      p [10, 20, 30].map.with_index { |x, i| [x, i] }
      p [10, 20, 30].map.with_index(1) { |x, i| x + i }
      seen = []
      [10, 20].each.with_index { |x, i| seen << [x, i] }
      p seen
      p [10, 20, 30].select.with_index { |_x, i| i.even? }

      # --- existing terminal / map chains still work ---
      p [10, 20, 30].each.with_index.to_a
      p [10, 20, 30].each.with_index(1).to_a
      p [10, 20].each.with_index(1).map { |x, i| [i, x] }
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [[10, 0], [20, 1], [30, 2]]
      3
      [10, 0]
      [20, 1]
      [30, 2]
      [30, 2]
      [[10, 1], [20, 2], [30, 3]]
      [10, 1]
      [["a", 1], ["b", 2], ["c", 3]]
      3
      [["a", 10], ["b", 11], ["c", 12]]
      [[10, 0], [20, 1], [30, 2]]
      [11, 22, 33]
      [[10, 0], [20, 1]]
      [10, 30]
      [[10, 0], [20, 1], [30, 2]]
      [[10, 1], [20, 2], [30, 3]]
      [[1, 10], [2, 20]]
    OUT
  end
end
