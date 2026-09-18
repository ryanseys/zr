# frozen_string_literal: true

require "spec_helper"

describe "Builtins: blocks and yields" do
  it "a block-carrying call checks its arity the same as the blockless spelling" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # block-carrying calls check the with-block quartet
      begin
        p(3.times(1) { |i| i })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(3.upto(4, 1) { |i| i })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(3.step(4, 1, 2) { |i| i })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p([1, 2].fill(0) { |i| i * 9 })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(2.step { break :stopped })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 2, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 3, expected 0..2)"]
      [0, 9]
      :stopped
    OUT
  end

  it "the rows Method#arity never reported still check their own arity" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # methods the Method#arity dump missed
      begin
        p(1.5.div)
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p("ab".bytesplice)
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 2..5)"]
    OUT
  end

  it "a receiver outside the original arity map checks its rows too" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # receivers beyond the original map
      begin
        p(nil.to_a(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(true.to_s(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(1r.numerator(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(1i.real(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
    OUT
  end

  it "a user object falls back to Object's universal rows for its arity" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # a user object falls back to Object's universal rows
      class Widget; end
      w = Widget.new
      begin
        p(w.frozen?(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(w.respond_to?(:a, false, 2))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(w.dup(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 3, expected 1..2)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
    OUT
  end

  it "an attr and a Struct reader take no argument, where Struct's [] and dig want one" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # attr and Struct readers are zero-arity; Struct [] / dig want arguments
      class Holder
        attr_reader :size
        def initialize = @size = 5
      end
      begin
        p(Holder.new.size(2))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      pair = Struct.new(:a, :b).new(1, 2)
      begin
        p(pair.a(2))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(pair[])
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(pair.dig)
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1+)"]
    OUT
  end

  it "a native-class instance and a Mutex check the rows a probe found on them" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # native-class instances and Mutex check their probed rows
      begin
        p(StringIO.new("x").eof?(1))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Mutex.new.synchronize(1) { 2 })
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
      [ArgumentError, "wrong number of arguments (given 1, expected 0)"]
    OUT
  end

  it "a constructor and a renamed class-method row each check their own arity" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # class-method rows: constructors and renamed forms
      begin
        p(Hash.new(1, 2))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(File.exist?)
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end
      begin
        p(Array.new(1, 2, 3))
      rescue TypeError, ArgumentError => e
        p [e.class, e.message]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "wrong number of arguments (given 2, expected 0..1)"]
      [ArgumentError, "wrong number of arguments (given 0, expected 1)"]
      [ArgumentError, "wrong number of arguments (given 3, expected 0..2)"]
    OUT
  end

  it "an attribute named like an Object method is the attribute, and its arity says so" do
    result = ze0(<<~'RUBY')
      # The arity guard on calls the bare-call spec cannot reach: block-carrying
      # calls (their accepted counts are probed separately -- `Array#fill` drops
      # to 0..2 under a block), zero-arity readers, Struct member access, native
      # instances, and receivers beyond the original eight.
      #
      # Three things this file was FILED for, all fixed. `String#bytesplice`
      # accepted 2..3 where CRuby has four shapes up to five arguments -- the
      # replacement's own byte window was simply missing. A Struct MEMBER
      # accessor counted nothing, so `s.a(2)` answered the member and
      # `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
      # nil as a BOUND, so the first comparison failed on a NilClass the caller
      # never wrote, where ruby's endless form runs.

      require "stringio"

      # review-found edges: an attribute named like an Object method is the
      # attribute; empty splats are zero arguments; the iterator path type-checks
      class Request
        attr_accessor :method, :path
        def initialize(m, p2) = (@method = m; @path = p2)
      end
      p Request.new("GET", "/").method
      class Pt; attr_reader :x; def initialize = @x = 7; end
      p Pt.new.x(*[])
      begin
        3.step("a") { |i| i }
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        5.between?("a", "b")
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p 1.step(nil) { |i| break :unbounded }
    RUBY

    _(result).must_answer <<~'OUT'
      "GET"
      7
      [ArgumentError, "comparison of Integer with String failed"]
      [ArgumentError, "comparison of Integer with String failed"]
      :unbounded
    OUT
  end

  it "container read builtin methods" do
    result = ze0(<<~'RUBY')
      # Methods on values read back out of containers (poly-typed receivers whose
      # runtime kind is a builtin): map! writes back to the original typed array,
      # Range sums/covers, Time subtracts, sum takes a seed, Integer#gcdlcm works
      # on nested block params (#3234).
      m = [[1, 2], [3, 4]]; m[1].map! { |x| x * 10 }; p m
      r = [(1..5)][0]; p r.sum
      c = [(10..20)][0]; p c.cover?(15)
      p c.cover?(25)
      arr = [Time.at(0), Time.at(3600)]; a = arr[0]; b = arr[1]
      p(b - a)
      rows = [[Rational(1, 2), Rational(1, 3)]]; row = rows[0]
      p row.sum(Rational(0))
      pairs = [[48, 36]]; pairs.each { |x, y| p x.gcdlcm(y) }
      fs = [[1.5, 2.5]]; fs[0].map! { |x| x * 2 }; p fs
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [30, 40]]
      15
      true
      false
      3600.0
      (5/6)
      [12, 144]
      [[3.0, 5.0]]
    OUT
  end

  it "curry arity" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Proc#curry with an arity larger than the proc's own returns a Proc where
      # ruby raises ArgumentError.
      #
      c001 = proc { |a, b, c| [a, b, c] }.curry(2); p c001[1][2].class
      c002 = ->(*a) { a }.curry(3); p c002[1][2][3].class
      c003 = ->(*a) { a }.curry; p c003[1].class
      r004 = (->(a, b) { a + b }.curry(3) rescue $!.class); p r004
      add = ->(a, b) { a + b }.curry
      p add[1][2]
      mul = proc { |a, b, c| a * b * c }.curry
      p mul[2][3][4]
      p proc { |a, b| [a, b] }.curry(2)[1][2]
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      Array
      Array
      ArgumentError
      3
      24
      [1, 2]
    OUT
  end

  it "enumerable and proc surface" do
    result = ze0(<<~'RUBY')
      # find/detect take an optional ifnone callable, invoked (no args) only when
      # nothing matches; a match -- even a nil element -- ignores it.
      p [1, 2, 3].find(-> { -1 }) { |x| x > 10 }
      p [1, 20, 3].find(-> { -1 }) { |x| x > 10 }
      p [1, nil, 3].find(-> { :fallback }) { |x| x.nil? }

      # tally accepts an accumulator hash: counts add onto its existing values and
      # the same hash is returned.
      h = Hash.new(0)
      p [1, 1, 2, 3, 3, 3].tally(h)
      p h
      p [5, 5, 6].tally({ 5 => 10 })
      p [1, 1, 2].tally

      # min_by(n)/max_by(n) return the n smallest/largest by key, ascending for
      # min_by and descending for max_by; no count answers a single element.
      p %w[bbbb a ccc dd].max_by(2, &:length)
      p %w[bbbb a ccc dd].min_by(2, &:length)
      p [3, 1, 4, 1, 5, 9, 2].max_by(3) { |n| n }
      p [1, 2, 3].min_by(0) { |n| n }
      p %w[bb a ccc dd].max_by(&:length)

      # Proc#source_location answers a [String, Integer] pair.
      loc = ->(x) { x }.source_location
      p loc.class
      p loc.length
      p [loc[0].class, loc[1].class]
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      20
      nil
      {1 => 2, 2 => 1, 3 => 3}
      {1 => 2, 2 => 1, 3 => 3}
      {5 => 12, 6 => 1}
      {1 => 2, 2 => 1}
      ["bbbb", "ccc"]
      ["a", "dd"]
      [9, 5, 4]
      []
      "ccc"
      Array
      2
      [String, Integer]
    OUT
  end

  it "lambda enforces strict arity via argument error" do
    result = ze0(<<~'RUBY')
      f = ->(x, y) { x + y }
      begin
        f.call(1)
      rescue ArgumentError => e
        puts "caught: #{e.message}"
      end
      puts f.call(1, 2)
    RUBY

    _(result).must_answer "caught: wrong number of arguments (given 1, expected 2)\n3\n"
  end

  it "lambda never auto splats and checks its arity" do
    result = ze0(<<~'RUBY')
      strict = ->(a, b) { [a, b] }
      p strict.call(1, 2)
      begin
        strict.call([1, 2])
      rescue ArgumentError => e
        puts "ArgumentError"
      end
    RUBY

    _(result).must_answer "[1, 2]\nArgumentError\n"
  end

  it "lambda strict arity" do
    result = ze0(<<~'RUBY')
      # A non-lambda Proc is lenient: extra args are dropped, no raise.
      pr = proc { |x| x }
      puts pr.call(1, 2)

      # A lambda is strict: the wrong argument count raises ArgumentError
      # (matching CRuby). Rescue it so the program completes normally and
      # "after" still prints.
      puts "before"
      f = ->(x) { x }
      begin
        f.call(1, 2)
      rescue ArgumentError => e
        puts "rescued: #{e.class}"
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      before
      rescued: ArgumentError
      after
    OUT
  end

  it "proc arity and curry" do
    result = ze0(<<~'RUBY')
      # Proc#arity / #lambda? / #curry all read facts about a proc's PARAMETERS,
      # which a compiled closure can't answer about itself -- the compiler
      # records them from the block/lambda's static signature at construction.
      #
      # arity encodes: min = required + post + (1 if any required keyword);
      # a signature whose maximum is unbounded (or, for a lambda, merely differs
      # from the minimum) reports -(min + 1) instead.

      # Required-only signatures stay positive.
      p proc {}.arity
      p proc { |a| }.arity
      p proc { |a, b| }.arity
      p ->() {}.arity
      p ->(a, b) {}.arity
      p ->(a, b, c) {}.arity

      # A block parameter isn't an argument slot.
      p ->(&b) {}.arity

      # An optional parameter makes a LAMBDA negative...
      p ->(a, b = 1) {}.arity
      p lambda { |a, b = 1, c = 2| }.arity
      # ...but a plain proc reports its minimum (its maximum is still bounded).
      p proc { |a, b = 1| }.arity

      # A rest parameter is unbounded: negative either way.
      p proc { |*a| }.arity
      p proc { |a, *b| }.arity
      p ->(a, *b) {}.arity
      p proc { |a, b, *c| }.arity

      # Post parameters are required, so they raise the minimum.
      p ->(a, *b, c) {}.arity
      p ->(a, *b, c, d) {}.arity

      # A required keyword adds exactly one mandatory slot, however many there are.
      p ->(b:) {}.arity
      p ->(a, b:) {}.arity
      p ->(a, b:, c:) {}.arity
      p ->(a, b:, c: 1) {}.arity
      p ->(a, e:, **g) {}.arity
      p proc { |a, b:| }.arity

      # An optional keyword or **rest alone widens the maximum.
      p ->(a, b: 1) {}.arity
      p ->(a, **k) {}.arity
      p proc { |a, b: 1| }.arity
      p proc { |a, **k| }.arity

      # Everything at once.
      p ->(a, b = 1, *c, d, e:, f: 2, **g, &h) {}.arity

      # lambda? distinguishes the two kinds.
      p ->() {}.lambda?
      p lambda {}.lambda?
      p proc {}.lambda?
      p Proc.new {}.lambda?

      # curry collects arguments across calls until the arity is satisfied.
      add = ->(a, b, c) { a + b + c }
      p add.curry[1][2][3]
      p add.curry.(1).(2).(3)
      p add.curry[1, 2][3]
      p add.curry[1][2, 3]
      # Every curry step is itself a var-args lambda, so its own arity is -1.
      p add.curry.arity
      p add.curry[1].arity
      p add.curry.lambda?
      p add.curry[1].lambda?

      # Each partial application is a FRESH proc -- reusable, never accumulating.
      step = add.curry[10]
      p step[1][2]
      p step[3][4]
      p step[5][6]

      # A plain proc curries to its minimum arity.
      mul = proc { |a, b| a * b }
      p mul.curry[3][4]
      p proc { |a, b| }.curry.arity

      # An explicit count curries a proc whose own arity is unbounded.
      p ->(*a) { a.sum }.curry(3)[1][2][3]
      p ->(*a) { a.length }.curry(2)[:x][:y]
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      0
      2
      3
      0
      -2
      -2
      1
      -1
      -2
      -2
      -3
      -3
      -4
      1
      2
      2
      2
      2
      2
      -2
      -2
      1
      1
      -4
      true
      true
      false
      false
      6
      6
      6
      6
      -1
      -1
      true
      true
      13
      17
      21
      12
      -1
      6
      2
    OUT
  end

  it "proc arity and lambda p report the blocks own signature" do
    result = ze0(<<~'RUBY')
      p ->(a, b) {}.arity
      p ->(a, b = 1) {}.arity
      p proc { |a, b = 1| }.arity
      p proc { |a, *b| }.arity
      p ->(a, b:) {}.arity
      p ->(a, **k) {}.arity
      p ->() {}.lambda?
      p proc {}.lambda?
    RUBY

    _(result).must_answer <<~'OUT'
      2
      -2
      1
      -2
      2
      -2
      true
      false
    OUT
  end

  it "proc arity keywords" do
    result = ze0(<<~'RUBY')
      # A proc's arity: only a rest parameter makes it negative. Optional keywords
      # and a keyword rest were treated as negative for a proc too, so
      # `proc { |**kw| }.arity` answered -1 where CRuby answers 0.
      p [proc{|**k|}.arity, proc{|a,**k|}.arity, lambda{|a,**k|}.arity]
      p [proc{|b:1|}.arity, proc{|a,b:1|}.arity, proc{|a:|}.arity, lambda{|a:|}.arity]
      p [proc{|a,b=1|}.arity, lambda{|a,b=1|}.arity, proc{|a,*r|}.arity, proc{|a:,b:1|}.arity]
      p [lambda{|b:1|}.arity, proc{|*r|}.arity, lambda{|*r|}.arity, proc{|**k,&b|}.arity]
      p [lambda{|a,b:1|}.arity, proc{|a,b,c=1|}.arity, lambda{|a,b,c=1|}.arity]
      p [lambda{|a:,b:1|}.arity, lambda{|a:,**k|}.arity, proc{|a:,**k|}.arity]
      p [proc{|a|}.arity, proc{|a,b|}.arity, lambda{|a,b|}.arity, proc{}.arity, lambda{}.arity]
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, -2]
      [0, 1, 1, 1]
      [1, -2, -2, 1]
      [-1, -1, -1, 0]
      [-2, 2, -3]
      [1, 1, 1]
      [1, 2, 2, 0, 0]
    OUT
  end

  it "proc arity nil" do
    result = ze0(<<~'RUBY')
      # A block/proc param past the supplied argument count binds nil, not the
      # typed zero (CRuby fills missing params with nil).
      f = proc { |a, b| p b }
      f.call(1)                 # nil
      f.call(10, 20)            # 20

      # nil-awareness flows through .nil? and || default on the missing param.
      g = proc { |a, b| p(b.nil?) }
      g.call(1)                 # true

      h = proc { |a, b| p(b || 99) }
      h.call(1)                 # 99
      h.call(1, 5)              # 5

      # A block forwarded through &blk and called with too few args.
      def take(&blk)
        blk.call(7)
      end
      take { |x, y| p y }       # nil

      # The leading supplied param is still bound normally.
      k = proc { |a, b| p a }
      k.call(42)                # 42

      # A lambda invoked with its exact arity is unaffected.
      lam = ->(a, b) { p(a + b) }
      lam.call(2, 3)            # 5
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      20
      true
      99
      5
      nil
      42
      5
    OUT
  end

  it "proc arity opt rest" do
    result = ze0(<<~'RUBY')
      # Proc#arity encodes a signature with an optional, rest, or post parameter as
      # -(required + 1); a required-only signature stays the positive count.
      p ->(a, b = 1) {}.arity
      p proc { |a, *b| }.arity
      p ->(a, b) {}.arity
      p proc { |a| }.arity
      p ->(a, *b) {}.arity
      p proc { |a, b, *c| }.arity
      p ->() {}.arity
      p proc { |*a| }.arity
      p lambda { |a, b = 1, c = 2| }.arity
      p ->(a, b, c) {}.arity

      # post parameters (after a rest) are required and counted
      p ->(a, *b, c) {}.arity
      p ->(a, *b, c, d) {}.arity

      # keyword parameters: a required keyword adds a mandatory slot (stays positive);
      # an optional keyword or keyword-rest alone makes the count negative.
      p ->(a, b:) {}.arity
      p ->(b:) {}.arity
      p ->(a, b:, c:) {}.arity
      p ->(a, b: 1) {}.arity
      p ->(a, b:, c: 1) {}.arity
      p ->(a, **k) {}.arity
      p ->(a, b:, **k) {}.arity

      # proc (non-lambda) forms with optional / rest
      p proc { |a, b = 1| }.arity
      p proc { |a, b, *c| }.arity
    RUBY

    _(result).must_answer <<~'OUT'
      -2
      -2
      2
      1
      -2
      -3
      0
      -1
      -2
      3
      -3
      -4
      2
      1
      2
      -2
      2
      -2
      2
      1
      -3
    OUT
  end

  it "proc curry arity arg" do
    result = ze0(<<~'RUBY')
      p(->(a, b, c) { a + b + c }.curry(3)[1][2][3])
      add = ->(a, b) { a + b }
      p(add.curry(2)[10][20])
    RUBY

    _(result).must_answer "6\n30\n"
  end

  it "proc forward arity" do
    result = ze0(<<~'RUBY')
      # Inline `&->(...)` lambdas and multi-param procs forwarded into iterators.
      # Direct clone-param typing (an inline lambda's params are typed from the
      # forwarded call site) plus arity-matched calling (a 1-param callable receives a
      # hash pair as one array; a 2-param one receives k, v positionally) close the
      # forwarding gaps. Distinct per-type helpers keep element types monomorphic.
      def ints(a) = a
      def strs(a) = a
      def syms(a) = a
      def hsh(x) = x
      def shsh(x) = x

      # inline lambdas now forward into arrays of any element type (previously the
      # cloned lambda's param defaulted to int and mistyped non-int elements)
      p ints([1, 2, 3]).map(&->(x) { x * 2 })                   # [2, 4, 6]
      p strs(["a", "bb", "c"]).select(&->(s) { s.length == 1 }) # ["a", "c"]
      p syms([:a, :bb]).map(&->(s) { s.to_s })                  # ["a", "bb"]

      # inline lambda and 1-param value into Hash#each receive the [k, v] pair
      h = hsh({ a: 1, b: 2 })
      h.each(&->(pair) { p pair })                              # [:a, 1] / [:b, 2]
      pair_l = ->(pair) { p pair[1] }
      h.each(&pair_l)                                           # 1 / 2

      # a 2-param proc receives k, v positionally (auto-splat by arity)
      kv = proc { |k, v| p [k, v] }
      h.each(&kv)                                               # [:a, 1] / [:b, 2]

      # each_key / each_value forward the bare key / value
      h.each_key(&->(k) { p k })                                # :a / :b
      h.each_value(&->(v) { p v })                              # 1 / 2

      # a string-keyed hash forwards string keys
      shsh({ "x" => 10, "y" => 20 }).each_key(&->(k) { p k })   # "x" / "y"

      # a proc/lambda called directly with a scalar arg gets that scalar's type,
      # not a poly widening of the bare-int default
      p ->(s) { s.upcase }.call("hi")                           # "HI"
      p ->(s) { s.to_s }.call(:hello)                           # "hello"
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      ["a", "c"]
      ["a", "bb"]
      [:a, 1]
      [:b, 2]
      1
      2
      [:a, 1]
      [:b, 2]
      :a
      :b
      1
      2
      "x"
      "y"
      "HI"
      "hello"
    OUT
  end
end
