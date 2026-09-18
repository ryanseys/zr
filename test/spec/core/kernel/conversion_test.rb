# frozen_string_literal: true

require "spec_helper"

describe "Kernel: conversion" do
  it "conv lying ducks" do
    result = ze0(<<~'RUBY')
      # A present-but-lying to_x raises CRuby's "can't convert" shape; a nil
      # answer from to_x means "not convertible" at check sites.
      class LiarInt
        def to_int
          "nope"
        end
      end

      class LiarStr
        def to_str
          42
        end
      end

      class LiarAry
        def to_ary
          "zap"
        end
      end

      def err
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      err { [1, 2, 3][LiarInt.new] }
      err { [1, 2].first(LiarInt.new) }
      err { "a" + LiarStr.new }
      err { [1, 2].join(LiarStr.new) }
      err { [1] + LiarAry.new }
      err { [1].concat(LiarAry.new) }
      err { "ab" * LiarInt.new }
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: can't convert LiarInt to Integer (LiarInt#to_int gives String)
      TypeError: can't convert LiarInt to Integer (LiarInt#to_int gives String)
      TypeError: can't convert LiarStr to String (LiarStr#to_str gives Integer)
      TypeError: can't convert LiarStr to String (LiarStr#to_str gives Integer)
      TypeError: can't convert LiarAry to Array (LiarAry#to_ary gives String)
      TypeError: can't convert LiarAry to Array (LiarAry#to_ary gives String)
      TypeError: can't convert LiarInt to Integer (LiarInt#to_int gives String)
    OUT
  end

  it "conv to int duck" do
    result = ze0(<<~'RUBY')
      # to_int ducks at NUM2LONG index/count sites.
      class Two
        def to_int
          2
        end
      end

      two = Two.new
      p [1, 2] * two
      p "ab" * two
      p [10, 20, 30][two]
      p [10, 20, 30].first(two)
      p [1, 2, 3].fill(0, two)
      p [1, 2, 3, 4].rotate(two)
      p [1, 2, 3].dig(two)
      p "abcdef"[two]
      p [1, 2, 3].combination(two).to_a
      p Array.new(two)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 1, 2]
      "abab"
      30
      [10, 20]
      [1, 2, 0]
      [3, 4, 1, 2]
      3
      "c"
      [[1, 2], [1, 3], [2, 3]]
      [nil, nil]
    OUT
  end

  it "an &obj block argument converts through to_proc" do
    result = ze0(<<~'RUBY')
      # Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
      # `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
      # Each is duck-typed -- any object answering the method participates.

      # --- &obj -> to_proc -------------------------------------------------------

      # A Symbol is the familiar case.
      p [1, 2, 3].map(&:to_s)
      p %w[a b].map(&:upcase)

      # A Proc passes straight through.
      doubler = ->(x) { x * 2 }
      p [1, 2, 3].map(&doubler)

      # A Method object converts via Method#to_proc.
      def triple(x) = x * 3
      p [1, 2, 3].map(&method(:triple))

      # Any object defining to_proc converts.
      class Dbl
        def to_proc
          ->(x) { x * 2 }
        end
      end
      p [1, 2, 3].map(&Dbl.new)
      d = Dbl.new
      p [10, 20].map(&d)

      # nil means "no block at all".
      def block_given_here(&blk)
        blk.nil?
      end
      p block_given_here(&nil)

      # An object whose to_proc answers a non-Proc is a TypeError.
      class BadProc
        def to_proc = :not_a_proc
      end
      begin
        [1].map(&BadProc.new)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

      # An object with no to_proc at all is a TypeError.
      class NoProc; end
      begin
        [1].map(&NoProc.new)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2", "3"]
      ["A", "B"]
      [2, 4, 6]
      [3, 6, 9]
      [2, 4, 6]
      [20, 40]
      true
      TypeError: can't convert BadProc to Proc (BadProc#to_proc gives Symbol)
      TypeError: no implicit conversion of NoProc into Proc
    OUT
  end

  it "a **obj argument converts through to_hash" do
    result = ze0(<<~'RUBY')
      # Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
      # `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
      # Each is duck-typed -- any object answering the method participates.

      # --- **obj -> to_hash ------------------------------------------------------

      class Opts
        def to_hash = { a: 1, b: 2 }
      end

      def take(a:, b:) = [a, b]
      p take(**Opts.new)

      # Into a keyword-rest callee.
      def collect(**o) = o
      p collect(**Opts.new)

      # An explicit keyword alongside the converted splat.
      p collect(x: 9, **Opts.new)

      # A later key wins, matching Hash#merge order.
      p collect(a: 99, **Opts.new)

      # A converter held in a local.
      o = Opts.new
      p take(**o)

      # A plain Hash splats without any conversion.
      h = { a: 5, b: 6 }
      p take(**h)
      p collect(c: 7, **h)

      # An object with no to_hash is a TypeError.
      class NoHash; end
      begin
        collect(**NoHash.new)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      {a: 1, b: 2}
      {x: 9, a: 1, b: 2}
      {a: 1, b: 2}
      [1, 2]
      [5, 6]
      {c: 7, a: 5, b: 6}
      TypeError: no implicit conversion of NoHash into Hash
    OUT
  end

  it "a splat and a destructuring assignment convert through to_ary" do
    result = ze0(<<~'RUBY')
      # Ruby's implicit-conversion protocols: `&obj` converts through `to_proc`,
      # `**obj` through `to_hash`, and a splice/auto-splat value through `to_ary`.
      # Each is duck-typed -- any object answering the method participates.

      # --- to_ary ----------------------------------------------------------------

      class Pair
        def initialize(a, b)
          @a = a
          @b = b
        end
        def to_ary = [@a, @b]
      end

      # Block auto-splat coerces through to_ary.
      def one(v)
        yield v
      end
      p(one(Pair.new(1, 2)) { |a, b| [a, b] })

      # Multiple assignment destructures through to_ary.
      x, y = Pair.new(3, 4)
      p [x, y]

      # An Array splice coerces the right-hand side through to_ary.
      arr = [1, 2, 3]
      arr[1, 1] = Pair.new(7, 8)
      p arr

      # A `for` loop's destructuring target.
      [[1, 2]].each do |a, b|
        p [a, b]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3, 4]
      [1, 7, 8, 3]
      [1, 2]
    OUT
  end

  it "the conversion functions raise TypeError for a bad argument type and RangeError past the bound" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Kernel conversion functions raise ArgumentError where ruby raises
      # TypeError for a bad argument type.
      #
      r001 = (Integer({}) rescue $!.class)
      p r001

      class Conv003; def to_f; 1.25; end; end
      p(Float(Conv003.new))          # Ruby: 1.25
      p(Float(Rational(1, 2)))       # Ruby: 0.5
      p(Float(Complex(1.5, 0)))      # Ruby: 1.5

      class Conv004; def to_int; 8; end; end
      p(Integer(Conv004.new))        # Ruby: 8   Spinel: can't convert Conv004 into Integer (TypeError)
      p(Integer(Rational(4, 2)))     # Ruby: 2   Spinel: can't convert Rational into Integer (TypeError)
      p(Integer(Complex(3, 0)))      # Ruby: 3   Spinel: can't convert Complex into Integer (TypeError)

      r005 = (Float(true) rescue $!.class); p r005      # Ruby: TypeError   Spinel: 1.0
      r006 = (Float(:s) rescue $!.class); p r006        # Ruby: TypeError   Spinel: 0.0

      r007 = (Integer([1]) rescue $!.class); p r007     # => TypeError
      r008 = (Integer(1..2) rescue $!.class); p r008    # => TypeError
      r009 = (Integer(true) rescue $!.class); p r009    # => TypeError
      r010 = (Integer(false) rescue $!.class); p r010   # => TypeError
      r011 = (Integer(:sym) rescue $!.class); p r011    # => TypeError

      p(Integer("42"))
      p(Float("1.5"))
      p(Integer(3.9))
      p(Float(3))
      r = (Float(Complex(1, 2)) rescue $!.class); p r
      r = (Integer(Complex(1, 2)) rescue $!.class); p r
      r = (Integer({}) rescue $!.class); p r
      r = (Float([]) rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      1.25
      0.5
      1.5
      8
      2
      3
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      42
      1.5
      3
      3.0
      RangeError
      RangeError
      TypeError
      TypeError
    OUT
  end

  it "method objects bind a receiver and convert to procs" do
    result = ze0(<<~'RUBY')
      def double(x) = x * 2
      m = method(:double)
      p m.call(21)
      p m.(21)
      p m[21]
      p m.name
      p [1, 2].map(&method(:double))

      class Greeter
        def initialize(g) = @g = g
        def greet(name) = "#{@g}, #{name}!"
      end
      g = Greeter.new("Hello")
      gm = g.method(:greet)
      p gm.call("Ada")
      p gm.receiver.equal?(g)
      p "hello".method(:upcase).call
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      42
      :double
      [2, 4]
      "Hello, Ada!"
      true
      "HELLO"
    OUT
  end

  it "method to proc carries its block" do
    result = ze0(<<~'RUBY')
      # The Proc `Method#to_proc` builds forwards its block to the wrapped method.
      #
      # It used to drop it, so a block-taking method reached through `to_proc` ran
      # block-less: `h.method(:each).to_proc.call { }` iterated zero times and
      # answered an Enumerator where ruby answers the receiver. `Method#call` with a
      # block was always right -- only the proc `to_proc` returned had no block
      # channel, which also took `&method(:x)`, `UnboundMethod#bind(o).to_proc` and
      # `#curry` down with it.
      #
      # The rows below are the whole family: the two that always worked are kept as
      # controls, so a regression names which half broke.

      def takes_block
        block_given? ? yield : :no_block
      end

      class Target
        def takes_block
          block_given? ? yield : :no_block
        end
      end

      # The control: a Method called directly has always carried its block.
      puts method(:takes_block).call { :ran }

      # The fix: through to_proc, in each of the ways a proc can be called.
      pr = method(:takes_block).to_proc
      puts pr.call { :ran }
      puts pr.() { :ran }
      puts pr.call(&-> { :ran })

      # `&method(:x)` is the common idiom, and it goes through to_proc.
      def relay(&blk) = blk.call { :ran }
      puts relay(&method(:takes_block))

      # An UnboundMethod bound to a receiver builds its proc the same way.
      puts Target.instance_method(:takes_block).bind(Target.new).to_proc.call { :ran }

      # curry's final application is the step that reaches the target, so the block
      # rides that one.
      puts method(:takes_block).to_proc.curry.call { :ran }

      # Two more controls, from the neighbouring constructors that never broke.
      puts :takes_block.to_proc.call(Target.new) { :ran }
      puts(proc { |&b| takes_block(&b) }.call { :ran })

      # The receiver comes back, not an Enumerator -- the tell that the block ran.
      h = {"k" => 1}
      seen = []
      puts h.method(:each).to_proc.call { |k, v| seen << [k, v] }.class
      p seen
    RUBY

    _(result).must_answer <<~'OUT'
      ran
      ran
      ran
      ran
      ran
      ran
      ran
      ran
      ran
      Hash
      [["k", 1]]
    OUT
  end

  it "nilclass bool ops conversions" do
    result = ze0(<<~'RUBY')
      # NilClass: boolean & | ^ (variable and literal receivers), ===, and the
      # conversions to_a/to_h/to_r/to_c on a nil-holding (poly-widened) variable.
      x = nil
      p(x.to_a)
      p(x.to_h)
      p(x.to_r)
      p(x.to_c)
      p(x === nil)
      p(x === 1)
      p(x & true)
      p(x | true)
      p(x ^ true)
      p(x | false)
      p(x ^ false)
      p(nil & true)
      p(nil | 5)
      p(nil ^ nil)
      p(nil === nil)
      p(nil === 0)
      p(nil.to_c)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      {}
      (0/1)
      (0+0i)
      true
      false
      false
      true
      true
      false
      false
      false
      true
      false
      true
      false
      (0+0i)
    OUT
  end

  it "user to proc block arg" do
    result = ze0(<<~'RUBY')
      # `&obj` where obj defines #to_proc converts through to_proc, exactly as CRuby
      # does: to_proc is called ONCE to obtain the block, then that proc runs per element.
      class Dbl
        def to_proc = ->(x) { x * 2 }
      end
      p [1, 2, 3].map(&Dbl.new)

      # a converter held in a local variable
      d = Dbl.new
      p [10, 20].map(&d)

      # forwarding to other iterators
      class IsEven
        def to_proc = ->(x) { x.even? }
      end
      p [1, 2, 3, 4, 5, 6].select(&IsEven.new)
      p [1, 2, 3, 4].count(&IsEven.new)

      # to_proc is evaluated exactly once even with an observable side effect
      class Counting
        def initialize; @calls = 0; end
        def to_proc; @calls += 1; ->(x) { x + @calls }; end
        def calls = @calls
      end
      c = Counting.new
      p [0, 0, 0].map(&c)
      p c.calls
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      [20, 40]
      [2, 4, 6]
      2
      [1, 1, 1]
      1
    OUT
  end

  it "yielder to proc" do
    result = ze0(<<~'RUBY')
      p(Enumerator.new { |y| y.to_proc.call(1) }.to_a)
      p(Enumerator.new { |y| [1, 2, 3].each(&y.to_proc) }.to_a)
      p(Enumerator.new { |y| [1, 2, 3].each(&y) }.to_a)
      p(Enumerator.new { |y| [1, 2, 3].each { |x| y << x } }.to_a)
      p(Enumerator.new { |y| y.yield 5 }.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, 2, 3]
      [1, 2, 3]
      [1, 2, 3]
      [5]
    OUT
  end
end
