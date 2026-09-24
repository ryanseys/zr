# frozen_string_literal: true

require "spec_helper"

describe "Range: slicing" do
  it "boolean range outside a condition" do
    result = zr(<<~'RUBY')
      # A `cond..cond` expression is only a flip-flop in a conditional context;
      # anywhere else it builds a Range, and a Range of booleans raises
      # ArgumentError ("bad value for range") the moment it is compared. zr treats
      # the block-body form as a flip-flop and happily yields values. The
      # if-modifier control below is a REAL flip-flop and works on both sides.
      picked = []
      %w[a START b END c].each do |l|
        picked << l if (l == "START")..(l == "END")
      end
      puts picked.inspect

      begin
        r = (1..20).select { |i| (i % 5 == 1)..(i % 5 == 3) }
        puts r.inspect
      rescue ArgumentError => e
        puts "select: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["START", "b", "END"]
      select: bad value for range
    OUT
  end

  it "conv nil and range errors" do
    result = zr(<<~'RUBY')
      # The exact CRuby error shapes: the special lowercase nil message at
      # NUM2LONG sites, the generic shapes elsewhere, RangeError for
      # out-of-range floats and bignums.
      def err
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      err { [1, 2] * nil }
      err { [1, 2, 3][nil] }
      err { [1, 2, 3].first(nil) }
      err { [1, 2, 3].take(nil) }
      err { "ab" * nil }
      err { "abc".split(",", nil) }
      err { [1] + nil }
      err { [1] + 5 }
      err { [1].concat(:x) }
      err { {} < 1 }
      err { {}.merge(1) }
      err { "a" + 1 }
      err { "a" << 1.5 }
      err { "a" << nil }
      err { [1, 2, 3][1e300] }
      err { [1, 2, 3].first(2**64) }
      err { "x" * (2**64) }
      err { [1, 2].zip(1) }
      err { [1].pack(1) }
      err { "A".unpack(1) }
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion from nil to integer
      TypeError: no implicit conversion of nil into Array
      TypeError: no implicit conversion of Integer into Array
      TypeError: no implicit conversion of Symbol into Array
      TypeError: no implicit conversion of Integer into Hash
      TypeError: no implicit conversion of Integer into Hash
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Float into String
      TypeError: no implicit conversion of nil into String
      RangeError: float 1e+300 out of range of integer
      RangeError: bignum too big to convert into 'long'
      RangeError: bignum too big to convert into 'long'
      TypeError: wrong argument type Integer (must respond to :each)
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Integer into String
    OUT
  end

  it "endless and beginless range max min raise rather than hang" do
    result = zr(<<~'RUBY')
      # `#max` on an endless range and `#min` on a beginless range have no
      # answer -- CRuby raises RangeError instead of iterating (which would loop
      # forever). `(1..).min` still returns the begin (an endless range has a
      # minimum). Regression: these used to hang the program.

      def t; yield; rescue RangeError => e; e.message; end
      puts t { (1..).max }
      puts t { (1...).max }
      puts t { (1.0..).max }
      puts t { (..5).min }
      puts((1..).min)
    RUBY

    _(result).must_answer <<~'OUT'
      cannot get the maximum of endless range
      cannot get the maximum of endless range
      cannot get the maximum of endless range
      cannot get the minimum of beginless range
      1
    OUT
  end

  it "endless range count hangs" do
    result = zr(<<~'RUBY')
      # `(1..).count` hangs forever. Ruby answers `Infinity`.
      #
      # `Range#count` routes to `enumerable::count_own`, which walks `each`. An
      # endless range's `each` never stops, so the walk never returns. Ruby special-
      # cases a range with no end (and no block/argument) and answers
      # `Float::INFINITY` without iterating (`range.c`'s `range_count`).
      #
      # `size` already answers `Infinity` for the same range, so the information the
      # count needs is present -- `count` just does not ask for it. A block or an
      # argument DOES have to iterate and legitimately never terminates, which is why
      # only the no-argument form can take the shortcut.

      r = (1..)
      p r.size
      p r.count
    RUBY

    _(result).must_answer "Infinity\nInfinity\n"
  end

  it "endless range refuses to set" do
    result = zr(<<~'RUBY')
      # Range#to_set is Range's own row: an endless range raises before
      # Enumerable's walk would run forever.

      p (1..3).to_set, (1...3).to_set, ("a".."c").to_set
      begin
        (1..).to_set
      rescue RangeError => e
        p e
      end
      p Range.instance_method(:to_set).owner, Range.instance_method(:to_set).arity

    RUBY

    _(result).must_answer <<~'OUT'
      Set[1, 2, 3]
      Set[1, 2]
      Set["a", "b", "c"]
      #<RangeError: cannot convert endless range to a set>
      Range
      -1
    OUT
  end

  it "endless range reverse each is lazy" do
    result = zr(<<~'RUBY')
      # `(1..).reverse_each` answers an Enumerator (the raise comes only when it
      # is iterated); zr raises TypeError at the call. (Found by the 2026-08-24
      # probe sweep.)
      e = (1..).reverse_each
      puts e.class
      begin
        e.next
      rescue TypeError => err
        puts err.message
      end
    RUBY

    _(result).must_answer "Enumerator\ncan't iterate from NilClass\n"
  end

  it "endless source stops at the first answer" do
    result = zr(<<~'RUBY')
      # The short-circuiting Enumerable methods stop the SOURCE, not just their own
      # scan, so they answer over an endless one. Each of these used to collect the
      # whole source first and so never returned.
      #
      # `find_index` is the one with no spinel coverage: it asks the same question as
      # `find`, which always stopped early, so the two disagreeing on an endless
      # source was a bug rather than a stated limitation.

      # take_while over an endless Range, an Enumerator, and a user Enumerable.
      p((1..).take_while { |x| x < 4 })
      p(Enumerator.produce(1) { |n| n + 1 }.take_while { |n| n < 5 })

      class Inf
        include Enumerable
        def each
          i = 1
          loop { yield i; i += 1 }
        end
      end
      p(Inf.new.take_while { |x| x < 3 })

      # find_index, both forms, on an endless source.
      p((1..).find_index { |x| x * x > 30 })
      p((10..).find_index(13))
      p(Inf.new.find_index { |x| x > 2 })

      # ... and the finite answers stay the same, including the misses.
      p([1, 2, 3].find_index { |x| x > 9 })
      p([1, 2, 3].find_index(9))
      p([5, 6, 7].find_index(6))

      # each_slice / each_cons roll a buffer instead of materializing the source.
      p((1..).each_slice(2).first(2))
      p((1..).each_cons(3).first(2))
      p((1..).each_slice(3).first(1))

      # A short final slice still yields; a source shorter than the window yields
      # nothing at all.
      p([1, 2, 3, 4, 5].each_slice(2).to_a)
      p([1, 2].each_cons(5).to_a)
      p([1, 2, 3, 4].each_cons(2).to_a)

      # drop_while stays eager (its answer is the tail) and keeps its answer.
      p([1, 2, 3, 1, 2].drop_while { |x| x < 3 })
      p([1, 2, 3].drop_while { |x| x > 9 })

      # A `break` in the predicate belongs to the CALLER, and must not be read as the
      # internal stop these methods use to halt the source.
      p([1, 2, 3].take_while { |x| break :broke_tw })
      p([1, 2, 3].find_index { |x| break :broke_fi })
      p([1, 2, 3, 4].each_slice(2) { |s| break s })
      p([1, 2, 3, 4].each_cons(2) { |c| break c })
      p((1..).take_while { |x| break :endless_break })

      # The block forms answer the receiver.
      p([1, 2, 3, 4].each_slice(2) { |_s| nil })
      p([1, 2, 3, 4].each_cons(2) { |_c| nil })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3, 4]
      [1, 2]
      5
      3
      2
      nil
      nil
      1
      [[1, 2], [3, 4]]
      [[1, 2, 3], [2, 3, 4]]
      [[1, 2, 3]]
      [[1, 2], [3, 4], [5]]
      []
      [[1, 2], [2, 3], [3, 4]]
      [3, 1, 2]
      [1, 2, 3]
      :broke_tw
      :broke_fi
      [1, 2]
      [1, 2]
      :endless_break
      [1, 2, 3, 4]
      [1, 2, 3, 4]
    OUT
  end

  it "flip flop operator" do
    result = zr(<<~'RUBY')
      # The flip-flop operator: `cond1..cond2` used AS a condition is a two-state
      # latch, not a Range. Two dots retest the right operand in the evaluation that
      # turned the latch on; three dots wait for the next one. An omitted side is nil,
      # so it never fires. Each syntactic occurrence owns its latch, and that latch
      # survives between separate runs of the loop it sits in.
      two_dot = []
      (1..8).each { |i| two_dot << i if (i == 3)..(i == 6) }
      p two_dot

      three_dot = []
      (1..8).each { |i| three_dot << i if (i == 3)...(i == 6) }
      p three_dot

      # Same operand on both sides: two dots span one iteration, three dots never
      # close, because the right operand is only ever tested after the latch is on.
      one_shot = []
      (1..8).each { |i| one_shot << i if (i == 3)..(i == 3) }
      p one_shot

      never_closes = []
      (1..8).each { |i| never_closes << i if (i == 3)...(i == 3) }
      p never_closes

      # Beginless never turns on; endless never turns off.
      beginless = []
      (1..5).each { |i| beginless << i if ..(i == 3) }
      p beginless

      endless = []
      (1..5).each { |i| endless << i if (i == 2).. }
      p endless

      # Two occurrences in one loop body keep separate latches.
      pairs = []
      (1..6).each do |i|
        a = false
        b = false
        a = true if (i == 2)..(i == 3)
        b = true if (i == 4)..(i == 5)
        pairs << [i, a, b]
      end
      p pairs

      # One occurrence keeps its latch across separate runs of its loop: the second
      # pass starts with the latch still off, having closed on 3 in the first.
      across = []
      2.times { (1..4).each { |i| across << i if (i == 2)..(i == 3) } }
      p across
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5, 6]
      [3, 4, 5, 6]
      [3]
      [3, 4, 5, 6, 7, 8]
      []
      [2, 3, 4, 5]
      [[1, false, false], [2, true, false], [3, true, false], [4, false, true], [5, false, true], [6, false, false]]
      [2, 3, 2, 3]
    OUT
  end

  it "integer range fills its array at once" do
    result = zr(<<~'RUBY')
      # (a..b).to_a over two Integers is one fill, not a yield per element:
      # the same Array either way, exclusive ends, empty and reversed ranges,
      # entries, and a Range whose ends are not both fixnums still walks each.
      p (1..5).to_a, (1...5).to_a, (5..1).to_a, (3...3).to_a, (-2..2).to_a, (0..0).to_a, (1..1).entries
      p (1..100_000).to_a.sum, (1..100_000).to_a.size, (2**62..2**62 + 2).to_a, ((2**62 - 1)...(2**62 + 1)).to_a
      p ("a".."e").to_a, (1.0..3.0).to_a rescue p $!.class
      p ((1..).to_a rescue $!.class), (nil..3).to_a rescue p $!.class
      class Range
        alias old_each each
        def each(&b)
          $walked = true
          old_each(&b)
        end
      end
      $walked = false
      p (1..3).to_a, $walked
      p Range.new(1, 3).to_a, (1..3).to_a.frozen?, (1..3).to_a.equal?((1..3).to_a)

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4]
      []
      []
      [-2, -1, 0, 1, 2]
      [0]
      [1]
      5000050000
      100000
      [4611686018427387904, 4611686018427387905, 4611686018427387906]
      [4611686018427387903, 4611686018427387904]
      TypeError
      TypeError
      [1, 2, 3]
      true
      [1, 2, 3]
      false
      false
    OUT
  end

  it "lazy range local" do
    result = zr(<<~'RUBY')
      # Enumerator::Lazy over a range held in a local variable.
      r = (1..9)
      p r.lazy.map { |x| x * x }.first(3)
      p r.lazy.select { |x| x.even? }.first(2)
    RUBY

    _(result).must_answer "[1, 4, 9]\n[2, 4]\n"
  end

  it "lazy range method" do
    result = zr(<<~'RUBY')
      # Enumerator::Lazy over a range returned from a method.
      def src; (1..9); end
      p src.lazy.map { |x| x }.first(3)
      p src.lazy.map { |x| x * 2 }.first(4)
    RUBY

    _(result).must_answer "[1, 2, 3]\n[2, 4, 6, 8]\n"
  end

  it "one sided range answers min and max without walking" do
    result = zr(<<~'RUBY')
      # `min`/`max`/`last` on a one-sided range are answered from the endpoints, not
      # by iterating: an endless range would never finish counting up to its maximum,
      # and a beginless one cannot even start.
      #
      # `min(n)` is the first n counting UP from begin -- which is why an endless
      # range can answer it -- and `max(n)` the n largest counting DOWN from end.

      # Endless: min counts up and stops, max has no answer at all.
      p((1..).min)
      p((1..).min(3))
      p((5..).min(2))
      p((1..).min(0))
      p(((1..).max rescue $!.class))
      p(((1..).last(2) rescue $!.class))
      p(((1..).to_a rescue $!.class))

      # Beginless: max counts down from the end, exclusive ends start one lower.
      p((..5).max)
      p((..5).max(2))
      p((..5).max(3))
      p((...5).max)
      p((...5).max(3))
      p((..5).max(0))
      p(((..5).min rescue $!.class))

      # A Float end has no decrementable element, so a beginless float range keeps
      # ruby's answers rather than being counted down.
      p((..5.0).max)
      p(((...5.0).max rescue $!.class))
      p(((..5.0).max(2) rescue $!.class))

      # A custom comparator has to walk, so the open side has no answer.
      p(((1..).min { |a, b| a <=> b } rescue $!.class))
      p(((1..).min(3) { |a, b| a <=> b } rescue $!.class))
      p(((..5).max { |a, b| a <=> b } rescue $!.class))

      # Bounded ranges are unchanged, including a comparator, a count past the end,
      # an exclusive end, a descending range, and non-numeric elements.
      p((1..5).min(2))
      p((1..5).max(2))
      p((1...5).max(2))
      p((1..5).min(9))
      p((1..5).max(9))
      p((1..5).min(2) { |a, b| b <=> a })
      p((1..5).max(2) { |a, b| b <=> a })
      p((5..1).min(2))
      p((5..1).max(2))
      p(("a".."e").min(2))
      p(("a".."e").max(2))
      p((1..5.0).min(2))
      p(((1.0..5.0).min(2) rescue $!.class))
      p((1..5).last(2))
      p((1...5).last(2))

      # A negative count is an ArgumentError on either side.
      p(((..5).max(-1) rescue $!.message))
      p(((1..).min(-1) rescue $!.message))

      # A non-Integer count converts.
      p((1..).min(3.0))
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2, 3]
      [5, 6]
      []
      RangeError
      RangeError
      RangeError
      5
      [5, 4]
      [5, 4, 3]
      4
      [4, 3, 2]
      []
      RangeError
      5.0
      TypeError
      TypeError
      RangeError
      RangeError
      RangeError
      [1, 2]
      [5, 4]
      [4, 3]
      [1, 2, 3, 4, 5]
      [5, 4, 3, 2, 1]
      [5, 4]
      [1, 2]
      []
      []
      ["a", "b"]
      ["e", "d"]
      [1, 2]
      TypeError
      [4, 5]
      [3, 4]
      "negative array size (or size too big)"
      "negative array size (or size too big)"
      [1, 2, 3]
    OUT
  end

  it "print range argument" do
    result = zr(<<~'RUBY')
      # p / puts / print previously fell through to the unsupported-argument
      # diagnostic when handed a Range. Integer ranges render as "first..last"
      # ("first...last" when the end is excluded). Receivers are exercised both as
      # literals and through a method parameter so the value path is covered.

      p 1..3
      p 1...5
      p(-3..-1)
      p 5..5

      x = 10..20
      p x

      puts 1..3
      print 1..3
      puts

      def show(r)
        p r
        puts r
        print r
        puts
      end

      show(2..8)
      show(7...7)
    RUBY

    _(result).must_answer <<~'OUT'
      1..3
      1...5
      -3..-1
      5..5
      10..20
      1..3
      1..3
      2..8
      2..8
      2..8
      7...7
      7...7
      7...7
    OUT
  end

  it "Basic Range methods" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      r0 = (1..10)
      puts r0.first             # 1
      puts r0.last              # 10
      puts r0.include?(5)       # true
      puts r0.include?(11)      # false

      arr0 = r0.to_a
      puts arr0.length          # 10
      puts arr0.sum             # 55

      total = 0
      r0.each do |x|
        total += x
      end
      puts total                # 55
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      10
      true
      false
      10
      55
      55
      done
    OUT
  end

  it "cover? / min / max / count" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      puts (1..10).cover?(5)
      puts (1..10).cover?(1)
      puts (1..10).cover?(10)
      puts (1..10).cover?(0)
      puts (1..10).cover?(11)
      puts (-5..5).cover?(0)
      puts (-5..5).cover?(-5)
      puts (-5..5).cover?(6)

      puts (1..10).min
      puts (1..10).max
      puts (-5..5).min
      puts (-5..5).max
      puts (100..200).min
      puts (100..200).max

      puts (1..10).count
      puts (1..1).count
      puts (-5..5).count
      puts (100..200).count

      puts (1...10).count
      puts (1...1).count
      puts (-5...5).count
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      true
      false
      1
      10
      -5
      5
      100
      200
      10
      1
      11
      101
      9
      0
      10
    OUT
  end

  it "map over a range collects one value an element, inclusive or exclusive" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      puts (0..3).map { |i| i * 10 }.length      # 4
      puts (0..3).map { |i| i * 10 }[2]          # 20
      puts (0...3).map { |i| i }.length          # 3
      puts (0...3).map { |i| i }[2]              # 2
      puts ((1..3).map { |i| "x#{i}" }.join(","))   # x1,x2,x3
      puts ((0...3).map { |i| i * 0.5 }.length)     # 3
    RUBY

    _(result).must_answer <<~'OUT'
      4
      20
      3
      2
      x1,x2,x3
      3
    OUT
  end

  it "Inclusive vs exclusive (slicing / for-in / Range#to a / case-when)" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      ia = [10, 20, 30, 40, 50]
      puts ia[1..3].length      # 3 (inclusive)
      puts ia[1...3].length     # 2 (exclusive)
      puts ia[1...3][0]         # 20
      puts ia[1...3][1]         # 30

      sa = "a,b,c,d,e".split(",")
      puts sa[0..2].join(":")   # a:b:c
      puts sa[0...2].join(":")  # a:b

      fa = [1.5, 2.5, 3.5, 4.5]
      puts fa[0..2].length      # 3
      puts fa[0...2].length     # 2
      puts fa[0...3].sum        # 7.5

      s = "abcdef"
      puts s[1..3]              # bcd
      puts s[1...3]             # bc

      sum_inc = 0
      for ix in 1..3
        sum_inc = sum_inc + ix
      end
      puts sum_inc              # 6

      sum_exc = 0
      for ix in 1...3
        sum_exc = sum_exc + ix
      end
      puts sum_exc              # 3

      puts (1..3).to_a.length   # 3
      puts (1...3).to_a.length  # 2

      def classify(n)
        case n
        when 0...10 then "small"
        when 10..99 then "medium"
        else "large"
        end
      end
      puts classify(5)
      puts classify(9)
      puts classify(10)
      puts classify(99)
      puts classify(100)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      20
      30
      a:b:c
      a:b
      3
      2
      7.5
      bcd
      bc
      6
      3
      3
      2
      small
      small
      medium
      medium
      large
    OUT
  end

  it "=== is true for a value inside the range, endpoints included" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      puts (1..10) === 5      # true
      puts (1..10) === 1      # true
      puts (1..10) === 10     # true
      puts (1..10) === 0      # false
      puts (1..10) === 11     # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
    OUT
  end

  it "step without block param" do
    result = zr(<<~'RUBY')
      # Range methods — first / last / include? / to_a / each, cover? /
      # min / max / count, Range#map, inclusive-vs-exclusive distinction,
      # step without block param. Was five separate tests; merged here.
      # No class collisions. The only top-level def (`classify` in the
      # inclusive/exclusive section) is unique within the file. Local
      # names use per-section prefixes where the original tests reused
      # generic names like `r`, `sum`, `i`.


      # `Integer#step` with a do-block that omits its parameter used a
      # synthesized `_i` index that wasn't declared. Two paramless `step`
      # blocks in the same function also redefined it.
      sum_step = 0
      1.step(10, 1) do
        sum_step += 1
      end
      1.step(5, 1) do
        sum_step += 10
      end
      1.step(5, 1) do
        sum_step += 100
      end
      puts sum_step
    RUBY

    _(result).must_answer "560\n"
  end

  it "cover?, include? and === answer false for an argument they cannot compare" do
    result = zr(<<~'RUBY')
      r = ((1..5).cover?("x") rescue $!.class)
      p r

      r = ((1..5).include?("x") rescue $!.class); p r
      r = ((1..5).member?("x") rescue $!.class); p r
      r = ((1..5) === "x" rescue $!.class); p r
      r = ((1..5).first("x") rescue $!.class); p r
      r = ((1..5).each_slice("x") { |s| } rescue $!.class); p r

      r = ((1..5).eql?(1.0..5.0) rescue $!.class); p r

      r = ((1..5) == (1.0..5.0) rescue $!.class); p r
      r = ((1..5).cover?(3) rescue $!.class); p r
      r = (("a".."e").include?("c") rescue $!.class); p r
      r = ((1..5).take(2) rescue $!.class); p r
      r = ((1..5).eql?(1..5) rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      TypeError
      TypeError
      false
      true
      true
      true
      [1, 2]
      true
    OUT
  end

  it "begin and end are the aliases of first and last" do
    result = zr(<<~'RUBY')
      # Three small adjacent fixes:
      #   - Range#begin / Range#end (aliases of first / last)
      #   - Array#include? on poly_array
      #   - String#delete_prefix! / delete_suffix! on mutable_str

      puts (1..10).begin
      puts (1..10).end

      a = [1, "hello", 3.0]
      puts a.include?(1)
      puts a.include?("hello")
      puts a.include?(3.0)
      puts a.include?(99)

      s = String.new("hello world")
      s.delete_prefix!("hello ")
      puts s.to_s

      s2 = String.new("hello world")
      s2.delete_suffix!(" world")
      puts s2.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      1
      10
      true
      true
      true
      false
      world
      hello
    OUT
  end

  it "reverse_each walks down from the end, beginless or not" do
    result = zr(<<~'RUBY')
      r = []; (..5).reverse_each { |x| break if x < 3; r << x }; p r

      p((1..5).reverse_each.to_a)   # => [5, 4, 3, 2, 1]
      p(("a".."e").reverse_each.to_a)

      acc = []
      (...4).reverse_each { |x| break if x < 1; acc << x }
      p acc
      n = 0
      (..10).reverse_each { |x| n += x; break if x <= 8 }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 4, 3]
      [5, 4, 3, 2, 1]
      ["e", "d", "c", "b", "a"]
      [3, 2, 1]
      27
    OUT
  end

  it "each_slice, each_cons and each_with_index with no block roll a window through an endless range" do
    result = zr(<<~'RUBY')
      # A blockless `each_slice`/`each_cons`/`each_with_index` over an ENDLESS Range
      # answers, because the Enumerator it returns re-invokes the block form, and
      # those roll a buffer through the source instead of materializing it first.
      #
      # The trailing comments record what spinel answered; zr answers ruby's.
      r = ((1..5).cycle(2).to_a rescue $!.class)
      p r

      r = ((1..5).each_entry.to_a rescue $!.class); p r        # Ruby: [1, 2, 3, 4, 5]      Spinel: NoMethodError
      r = ((1..).each_slice(2).first(2) rescue $!.class); p r  # Ruby: [[1, 2], [3, 4]]     Spinel: RangeError

      r = ((1..).each_cons(2).first(2) rescue $!.class); p r        # Ruby: [[1, 2], [2, 3]]   Spinel: RangeError
      r = ((1..).each_with_index.first(2) rescue $!.class); p r     # Ruby: [[1, 0], [2, 1]]   Spinel: NoMethodError

      p((1..3).each_with_index.to_a)   # => [[1, 0], [2, 1], [3, 2]]

      o = []; (1..3).cycle(2) { |x| o << x }; p o    # => [1, 2, 3, 1, 2, 3]
      o = []; (1..3).each_entry { |x| o << x }; p o   # => [1, 2, 3]

      r = ((1..).each_slice(3).first(1) rescue $!.class); p r
      r = ((5..).each_with_index.first(3) rescue $!.class); p r
      r = ((1..).lazy.with_index(10).first(2) rescue $!.class); p r
      r = ([1, 2, 3, 4].each_cons(2).to_a rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      [[1, 2], [3, 4]]
      [[1, 2], [2, 3]]
      [[1, 0], [2, 1]]
      [[1, 0], [2, 1], [3, 2]]
      [1, 2, 3, 1, 2, 3]
      [1, 2, 3]
      [[1, 2, 3]]
      [[5, 0], [6, 1], [7, 2]]
      [[1, 10], [2, 11]]
      [[1, 2], [2, 3], [3, 4]]
    OUT
  end

  it "all?, any?, none? and one? take a block, a pattern, or nothing" do
    result = zr(<<~'RUBY')
      p((1..5).all?)
      p((1..5).any?)
      p((1..5).none?)
      p((1..5).one?)
      p((1..1).one?)
      p((1..5).sum)
      p((1..5).count)
      p((1..5).all? { |x| x > 0 })
      p((1..5).all?(Integer))
      p((1..5).any?(String))
      p((1..5).none?(String))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      15
      5
      true
      true
      false
      true
    OUT
  end

  it "=== of a range against a range is false, and cover? of one is true" do
    result = zr(<<~'RUBY')
      p((1..5) === (2..4))
      p((1..5) === (1..5))
      p((1..5) === 3)
      p((1...5) === (2..5))
      p (1..5).cover?(2..4)
      p (1..5).cover?(0..4)
      p (1..5).include?(2..4)
      p (1..5).member?(2..4)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      false
      true
      false
      false
      false
    OUT
  end

  it "a String range answers false for an argument that is not a string" do
    result = zr(<<~'RUBY')
      # Range#=== (and cover?/include?) on a String range with a non-String argument
      # returns false, like CRuby, rather than feeding a non-pointer to strcmp (which
      # segfaulted). String-in-string-range and numeric ranges are unaffected.
      p(('A'..'C') === 20)
      p(('A'..'C') === 'B')
      p(('A'..'C') === 'Z')
      p(('a'..'z') === 'm')
      p(('a'..'z').cover?(5))
      p((1..5) === 3)
      p((1..5) === 9)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
      true
      false
    OUT
  end

  it "a case arm matches through cover?, not through equality" do
    result = zr(<<~'RUBY')
      # `Range#===` IS `#cover?` -- what makes `case x when 1..50` actually
      # match (previously it fell to structural equality and silently never
      # did). Endpoint semantics oracle-verified incl. exclusive ends, floats,
      # and incomparable-subject false.

      case 42
      when 1..50 then puts "hit"
      else puts "miss"
      end

      x = [5.5].first
      puts (1..5) === x
      puts (1..6) === x
      puts (1...5) === 5
      puts (1..5).cover?(3)
      puts (1..5).include?("x")
      case "c"
      when "a".."f" then puts "letter"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hit
      false
      true
      false
      true
      false
      letter
    OUT
  end

  it "the Comparable and slicing methods over char, beginless and endless ranges" do
    result = zr(<<~'RUBY')
      # Range: char-range variables, beginless/endless membership, min(n)/max(n),
      # take/drop/reverse_each/filter_map, % (step), clamp(range) incl. variables,
      # and Comparable between?/clamp on a custom class.
      cr = ('a'..'e'); p(cr.to_a)
      p((..5).include?(3))
      p((..5).include?(7))
      p((6..).include?(7))
      p((1..10).min(3))
      p((1..10).max(3))
      p((1..5).take(3))
      p((1..3).reverse_each.to_a)
      p((1..5).filter_map { |x| x * 10 if x.odd? })
      r = (((1..10) % 3).to_a rescue "no each"); p r
      rv = (1..10); r2 = (15.clamp(rv) rescue "no clamp"); p r2
      p(0.clamp(rv))
      p(5.clamp(rv))
      p((1..10).min(3))
      p((1..10).max(3))
      p((1..5).take(3))
      p((1..5).drop(3))
      p((1..3).reverse_each.to_a)
      p((1..5).filter_map { |x| x * 10 if x.odd? })
      r = (((1..10) % 3).to_a rescue "no each"); p r
      p(((0..20) % 5).to_a)
      p((..5).include?(3))
      p((..5).include?(7))
      p((6..).include?(7))
      p((6..).include?(2))
      p((..5).cover?(5))
      p((...5).include?(5))
      p((1..3).include?(2))
      p((3..1).include?(2))
      rv = (1..10)
      r = (15.clamp(rv) rescue "no clamp"); p r
      p(0.clamp(rv))
      p(5.clamp(rv))
      p(15.clamp(1..10))
      cr = ('a'..'e'); p(cr.to_a)
      p(cr.include?('c'))
      p(cr.map { |ch| ch.upcase })
      class Ver139
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      p(Ver139.new(5).between?(Ver139.new(1), Ver139.new(9)))
      p(Ver139.new(0).between?(Ver139.new(1), Ver139.new(9)))
      v = Ver139.new(12).clamp(Ver139.new(1)..Ver139.new(9))
      p v.n
      w = Ver139.new(5).clamp(Ver139.new(1), Ver139.new(9))
      p w.n
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c", "d", "e"]
      true
      false
      true
      [1, 2, 3]
      [10, 9, 8]
      [1, 2, 3]
      [3, 2, 1]
      [10, 30, 50]
      [1, 4, 7, 10]
      10
      1
      5
      [1, 2, 3]
      [10, 9, 8]
      [1, 2, 3]
      [4, 5]
      [3, 2, 1]
      [10, 30, 50]
      [1, 4, 7, 10]
      [0, 5, 10, 15, 20]
      true
      false
      true
      false
      true
      false
      true
      false
      10
      1
      5
      10
      ["a", "b", "c", "d", "e"]
      true
      ["A", "B", "C", "D", "E"]
      true
      false
      9
      5
    OUT
  end

  it "min, max and minmax answer nil for a range whose begin is past its end" do
    result = zr(<<~'RUBY')
      # Range conformance (KieranP #2411-#2415)
      a = ("a".."e")
      p a.begin
      p a.end
      p((5..1).min)
      p((5..1).max)
      p((5..1).minmax)
      p((1...1).min)
      p((1..5).min)
      p((1..5).minmax)
      p((1..).end)
      p((1..5).entries)
      p((1..10).step(3) { |x| }.class)
      r = (1..5)
      p r.begin
      p r.end
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "e"
      nil
      nil
      [nil, nil]
      nil
      1
      [1, 5]
      nil
      [1, 2, 3, 4, 5]
      Range
      1
      5
    OUT
  end

  it "two ranges with the same endpoints are one Hash key and one array element" do
    result = zr(<<~'RUBY')
      p({ ("a".."c") => :s }[("a".."c")])
      p({ (1..3) => :i }[(1..3)])
      p({ (1.0..2.0) => :f }[(1.0..2.0)])
      p [(1..3)].include?(1..3)
      p [(1..3)].index(1..3)
      p [("a".."c")].include?("a".."c")
      p [(1.0..2.0)].include?(1.0..2.0)
      p((1..3) == (1..3))
      p(("a".."c") == ("a".."d"))
    RUBY

    _(result).must_answer <<~'OUT'
      :s
      :i
      :f
      true
      0
      true
      true
      true
      false
    OUT
  end

  it "each over a literal range covers its bounds, an exclusive end included" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Basic bounds ---

      # Inclusive range, accumulator
      sum = 0
      (1..10).each { |i| sum = sum + i }
      puts sum

      # Exclusive range — last value is excluded
      sum_excl = 0
      (1...10).each { |i| sum_excl = sum_excl + i }
      puts sum_excl

      # Negative bounds
      neg_sum = 0
      (-3..3).each { |i| neg_sum = neg_sum + i }
      puts neg_sum

      # Crosses zero, exclusive
      zero_sum = 0
      (-2...2).each { |i| zero_sum = zero_sum + i }
      puts zero_sum

    RUBY

    _(result).must_answer <<~'OUT'
      55
      45
      0
      -2
    OUT
  end

  it "a one-element range yields once and an empty one yields nothing" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Edge sizes ---

      # Single-element inclusive range
      hits = 0
      (7..7).each { |i| hits = hits + 1 }
      puts hits

      # Empty exclusive range (start == end, exclusive)
      empties = 0
      (5...5).each { |i| empties = empties + 1 }
      puts empties

      # Zero-element inclusive range at the origin
      zero_hits = 0
      (0..0).each { |i| zero_hits = zero_hits + 1 }
      puts zero_hits

      # Decreasing range — start > end. CRuby yields zero times; the
      # fused for-loop's `i <= hi` check is false on entry.
      dec_count = 0
      (10..1).each { |i| dec_count = dec_count + 1 }
      puts dec_count

      # Decreasing exclusive range — same zero-iteration shape.
      dec_excl = 0
      (10...1).each { |i| dec_excl = dec_excl + 1 }
      puts dec_excl

    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      1
      0
      0
    OUT
  end

  it "the block parameter of a fused range loop belongs to the block" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Block-param scoping ---

      # Block param doesn't leak when its name is distinct from outer
      # locals. (Same-name shadowing is a pre-existing spinel-wide
      # limitation in compile_each_block — both this fusion path and the
      # generic sp_Range path emit the block param as `lv_<name>`, which
      # collides with an outer `lv_<name>` of the same name. Out of scope
      # for this perf PR; see PR body.)
      outer_v = 42
      (1..5).each { |inner| outer_v = outer_v + inner }
      puts outer_v

    RUBY

    _(result).must_answer <<~'OUT'
      57
    OUT
  end

  it "a range whose bounds are expressions iterates over the values they answer" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Non-trivial bounds ---

      # Non-literal bounds (variable-bounded range) — falls back to the
      # generic sp_Range path. Behaviour must still match.
      lo = 2
      hi = 6
      var_sum = 0
      (lo..hi).each { |x| var_sum = var_sum + x }
      puts var_sum

      # Parens-wrapped range — `((1..5))` is a ParenthesesNode wrapping a
      # RangeNode. The fusion recognizer must unwrap parens before
      # deciding whether to inline.
      p_sum = 0
      ((1..5)).each { |i| p_sum = p_sum + i }
      puts p_sum

    RUBY

    _(result).must_answer <<~'OUT'
      20
      15
    OUT
  end

  it "break and next inside a fused range loop mean what they mean anywhere" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Control flow inside the loop ---

      # `break` exits the loop early; the accumulator captures only the
      # values seen before the break.
      early = 0
      (1..100).each { |i| break if i > 5; early = early + i }
      puts early

      # `next` skips the body for the current iteration; even values
      # contribute, odd values are skipped.
      even_sum = 0
      (1..10).each { |i| next if i % 2 != 0; even_sum = even_sum + i }
      puts even_sum

    RUBY

    _(result).must_answer <<~'OUT'
      15
      30
    OUT
  end

  it "a fused range loop nests inside another" do
    result = zr(<<~'RUBY')
      # Range#each over a literal numeric range should fuse to a tight C
      # for-loop with bounds inlined. Output is identical to the unfused
      # path; this test pins behavioural parity. The perf win shows up in
      # the generated C — no sp_Range struct copy on the loop's hot path.

      # --- Nesting ---

      # Nested ranges
      total = 0
      (1..3).each { |i| (1..3).each { |j| total = total + i * j } }
      puts total

      # Triple-nested with mixed inclusive/exclusive
      mixed = 0
      (1..2).each { |a| (1...3).each { |b| (0..1).each { |c| mixed = mixed + a * b + c } } }
      puts mixed
    RUBY

    _(result).must_answer <<~'OUT'
      36
      22
    OUT
  end

  it "each with no block answers an Enumerator of the elements" do
    result = zr(<<~'RUBY')
      # Range#each without a block returns an Enumerator; spinel materializes
      # the element array so chaining works.
      p((1..3).each.to_a)
      p((1...4).each.to_a)
      p((5..8).each.to_a.length)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      4
    OUT
  end

  it "throw out of a range's each carries its value to the catch" do
    result = zr(<<~'RUBY')
      p(catch(:n) { (1..2).each { throw :n, 7 } })
      v = catch(:n2) { x = (1..2).each { throw :n2, 7 }; x }; p v
      p(catch(:m) { [1, 2].each { |i| throw :m, i } })
      v2 = catch(:t) { [1, 2].each { |i| throw :t, i } }; p v2
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      1
      1
    OUT
  end

  it "take_while, drop_while, a comparator min and max, and bsearch in both modes" do
    result = zr(<<~'RUBY')
      # Range Enumerable forms: take_while/drop_while blocks, comparator min/max,
      # beginless/endless include?/cover?, bsearch find-any vs find-minimum mode,
      # and #to_a on runtime-tagged (poly) receivers including nil.

      def tw(r); r.take_while { |i| i < 4 }; end
      def dw(r); r.drop_while { |i| i < 4 }; end
      p tw(1..6)      # [1, 2, 3]
      p dw(1..6)      # [4, 5, 6]
      p tw(5..8)      # [] (first element fails)
      p dw(5..8)      # [5, 6, 7, 8] (nothing dropped)

      def mx(r); r.max { |a, b| b <=> a }; end
      def mn(r); r.min { |x, y| y <=> x }; end
      p mx(1..5)      # 1 (reversed comparator)
      p mn(1..5)      # 5
      p mx(3..3)      # single element

      def inc(r, v); r.include?(v); end
      def cov(r, v); r.cover?(v); end
      p inc((..5), 1)     # true
      p inc((..5), 5)     # true
      p inc((..5), 6)     # false
      p inc((...5), 5)    # false (exclusive upper)
      p inc((1..), 100)   # true
      p inc((1..), 0)     # false
      p cov((..0), -9)    # true
      p inc(1..5, 3)      # bounded ranges keep working
      p inc(1..5, 9)      # false

      def bs_any(r, t); r.bsearch { |v| t <=> v }; end
      def bs_min(r); r.bsearch { |w| w >= 3 }; end
      p bs_any(0..100, 42)   # 42 (find-any hit)
      p bs_any(0..3, 5)      # nil (target above range)
      p bs_any(4..9, 1)      # nil (target below range)
      p bs_min(0..10)        # 3 (find-minimum mode unchanged)

      def ta(x); x.to_a; end
      p ta(nil)               # []
      p ta([1, "two", 3])     # identity contents
      p ta({a: 1, b: 2})      # [[:a, 1], [:b, 2]]
      begin
        ta(5)
      rescue NoMethodError => e
        puts e.message        # undefined method 'to_a' for an instance of Integer
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [4, 5, 6]
      []
      [5, 6, 7, 8]
      1
      5
      3
      true
      true
      false
      false
      true
      false
      true
      true
      false
      42
      nil
      nil
      3
      []
      [1, "two", 3]
      [[:a, 1], [:b, 2]]
      undefined method 'to_a' for an instance of Integer
    OUT
  end

  it "reduce, group_by, find, count, zip and tally over a range held in a local" do
    result = zr(<<~'RUBY')
      # Enumerable methods on a Range that spinel does not handle natively are served
      # by materializing the range to an int array and dispatching the array method:
      # the non-collecting forms (reduce(:sym)/group_by/find/count/zip/tally). The
      # range is a local so the materialization runs at runtime.
      r = (1..5)

      # reduce / inject with a symbol or an initial value
      p r.reduce(:+)
      p r.inject(:*)
      p r.reduce(100, :+)
      p r.inject(2, :*)

      # group_by returns a Hash of arrays
      p (1..6).group_by { |x| x % 3 }

      # find / detect return the first matching element (or nil)
      p r.find { |x| x > 3 }
      p r.detect(&:even?)
      p r.find { |x| x > 99 }

      # count with a block or an argument (bare count stays Range#size)
      p r.count(&:even?)
      p r.count(3)
      p r.count

      # zip pairs with other collections
      p (1..3).zip([4, 5, 6])
      p (1..3).zip([4, 5, 6], [7, 8, 9])

      # tally counts occurrences
      p (1..3).tally

      # exclusive ranges exercise the `last - excl` materialization bound
      x = (1...5)
      p x.reduce(:+)
      p x.group_by { |n| n % 2 }
      p x.count(&:even?)
      p x.zip([10, 20, 30, 40])

      # empty ranges (first > last) materialize to an empty int array. reduce with an
      # initial value returns that value; the no-init `reduce(:sym)` form on an empty
      # array is the pre-existing typed-array limitation (returns the element-type
      # identity, not nil, since the result is a non-nullable int) and is not tested.
      e = (5..1)
      p e.reduce(100, :+)
      p e.group_by { |n| n }
      p e.find { |n| n > 0 }
      p e.count(&:even?)
      p e.tally

      # zip with a shorter argument pads the tail with nil
      p (1..3).zip([4, 5])

      # the natively-handled range methods are unchanged
      p r.map { |x| x * 2 }
      p r.select(&:odd?)
      p r.sum
      p r.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      15
      120
      115
      240
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      4
      2
      nil
      2
      1
      5
      [[1, 4], [2, 5], [3, 6]]
      [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
      {1 => 1, 2 => 1, 3 => 1}
      10
      {1 => [1, 3], 0 => [2, 4]}
      2
      [[1, 10], [2, 20], [3, 30], [4, 40]]
      100
      {}
      nil
      0
      {}
      [[1, 4], [2, 5], [3, nil]]
      [2, 4, 6, 8, 10]
      [1, 3, 5]
      15
      [1, 2, 3, 4, 5]
    OUT
  end

  it "sum, partition, sort_by and chunk_while take their block over a range" do
    result = zr(<<~'RUBY')
      # Block-taking Enumerable methods on an integer Range materialize through
      # the array redispatch: sum with a block (it was silently ignored),
      # partition, each_with_index, sort_by, chunk_while, and inject/reduce
      # block forms.
      p (1..3).sum { |x| x * 2 }
      x = (1..6).partition(&:even?)
      p x
      (10..12).each_with_index { |v, i| puts "#{i}:#{v}" }
      p (1..5).sort_by { |x| -x }
      p (1..5).chunk_while { |a, b| b == a + 1 }.to_a
      p (1..4).inject(10) { |s, x| s + x }
      p (1..4).reduce(0) { |s, x| s + x }
      p (1..4).inject(:+)
      p (1..3).sum
    RUBY

    _(result).must_answer <<~'OUT'
      12
      [[2, 4, 6], [1, 3, 5]]
      0:10
      1:11
      2:12
      [5, 4, 3, 2, 1]
      [[1, 2, 3, 4, 5]]
      20
      10
      10
      6
    OUT
  end

  it "select, reject, filter, min_by and max_by over a range that arrived as a parameter" do
    result = zr(<<~'RUBY')
      # Finite-range Enumerable coverage: select/reject/filter (the fused-loop forms)
      # and min_by/max_by, which materialize the range to an int array. Receivers go
      # through a method param so the range value reaches the runtime path.
      def r(x); x; end

      p r(1..5).select { |n| n.even? }
      p r(1..5).reject { |n| n.even? }
      p r(1..6).filter { |n| n > 3 }
      p r(1..5).select { |n| n > 10 }
      p r(1...5).select { |n| n.odd? }

      p r(1..5).min_by { |n| -n }
      p r(1..5).max_by { |n| -n }
      p r(2..8).min_by { |n| (n - 5).abs }
      p r(1..4).max_by { |n| n % 3 }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [1, 3, 5]
      [4, 5, 6]
      []
      [1, 3]
      5
      1
      5
      2
    OUT
  end

  it "== and eql? compare begin, end and exclusivity, and nothing else" do
    result = zr(<<~'RUBY')
      # Range#== / #eql? compare first, last, and exclusivity; a non-range is
      # never equal.
      p((1..5) == (1..5))
      p((1..5) == (1..6))
      p((1...5) == (1..5))
      p((1..5) == 5)
      p((1..5).eql?(1..5))
      p((1..5) != (1..6))
      p((1..5) != (1..5))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      true
      true
      false
    OUT
  end

  it "exclude_end?, size and count read the flag off a range held in a parameter" do
    result = zr(<<~'RUBY')
      # Non-literal ranges: passing through a method parameter defeats
      # compile-time constant-folding, so `exclude_end?`/`size`/`count`
      # must read the runtime `excl` flag off the sp_Range struct.
      def report(r)
        puts r.exclude_end?
        puts r.size
        puts r.count
      end

      report(1...5)
      report(1..5)

      # Literal ranges: compile-time receiver -- regression guard.
      puts (1...5).exclude_end?
      puts (1..5).exclude_end?
      puts (1...5).size
      puts (1..5).size
      puts (1...5).count
      puts (1..5).count
      puts (0...10).size
      puts (0..10).size
    RUBY

    _(result).must_answer <<~'OUT'
      true
      4
      4
      false
      5
      5
      true
      false
      4
      5
      4
      5
      10
      11
    OUT
  end

  it "an exclusive range held in a local stops one short everywhere" do
    result = zr(<<~'RUBY')
      # Exclusive ranges (`...`) held in a variable carry exclude_end at
      # runtime via the sp_Range struct, so max / include? / to_a / each /
      # map / size / step all stop one short of the end — matching CRuby
      # and the literal-range forms.
      r = 1...5
      p r.max
      p r.min
      p r.first
      p r.last
      p r.to_a
      p r.include?(5)
      p r.include?(4)
      p r.cover?(5)
      p r.size
      p r.count

      sum = 0
      r.each { |i| sum += i }
      p sum
      p r.map { |i| i * 2 }

      # Literal exclusive forms were also affected by the shared max /
      # include? codegen path.
      p((1...5).max)
      p((1...5).include?(5))
      p((1...5).to_a)

      # Inclusive ranges are unchanged.
      ri = 1..5
      p ri.max
      p ri.last
      p ri.to_a
      p ri.include?(5)
      p ri.size
    RUBY

    _(result).must_answer <<~'OUT'
      4
      1
      1
      5
      [1, 2, 3, 4]
      false
      true
      false
      4
      4
      10
      [2, 4, 6, 8]
      4
      false
      [1, 2, 3, 4]
      5
      5
      [1, 2, 3, 4, 5]
      true
      5
    OUT
  end

  it "flat_map over a range flattens one level" do
    result = zr(<<~'RUBY')
      # Range#flat_map maps each element through the block then flattens one level.
      def s(x); x; end
      p s(1..5).flat_map { |x| [x] }
      p s(1..3).flat_map { |x| [x, x * 10] }
      p s(1..4).flat_map { |x| x.even? ? [x] : [] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5]
      [1, 10, 2, 20, 3, 30]
      [2, 4]
    OUT
  end

  it "last(n) on an endless range raises, where first(n) and min answer" do
    result = zr(<<~'RUBY')
      # `last(n)` on an endless range raises rather than trying to reach a tail that
      # is not there. The guard has to live on Range's own row: `last(n)` answers by
      # materializing, and the `to_a` it used to reach went through Enumerable, which
      # walks `each` and so routed straight past Range's endless check.
      #
      # `first(n)` and `min` are the counterpart -- they count UP from begin, so an
      # endless range answers them.
      r = ((1..).last(2) rescue $!.class)
      p r
      p((1..).first(2))
      p((1..).min)
      p((1..5).last(2))
      p((1..5).last)
      p((1...5).last(2))
    RUBY

    _(result).must_answer <<~'OUT'
      RangeError
      [1, 2]
      1
      [4, 5]
      5
      [3, 4]
    OUT
  end

  it "a range literal reports its first, last and exclusivity" do
    result = zr(<<~'RUBY')
      r = 1..5
      puts(r.first)
      puts(r.last)
      puts(r.exclude_end?)
      puts(r)

      r2 = 1...5
      puts(r2.exclude_end?)
      puts(r2)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      false
      1..5
      true
      1...5
    OUT
  end

  it "min_by and max_by take a count and answer that many" do
    result = zr(<<~'RUBY')
      # The count form of min_by/max_by over a Range: the Range has to be
      # materialized before it can be indexed (#3860). MatchData#values_at with no
      # arguments selects nothing (#3846).
      p((1..5).min_by(2) { |x| -x })
      p((1..5).max_by(2) { |x| -x })
      p((1..5).min_by { |x| -x })
      p([3, 1, 2].min_by(2) { |x| x })
      p("hello".match(/(l)(o)/).values_at)
      p("hello".match(/(l)(o)/).values_at(1, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 4]
      [1, 2]
      5
      [1, 2]
      []
      ["l", "o"]
    OUT
  end

  it "min(n) counts up from begin and max(n) down from end, so one open side is enough" do
    result = zr(<<~'RUBY')
      # `min(n)` counts UP from begin and `max(n)` counts DOWN from end, so a range
      # open on the OTHER side still answers. Sorting the whole range instead, as the
      # generic Enumerable path does, never returns on an endless one.
      #
      # A Float begin cannot be walked, which is where the TypeErrors come from.
      p((1..).min(3))
      p((..5).max(2))
      p(("a".."e").min(2))
      p(("a".."e").max(2))
      r001 = ((1.0..5.0).min(2) rescue $!.class); p r001
      r002 = ((1.0..5.0).max(2) rescue $!.class); p r002
      p((1..5.0).min(2))
      p((1..5).min(2))
      p((1..5).max(2))
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [5, 4]
      ["a", "b"]
      ["e", "d"]
      TypeError
      TypeError
      [1, 2]
      [1, 2]
      [5, 4]
    OUT
  end

  it "a range with one Float endpoint keeps each endpoint's own type" do
    result = zr(<<~'RUBY')
      p((1.5..5).begin)
      p((1.5..5).first)
      p((1.5..5).min)
      p((1.5..5).to_s)
      p((1.5..5).cover?(1.2))
      p((1..5.5).end)
      p((1..5.5).last)
      p((1..5.5).max)
      p((1..5.5).to_s)
      p((1.0..5).begin)
      p((1.0..5).to_s)
      r = (1.5..5); p r.begin
      p((1.5..5.5).begin)
      p((1.0..5.0).to_s)
      p((1..5).to_s)
      p((1..5.5).to_a)
      p((1..5.5).sum)
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      1.5
      1.5
      "1.5..5"
      false
      5.5
      5.5
      5.5
      "1..5.5"
      1.0
      "1.0..5"
      1.5
      1.5
      "1.0..5.0"
      "1..5"
      [1, 2, 3, 4, 5]
      15
    OUT
  end

  it "first, last, min and max refuse a negative count" do
    result = zr(<<~'RUBY')
      r001 = ((1..5).first(-1) rescue $!.class); p r001
      r002 = ((1..5).last(-1) rescue $!.class); p r002
      r003 = ((1..5).min(-1) rescue $!.class); p r003
      r004 = ((1..5).max(-1) rescue $!.class); p r004
      a005 = (1..5); n005 = -1; r005 = (a005.first(n005) rescue $!.class); p r005
      r010 = (("a".."e").first(-1) rescue $!.class); p r010
      p (1..5).first(2)
      p (1..5).last(2)
      p (1..5).min(2)
      p (1..5).max(2)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      [1, 2]
      [4, 5]
      [1, 2]
      [5, 4]
    OUT
  end

  it "an explicit nil endpoint is the open end, and Range.new builds the same range" do
    result = zr(<<~'RUBY')
      # An explicit `nil` endpoint IS the open end: `nil..5` and `..5` are the SAME
      # range. zr kept the two apart, so `(1..nil).min` read a bounded range and
      # iterated forever, `(nil..5).first` answered nil instead of raising, and the
      # pair compared unequal.
      #
      # `Range.new` is the same constructor under another name, and was missing.

      def show(label)
        print label, ": "
        p yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        p [e.class, e.message]
      end

      RANGES = {
        "beginless-lit" => (..5),
        "nil-begin" => (nil..5),
        "endless-lit" => (1..),
        "nil-end" => (1..nil),
        "both-nil" => (nil..nil),
      }.freeze

      RANGES.each do |name, r|
        show("#{name} inspect") { r.inspect }
        show("#{name} endpoints") { [r.begin, r.end, r.exclude_end?] }
        show("#{name} first") { r.first }
        show("#{name} last") { r.last }
        show("#{name} size") { r.size }
        show("#{name} cover") { r.cover?(3) }
        show("#{name} min") { r.min }
      end

      # The nil spelling and the omitted spelling are one range.
      show("eq begin") { (nil..5) == (..5) }
      show("eq end") { (1..nil) == (1..) }
      show("eq excl") { (1...nil) == (1...) }
      show("both-nil is neither") { [(nil..nil) == (..5), (nil..nil) == (1..)] }

      # `Range.new` normalizes the same way, and rejects an incomparable pair a
      # literal could never build.
      show("new") { Range.new(1, 5).inspect }
      show("new excl") { Range.new(1, 5, true).inspect }
      show("new truthy excl") { Range.new(1, 5, 1).exclude_end? }
      show("new nil begin") { Range.new(nil, 5).inspect }
      show("new nil end") { Range.new(1, nil).inspect }
      show("new both nil") { Range.new(nil, nil).inspect }
      show("new equals literal") { Range.new(1, 5) == (1..5) }
      show("new strings") { Range.new("a", "e").to_a }
      show("new bad pair") { Range.new(1, "a") }
      show("new too few") { Range.new(1) }
      show("new too many") { Range.new(1, 2, 3, 4) }

      # A nil endpoint inside a pattern range folds the same way.
      def classify(v)
        case v
        in ..0 then :low
        in 1.. then :high
        end
      end
      show("pattern") { [classify(-1), classify(3)] }
    RUBY

    _(result).must_answer <<~'OUT'
      beginless-lit inspect: "..5"
      beginless-lit endpoints: [nil, 5, false]
      beginless-lit first: [RangeError, "cannot get the first element of beginless range"]
      beginless-lit last: 5
      beginless-lit size: [TypeError, "can't iterate from NilClass"]
      beginless-lit cover: true
      beginless-lit min: [RangeError, "cannot get the minimum of beginless range"]
      nil-begin inspect: "..5"
      nil-begin endpoints: [nil, 5, false]
      nil-begin first: [RangeError, "cannot get the first element of beginless range"]
      nil-begin last: 5
      nil-begin size: [TypeError, "can't iterate from NilClass"]
      nil-begin cover: true
      nil-begin min: [RangeError, "cannot get the minimum of beginless range"]
      endless-lit inspect: "1.."
      endless-lit endpoints: [1, nil, false]
      endless-lit first: 1
      endless-lit last: [RangeError, "cannot get the last element of endless range"]
      endless-lit size: Infinity
      endless-lit cover: true
      endless-lit min: 1
      nil-end inspect: "1.."
      nil-end endpoints: [1, nil, false]
      nil-end first: 1
      nil-end last: [RangeError, "cannot get the last element of endless range"]
      nil-end size: Infinity
      nil-end cover: true
      nil-end min: 1
      both-nil inspect: "nil..nil"
      both-nil endpoints: [nil, nil, false]
      both-nil first: [RangeError, "cannot get the first element of beginless range"]
      both-nil last: [RangeError, "cannot get the last element of endless range"]
      both-nil size: [TypeError, "can't iterate from NilClass"]
      both-nil cover: true
      both-nil min: [RangeError, "cannot get the minimum of beginless range"]
      eq begin: true
      eq end: true
      eq excl: true
      both-nil is neither: [false, false]
      new: "1..5"
      new excl: "1...5"
      new truthy excl: true
      new nil begin: "..5"
      new nil end: "1.."
      new both nil: "nil..nil"
      new equals literal: true
      new strings: ["a", "b", "c", "d", "e"]
      new bad pair: [ArgumentError, "bad value for range"]
      new too few: [ArgumentError, "wrong number of arguments (given 1, expected 2..3)"]
      new too many: [ArgumentError, "wrong number of arguments (given 4, expected 2..3)"]
      pattern: [:low, :high]
    OUT
  end

  it "clamp against a range of user objects folds the bounds into the comparison" do
    result = zr(<<~'RUBY')
      # Comparable#clamp against a range of user objects: the bounds fold straight
      # into the comparison, so no Range object is built and every inline form works.
      # Materializing such a Range is the part that cannot work (sp_Range has mrb_int
      # bounds); that is a compile error, covered by docs/limitations.md. #2558
      class Ver
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      lo = Ver.new(1)
      hi = Ver.new(9)
      p(Ver.new(5).clamp(lo..hi).n)
      p(Ver.new(12).clamp(lo..hi).n)
      p(Ver.new(0).clamp(lo..hi).n)
      p(Ver.new(5).clamp(lo, hi).n)
      p(Ver.new(12).clamp(..Ver.new(9)).n)
      p(Ver.new(0).clamp(Ver.new(1)..).n)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      9
      1
      5
      9
      1
    OUT
  end

  it "the queries that need the missing end raise, and the ones that do not answer" do
    result = zr(<<~'RUBY')
      p((..5).max)
      r001 = ((..5).first rescue $!.class); p r001
      r002 = ((1..).last rescue $!.class); p r002
      r003 = ((1..).minmax rescue $!.class); p r003
      r004 = ((..5).to_a rescue $!.class); p r004
      p((1..).count)
      p((1..).size)
      p((1..5).count)
      p((1..5).max)
      p((1..5).first)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      RangeError
      RangeError
      RangeError
      TypeError
      Infinity
      Infinity
      5
      5
      1
    OUT
  end

  it "find, detect and take_while over an endless range stop at their answer" do
    result = zr(<<~'RUBY')
      # `find`/`detect`/`take_while` over an endless Range stop at their answer
      # rather than trying to walk the whole range. `find` and `detect` always broke
      # early; `take_while` used to collect the source first, which on `(1..)` never
      # returned.
      #
      p((1..).find { |x001| x001 * x001 > 30 })
      p((1..).detect { |x002| x002 > 3 })
      p((1..).take_while { |x004| x004 < 4 })
      p((1..5).all?(Integer))
      p((1..5).any?(2..4))
      p((1..5).none?(String))
      p((1..5).find { |x| x > 3 })
      p((1..5).take_while { |x| x < 3 })
      r = (1..)
      p r.find { |x| x > 7 }
    RUBY

    _(result).must_answer <<~'OUT'
      6
      4
      [1, 2, 3]
      true
      true
      true
      4
      [1, 2]
      8
    OUT
  end

  it "an in clause with a range matches through cover?, whatever the value's type" do
    result = zr(<<~'RUBY')
      # A range pattern in `case/in` is `Range#===` -- a `#cover?` test that works
      # for any comparable scrutinee (a Float, or a value of unknown static type),
      # an exclusive range, and a beginless/endless range, not just integers.
      def classify(x)
        case x
        in 0.0...0.5 then "low"
        in 0.5..1.0  then "high"
        in ..0.0     then "negative"
        else              "other"
        end
      end
      puts classify(0.2)
      puts classify(0.9)
      puts classify(-1.0)
      puts classify(5.0)

      # A poly element (its type isn't statically known) matches an integer range
      # by value; a non-integer simply doesn't match.
      [3, "x", 7].each do |v|
        case v
        in 0..5 then puts "#{v.inspect}: small int"
        else         puts "#{v.inspect}: other"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      low
      high
      negative
      other
      3: small int
      "x": other
      7: other
    OUT
  end

  it "slice_when, chunk_while and the with_index family over a range" do
    result = zr(<<~'RUBY')
      # Enumerator chains over an Integer Range source: the with_index family
      # materializes the range to an int array and runs the array machinery (#3228).
      p((1..10).slice_when { |i, j| j.even? }.to_a)
      p((1..8).chunk_while { |i, j| j == i + 1 }.map { |r| r.sum })
      p((1..10).select.with_index { |v, i| i.even? })
      p((1..5).map.with_index { |v, i| v * i })
      p((1..5).select.with_index(1) { |v, i| i.odd? })
      p((0..4).reject.with_index { |v, i| i < 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], [2, 3], [4, 5], [6, 7], [8, 9], [10]]
      [36]
      [1, 3, 5, 7, 9]
      [0, 2, 6, 12, 20]
      [1, 3, 5]
      [2, 3, 4]
    OUT
  end

  it "size answers for an integer, endless or Float-ended range and raises for the rest" do
    result = zr(<<~'RUBY')
      # Range#size handles integer, endless, and Float-ended ranges.
      p (1..10).size
      p (1...10).size
      p (1..).size            # endless -> Infinity
      p (1..7.5).size         # Float end floors
      p (1...7.5).size
      p (5..1).size           # empty -> 0

      # A Float or absent begin can't be sized (CRuby raises TypeError).
      r1 = ((1.5..5).size rescue $!.class); p r1
      r2 = ((..5).size rescue $!.class); p r2

      # Proc.new builds a proc from its block (or a forwarded &block).
      double = Proc.new { |n| n * 2 }
      p double.call(21)
      def forward(&b) = Proc.new(&b)
      p forward { |n| n + 1 }.call(9)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      9
      Infinity
      7
      7
      0
      TypeError
      TypeError
      42
      10
    OUT
  end

  it "size, take and first answer for an infinite range reached through a local" do
    result = zr(<<~'RUBY')
      # Range#size with a Float::INFINITY (or endless) bound, reached through a
      # local variable: the sole-assignment lookthrough types/serves it like the
      # literal receiver (Float Infinity), and the range VALUE materializes its
      # infinite end as INTPTR_MAX instead of passing (1.0/0.0) through an
      # mrb_int parameter (UB: the converted value was a stale register, so the
      # previous range's size leaked through).
      a = (1..10); p(a.size)
      b = (1..Float::INFINITY); p(b.size)
      c1 = (5..); p(c1.size)

      # take/first on the looked-through infinite range count from the start
      d = (2..Float::INFINITY)
      p d.take(4)
      p d.first(3)

      # exclusive infinite end behaves the same
      f = (1...Float::INFINITY); p(f.size)

      # membership on a materialized infinite-end range
      g = (3..Float::INFINITY)
      p g.include?(1000000)
      p g.cover?(2)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      Infinity
      Infinity
      [2, 3, 4, 5]
      [2, 3, 4]
      Infinity
      true
      false
    OUT
  end

  it "sum takes a numeric seed, and an endless range has an infinite size" do
    result = zr(<<~'RUBY')
      # Range#sum with a numeric init, endless-literal size (Infinity) and
      # take/first(n) (counted prefix), and beginless size raising TypeError.
      p((1..3).sum(10))
      p((1..4).sum(0.5))
      p((1..).size)
      r6 = (begin; (..5).size; rescue TypeError; "TE"; end); p r6
      p((1..).take(3))
      p((1..).first(2))
      p((5..).take(4))
    RUBY

    _(result).must_answer <<~'OUT'
      16
      10.5
      Infinity
      "TE"
      [1, 2, 3]
      [1, 2]
      [5, 6, 7, 8]
    OUT
  end

  it "to_s and inspect print the endpoints the way they were written" do
    result = zr(<<~'RUBY')
      r = (1..3)
      puts r.to_s
      puts r.inspect
      puts (1...5).to_s
      puts ('a'..'c').inspect
      puts ('a'...'d').to_s
      puts (1..).to_s
      puts (..5).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      1..3
      1..3
      1...5
      "a".."c"
      a...d
      1..
      ..5
    OUT
  end

  it "a nil or infinite endpoint covers everything on that side" do
    result = zr(<<~'RUBY')
      p((nil..5).cover?(-3))
      p((..5).cover?(-3))
      p((nil..5).include?(-3))
      p((-Float::INFINITY..5).cover?(0))
      p((-Float::INFINITY..5) === 0)
      p((1..).cover?(10**12))
      p((nil..nil).cover?(3))
      p((nil..nil).begin)
      p((nil..nil).end)
      p((nil..nil).inspect)
      p((nil...nil).inspect)
      p(Range.new(nil, nil).inspect)
      p((nil..nil).to_s)
      p((..5).inspect)
      p((1..).inspect)
      p((1..).end)
      p((1..nil).end)
      p((nil..5).begin)
      p((1..5).begin)
      p((1..5).end)
      p((1..5).to_a)
      p((-Float::INFINITY..Float::INFINITY).cover?(0))
      p((-Float::INFINITY..5).begin)
      p((1..Float::INFINITY).end)
      p((1..Float::INFINITY).size)
      p((1..Float::INFINITY).cover?(10**9))
      p((-Float::INFINITY..Float::INFINITY).begin)
      p((-Float::INFINITY..Float::INFINITY).end)
      p((1.0..5.0).begin)
      p((1.0..Float::INFINITY).to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      nil
      nil
      "nil..nil"
      "nil...nil"
      "nil..nil"
      ".."
      "..5"
      "1.."
      nil
      nil
      nil
      1
      5
      [1, 2, 3, 4, 5]
      true
      -Infinity
      Infinity
      Infinity
      true
      -Infinity
      Infinity
      1.0
      "1.0..Infinity"
    OUT
  end
end
