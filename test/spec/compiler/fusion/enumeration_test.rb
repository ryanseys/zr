# frozen_string_literal: true

require "spec_helper"

describe "Fusion: enumeration" do
  it "fused inject carries its accumulator" do
    result = ze0(<<~'RUBY')
      arr = [1, 2, 3, 4]

      p arr.inject(0) { |a, b| a + b }
      p arr.inject(10) { |a, b| a + b }
      p arr.reduce([]) { |a, b| a << b }
      p arr.inject("") { |a, b| a += b.to_s; a }

      # The block's VALUE is the next accumulator, so reassigning either param
      # inside the body only matters through what the body evaluates to.
      p arr.inject(0) { |a, b| b = 100; a + b }
      p(arr.inject(0) { |a, b| next a })

      # An empty receiver never calls the block and answers the seed.
      p [].inject(:seed) { |a, b| :other }

      # `break` overrides the whole call.
      p(arr.inject(0) { |a, b| break :early })

      # Without an explicit seed the first element IS the seed and the block is not
      # called for it -- a different shape, which takes the dynamic row.
      p arr.inject { |a, b| a + b }
      p arr.inject(:+)

      # A block with any count other than two params also takes the dynamic row.
      p arr.inject(0) { |a| 7 }

      # Nested drivers, each with its own accumulator.
      p arr.inject(0) { |a, b| a + [b, b].inject(0) { |c, d| c + d } }
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      [1, 2, 3, 4]
      "1234"
      400
      0
      :seed
      :early
      10
      10
      7
      20
    OUT
  end

  it "lazy unfused terminal" do
    result = ze0(<<~'RUBY')
      # A terminal the lazy pipeline does not fuse -- sum, count, min, include? --
      # runs on the materialized result. Without an arm the call answered nil or
      # refused to compile.
      p([1, 2, 3].lazy.sum)
      p([1, 2, 3].lazy.count)
      p([1, 2, 3].lazy.min)
      p([1, 2, 3].lazy.max)
      p([1, 2, 3].lazy.include?(2))
      p([1, 2, 3].lazy.include?(9))
      p([1, 2, 3].lazy.minmax)
      p([1, 2, 3].lazy.sort)
      p([1, 2, 3].lazy.reduce(:+))
      p([3, 1, 2].lazy.sort_by { |x| -x })
      p([1, 2, 3].lazy.map { |x| x * 2 }.sum)
      p([1, 2, 3].lazy.select { |x| x > 1 }.count)

      # the fused terminals are unchanged
      p([1, 2, 3].lazy.to_a)
      p([1, 2, 3].lazy.first(2))
      p([1, 2, 3].lazy.map { |x| x + 1 }.to_a)
      p((1..Float::INFINITY).lazy.map { |x| x * 2 }.first(3))
    RUBY

    _(result).must_answer <<~'OUT'
      6
      3
      1
      3
      true
      false
      [1, 3]
      [1, 2, 3]
      6
      [3, 2, 1]
      12
      2
      [1, 2, 3]
      [1, 2]
      [2, 3, 4]
      [2, 4, 6]
    OUT
  end

  it "map each cons typed" do
    result = ze0(<<~'RUBY')
      # Typed block results through each_cons(n).map and each_cons(n).with_index.map
      # must collect the real values. Guards the emit_boxed refactor of these
      # collecting emitters against regressing the typed (non-poly) path.
      p [1, 2, 3, 4].each_cons(2).map { |a, b| a + b }
      p [1, 2, 3, 4].each_cons(2).map { |pair| pair.sum }
      p %w[a b c].each_cons(2).map { |x, y| "#{x}#{y}" }
      p [10, 20, 30].each_cons(2).with_index.map { |pair, i| pair.sum + i }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 5, 7]
      [3, 5, 7]
      ["ab", "bc"]
      [30, 51]
    OUT
  end

  it "map untyped block result" do
    result = ze0(<<~'RUBY')
      # An untyped block result (here a read of an unassigned ivar, which is untyped
      # and evaluates to nil) collected by map / each_cons must produce nil elements,
      # never crash or mis-box. Covers the area of the untyped-into-poly-array boxing
      # fix (the RBS-typed reproducer lives in test/rbs-seed/map_untyped_poly.rb).
      class Collector
        def plain(arr);           arr.map { |x| @sink };                          end
        def cons(arr);            arr.each_cons(2).map { |pair| @sink };          end
        def cons_with_index(arr); arr.each_cons(2).with_index.map { |p, i| @sink }; end
      end

      c = Collector.new
      p c.plain([1, 2, 3])
      p c.cons([1, 2, 3, 4])
      p c.cons_with_index([1, 2, 3, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, nil, nil]
      [nil, nil, nil]
      [nil, nil, nil]
    OUT
  end

  it "obj array sort typed" do
    result = ze0(<<~'RUBY')
      # No-block sort/sort!/min/max over arrays of user objects. A local touched
      # only by modeled ops narrows to the typed object-array representation (the
      # runtime compares through the cmp hook); a component whose sort result
      # escapes into an unmodeled consumer stays on the boxed poly path -- the
      # behavior is identical either way. A class without <=> raises like CRuby.
      class Money
        include Comparable
        attr_reader :cents
        def initialize(cents); @cents = cents; end
        def <=>(other); cents <=> other.cents; end
      end

      # narrowed: only admitted ops touch this local and its sort alias
      bag = [Money.new(30), Money.new(10), Money.new(20)]
      sorted = bag.sort
      p sorted.first.cents
      p sorted.last.cents
      p bag.min.cents
      p bag.max.cents
      p bag.first.cents        # sort is a copy; the receiver is unchanged
      bag.sort!
      p bag.first.cents        # sort! reorders in place

      # escaping consumer: the component stays poly (boxed hook path)
      esc = [Money.new(3), Money.new(1), Money.new(2)]
      p esc.sort.length

      # empty array: min/max are nil
      none = [Money.new(1)]
      none.sort!
      p none.min.nil?

      # equal-comparing elements: tied elements land in the order of the C
      # library's qsort_r, as CRuby's do
      class Card
        include Comparable
        attr_reader :rank, :tag
        def initialize(rank, tag); @rank = rank; @tag = tag; end
        def <=>(other); rank <=> other.rank; end
      end
      deck = [Card.new(1, 0), Card.new(0, 1), Card.new(1, 2), Card.new(0, 3), Card.new(1, 4)]
      ordered = deck.sort
      p ordered.map(&:tag)

      # a class without <=> cannot compare, matching CRuby's error
      class NoCmp
        attr_reader :v
        def initialize(v); @v = v; end
      end
      plain = [NoCmp.new(2), NoCmp.new(1)]
      begin
        plain.sort
        puts "no raise"
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      10
      30
      10
      30
      30
      10
      3
      false
      [1, 3, 0, 2, 4]
      comparison of NoCmp with NoCmp failed
    OUT
      10
      30
      10
      30
      30
      10
      3
      false
      [3, 1, 0, 2, 4]
      comparison of NoCmp with NoCmp failed
    LINUX
  end

  it "redefined array each beats the splice" do
    _(ze0(<<~'RUBY')).must_answer "\"REDEFINED\"\n"
      # A reopen of `Array#each` makes the splice illegal: `iter_inline_ok_for`
      # answers false and the site's other arm -- an ordinary block send -- is
      # what finds the new definition. Without that guard a fused site would
      # keep walking the array and never call the method at all.
      class Array
        def each(&b) = "REDEFINED"
      end
      a = [1, 2, 3]
      p a.each { |x| x }
    RUBY
  end

  it "two spliced loops in one scope each own their local" do
    result = ze0(<<~'RUBY')
      # Both loops splice into the enclosing scope and both first-assign `r`, so
      # each gets storage of its own for its loop's extent. The two storages are
      # registered under synthetic keys, and a key collision left the first loop's
      # value with no release -- visible only under `ZEO_RT_LEAKCHECK`, which the
      # memcheck leg runs over every golden.
      1.times do |i|
        r = "a" + i.to_s
        p r
      end
      1.times do
        r = "c" + "d"
        p r
      end

      # The same pair with the parameter on the second loop instead.
      2.times do
        s = "e" * 2
        p s
      end
      2.times do |i|
        s = "f" * i
        p s
      end

      # ...and with an accumulating kind between them, whose accumulator slot takes
      # a synthetic key from the same counter.
      p (1..3).map { |i| "m#{i}" }
      1.times do |i|
        r = "g" + i.to_s
        p r
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "a0"
      "cd"
      "ee"
      "ee"
      ""
      "f"
      ["m1", "m2", "m3"]
      "g0"
    OUT
  end

  it "typed array each fuses under a guard" do
    result = ze0(<<~'RUBY')
      # `arr.each { }` on a statically-`Array` receiver splices the block body
      # into a native loop. Unlike the literal `n.times` shape, the receiver's
      # class here is a compile-time BELIEF, so the site asks TWO runtime
      # questions before it may splice, and either can say no:
      #
      #   - is the value really an Array (a local analyze typed as one can hold
      #     anything by the time the loop runs)
      #   - may a splice stand in for `Array#each` (a reopen, a per-object
      #     singleton, or a box makes real dispatch the only correct answer)
      #
      # with an ordinary block send on the other arm. Everything below has to
      # behave the same whichever arm runs, which is what this file checks.
      a = [1,2,3]
      r = a.each { |x| print x }
      puts
      p r.equal?(a)
      # break, next, redo-free control
      p(a.each { |x| break x * 10 if x == 2 })
      s = 0
      a.each { |x| next if x == 2; s += x }
      p s
      # growth while walking: CRuby re-reads the length
      b = [1]
      n = 0
      b.each { |x| n += 1; b << x + 1 if b.size < 4 }
      p [b, n]
      # a block that escapes captures a fresh binding per iteration
      procs = []
      a.each { |x| procs << -> { x } }
      p procs.map(&:call)
      # an empty array
      p([].each { |x| raise "never" })
      # NOT an array at run time, though analyze may believe otherwise
      c = [1,2]
      c = "ab" if ARGV[0]
      p c.each { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      123
      true
      20
      4
      [[1, 2, 3, 4], 4]
      [1, 2, 3]
      []
      [1, 2]
    OUT
  end

  it "user redefinition unfuses the new iterator kinds" do
    result = ze0(<<~'RUBY')
      class Array
        def detect
          :from_the_reopen
        end

        def reduce(seed)
          :also_from_the_reopen
        end
      end

      arr = [1, 2, 3]

      # An alias and its twin are separate method entries, so redefining either one
      # takes the whole kind off the fused path.
      p arr.find { |x| x > 1 }
      p arr.detect { |x| x > 1 }
      p arr.inject(0) { |a, b| a + b }
      p arr.reduce(0) { |a, b| a + b }

      # The kinds nobody touched still answer normally.
      p arr.count { |x| x > 1 }
      p arr.none? { |x| x > 9 }
      p arr.all? { |x| x > 0 }
      p arr.any? { |x| x > 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      2
      :from_the_reopen
      6
      :also_from_the_reopen
      2
      true
      true
      true
    OUT
  end
end
