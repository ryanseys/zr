# frozen_string_literal: true

require "spec_helper"

describe "Blocks: enumeration" do
  it "block and proc argument semantics" do
    result = ze0(<<~'RUBY')
      h = { a: 1, b: 2 }
      h.each { |pair| p pair }
      h.each { |k, v| puts "#{k}=#{v}" }
      def show(pair) = p pair
      h.each(&method(:show))

      add = proc { |a:, b:| a + b }
      p add.call(a: 1, b: 2)
      opt = proc { |x:, y: 100| [x, y] }
      p opt.call(x: 5)
      begin
        add.call(a: 1)
      rescue ArgumentError => e
        puts e.message
      end

      lam = ->(x:, y: 9) { [x, y] }
      p lam.call(x: 5)

      pr = proc { |a, b| [a, b] }
      p pr.call(1, 2, 3)
      p pr.call(1)
      p [[1, 2], [3, 4]].map { |a, b| a + b }
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:b, 2]
      a=1
      b=2
      [:a, 1]
      [:b, 2]
      3
      [5, 100]
      missing keyword: :b
      [5, 9]
      [1, 2]
      [1, nil]
      [3, 7]
    OUT
  end

  it "block escaping from inside another escaping block works" do
    result = ze0(<<~'RUBY')
      # The original blanket rejection of Proc-within-Proc was LIFTED
      # (`Thread.new { m.synchronize { } }` is the canonical threading
      # idiom): method-level captures are shared cells that compose through
      # any nesting depth. This exact snippet was that rejection's own
      # negative test -- now a positive one, oracle-verified.

      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      c = Collector.new
      c.each_num(1, 2) { |n| c.each_num(n, n) { |m| puts m } }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      2
    OUT
  end

  it "block forward map" do
    result = ze0(<<~'RUBY')
      # A method taking a block (&blk) can forward it to an array's #map /
      # #collect: each element is mapped through the caller's block and the
      # results are collected. The forwarded `&blk` is a BlockArgumentNode
      # with no body, so the map codegen resolves it to the active inlined
      # block instead of treating it as an empty (nil-producing) block.
      # Reuses the typed-map machinery, so element/result type inference
      # (int, string, and int<->string conversions) all flow through.
      def doubled(arr, &blk)
        arr.map(&blk)
      end
      p doubled([1, 2, 3]) { |x| x * 2 }

      # #collect alias, result fed into a further computation.
      def mapped(arr, &blk)
        arr.collect(&blk)
      end
      p mapped([1, 2, 3]) { |n| n * n }

      # int element -> string result.
      def to_strings(arr, &blk)
        arr.map(&blk)
      end
      p to_strings([1, 2, 3]) { |x| x.to_s }

      # string element -> int result.
      def lengths(arr, &blk)
        arr.map(&blk)
      end
      p lengths(["a", "bb", "ccc"]) { |s| s.length }

      # Class instance method forwarding &blk to #map.
      class Calc
        def squares(arr, &blk)
          arr.map(&blk)
        end
      end
      p Calc.new.squares([1, 2, 3]) { |n| n * n }

      # Method does work before forwarding; the forward still resolves.
      def announced(arr, &blk)
        puts "mapping"
        arr.map(&blk)
      end
      p announced([2, 4, 6]) { |x| x / 2 }

      # Anonymous `&` forward (Ruby 3.1+): the unnamed block param forwards
      # through the matching anonymous `&` at the #map call.
      def tripled(arr, &)
        arr.map(&)
      end
      p tripled([1, 2, 3]) { |x| x * 3 }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      [1, 4, 9]
      ["1", "2", "3"]
      [1, 2, 3]
      [1, 4, 9]
      mapping
      [1, 2, 3]
      [3, 6, 9]
    OUT
  end

  it "block forward proc param type" do
    result = ze0(<<~'RUBY')
      def fwd_map(&b)  = ["a", "bb"].map(&b)
      def fwd_sel(&b)  = ["a", "bb"].select(&b)
      def fwd_sort(&b) = ["a", "bb"].sort_by(&b)
      def fwd_min(&b)  = ["a", "bb"].min_by(&b)
      def fwd_max(&b)  = ["a", "bb"].max_by(&b)
      def fwd_grp(&b)  = ["a", "bb"].group_by(&b)
      def fwd_cnt(&b)  = ["a", "bb"].count(&b)

      len = ->(s) { s.length }
      p fwd_map(&len)
      p fwd_sort(&len)
      p fwd_min(&len)
      p fwd_max(&len)
      p fwd_grp(&len)

      long = ->(s) { s.length > 1 }
      p fwd_sel(&long)
      p fwd_cnt(&long)

      def fwd_int(&b) = [1, 2].map(&b)
      dbl = ->(x) { x * 2 }
      p fwd_int(&dbl)

      p(["a", "bb"].map(&len))
      p(["a", "bb"].map { |s| s.length })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      ["a", "bb"]
      "a"
      "bb"
      {1 => ["a"], 2 => ["bb"]}
      ["bb"]
      1
      [2, 4]
      [1, 2]
      [1, 2]
    OUT
  end

  it "block local fresh cell" do
    result = ze0(<<~'RUBY')
      # A block-local captured by a nested proc gets a FRESH cell per block
      # invocation (#3230): each iteration's closure keeps its own binding.
      # Within one iteration the closure and the block body still share the
      # cell, and method-level captures stay shared across calls.
      p((1..3).map { |b| n = b; -> { n } }.map(&:call))
      p((1..3).map { |b| s = "v#{b}"; -> { s } }.map(&:call))
      p((1..3).map { |b| f = b * 1.5; -> { f } }.map(&:call))
      p((1..3).map { |b| a = [b]; -> { a } }.map(&:call))
      acc = []
      (1..2).each { |i| x = i; g = -> { x += 10 }; g.call; acc << x }
      p acc
      y = 0
      inc = -> { y += 1 }
      inc.call; inc.call
      p y
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      ["v1", "v2", "v3"]
      [1.5, 3.0, 4.5]
      [[1], [2], [3]]
      [11, 12]
      2
    OUT
  end

  it "block local widens map result" do
    result = ze0(<<~'RUBY')
      # Local types are recomputed from scratch each inference round, in node order.
      # A local assigned inside an iterator block sits at a higher node id than the
      # write that receives the iterator's value, so that write derived its type with
      # the block's locals still reset -- narrower than what the block really yields.
      # The result array was then declared as an Integer array while the loop pushed
      # boxed values into a poly one, printing 16 zero-padded elements. #3463.
      ws = [[1, 2], [3, 4]]
      p([0, 1].map { |i| w = ws.select { |a, _| a > 0 }.last; w ? w[0] : 9 })
      p([0, 1].map { |i| w = ws.select { |a, _| a > 0 }.first; w ? w[0] : 9 })
      p([0, 1].map { |i| w = ws.reject { |a, _| a < 0 }.last; w ? w[0] : 9 })
      p([0, 1].map { |i| w = ws.select { |a, _| a > 0 }.last; if w then w[0] else 9 end })
      p((0..1).map { |i| w = ws.select { |a, _| a > 0 }.last; w ? w[0] : 9 })
      p([0, 1].each_with_object([]) { |i, acc| w = ws.select { |a, _| a > 0 }.last; acc << (w ? w[0] : 9) })
      p([0, 1].map { |i| ws.select { |a, _| a > 0 }.last[0] })
      ws2 = [1, 2]
      p([0, 1].map { |i| w = ws2.select { |a| a > 0 }.last; w ? w + 1 : 9 })
      def f(ws) = (w = ws.select { |a, _| a > 0 }.last; w ? w[0] : 9)
      p([0, 1].map { |i| f([[1, 2], [3, 4]]) })
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 3]
      [1, 1]
      [3, 3]
      [3, 3]
      [3, 3]
      [3, 3]
      [3, 3]
      [3, 3]
      [3, 3]
    OUT
  end

  it "block tail empty literal" do
    result = ze0(<<~'RUBY')
      [].then { [] }.tap { p 0 }

      p([].then { [] })
      p([1].then { [] })
      p(1.then { [] })
      p("s".then { [] })
      p([].then { {} })
      p([].then { [] }.size)
      p([].then { [] } + [1])
      p([].yield_self { [] })

      x = [].then { [] }
      p x
      p x.class

      p([].then { [1] })
      p([].tap { [] })
      p([1].map { [] })
      p([1, 2].each_with_object([]) { |e, m| m << e })

      a = [1, 2].map { [] }
      a[0] << 1
      p a

      pr = proc { [] }
      p pr.call
      l = -> { [] }
      p l.call
    RUBY

    _(result).must_answer <<~'OUT'
      0
      []
      []
      []
      []
      {}
      0
      [1]
      []
      []
      Array
      [1]
      []
      [[]]
      [1, 2]
      [[1], []]
      []
      []
    OUT
  end

  it "block2" do
    result = ze0(<<~'RUBY')
      # Test block_given? and optional blocks

      def maybe_yield(x)
        if block_given?
          yield x
        else
          x * 2
        end
      end

      puts maybe_yield(5)  # 10 (no block)

      result = 0
      maybe_yield(5) do |n|
        result = n * 3
      end
      puts result  # 15

      # Method that always yields
      def each_pair(a, b)
        yield a
        yield b
      end

      total = 0
      each_pair(10, 20) do |n|
        total += n
      end
      puts total  # 30

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      15
      30
      done
    OUT
  end

  it "yield, block_given?, break, next and a closure over a local all answer" do
    result = ze0(<<~'RUBY', path: "ze0/blocks_and_closures.rb")
      def each_twice
        yield 1
        yield 2
        :done
      end

      def maybe
        return :no_block unless block_given?

        yield 41
      end

      def collect
        out = []
        yield out
        out
      end

      p [1, 2, 3].each { |x| puts x }
      p [1, 2, 3].map { |x| x * 2 }
      p [1, 2, 3, 4].select { |x| x > 2 }
      p({ "a" => 1, "b" => 2 }.map { |k, v| "#{k}=#{v}" })
      p [[1, 2], [3, 4]].map { |a, b| a + b }
      p [3, 1, 2].sort { |a, b| a <=> b }

      p(each_twice { |x| puts x })
      p maybe
      p(maybe { |x| x + 1 })
      p(collect { |o| o << :one; o << :two })
      p(each_twice { |x| break :broken })

      p [1, 2, 3].each { |x| next if x == 2; puts x }
      p [1, 2, 3].map { |x| next 0 if x == 2; x }
      p [1, 2, 3].each { |x| break :stopped if x == 2 }

      offset = 10
      p [1, 2].map { |x| x + offset }

      total = 0
      [1, 2, 3].each { |x| total += x }
      p total

      label = "n"
      p [1, 2].map { |i| "#{label}#{i}" }

      pairs = []
      [1, 2].each { |i| [10, 20].each { |j| pairs << i * j } }
      p pairs

      made = []
      [1, 2, 3].each { |i| made << proc { i * 100 } }
      p made.map { |pr| pr.call }

      pr = proc { |x, y| x }
      p pr.call(7, 8)
      p pr.arity
      p pr.lambda?
      p pr.parameters
      la = lambda { |x, y| x - y }
      p la.call(10, 3)
      p la.arity
      p la.lambda?

      # A `yield` written INSIDE a block reaches the enclosing method's block,
      # which the proc carries along. Two of them in sibling branches read one
      # value, and neither branch runs before the other.
      def relay(list)
        list.map do |n|
          if n.odd?
            yield n
          else
            yield(n * 10)
          end
        end
      end

      p relay([1, 2, 3]) { |v| v + 100 }

      # `block_given?` and a `->` in the same block read it too.
      def either(list)
        list.map do |n|
          next (-> { n }).call unless block_given?

          yield n
        end
      end

      p either([1, 2])
      p either([1, 2]) { |v| v * 3 }

      def boom
        [1].each { |x| raise "inside" }
      end
      boom
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR', status: 1
      1
      2
      3
      [1, 2, 3]
      [2, 4, 6]
      [3, 4]
      ["a=1", "b=2"]
      [3, 7]
      [1, 2, 3]
      1
      2
      :done
      :no_block
      42
      [:one, :two]
      :broken
      1
      3
      [1, 2, 3]
      [1, 0, 3]
      :stopped
      [11, 12]
      6
      ["n1", "n2"]
      [10, 20, 20, 40]
      [100, 200, 300]
      7
      2
      false
      [[:opt, :x], [:opt, :y]]
      7
      2
      true
      [101, 120, 103]
      [1, 2]
      [3, 6]
    OUT
      ze0/blocks_and_closures.rb:92:in 'block in Object#boom': inside (RuntimeError)
      	from ze0/blocks_and_closures.rb:92:in 'Array#each'
      	from ze0/blocks_and_closures.rb:92:in 'Object#boom'
      	from ze0/blocks_and_closures.rb:94:in '<main>'
    ERR
  end

  it "a method yields to its block, and a proc carries the enclosing scope wherever it is called" do
    result = ze0(<<~'RUBY')
      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end

      class Greeter
        def maybe_greet
          if block_given?
            yield "Ada"
          else
            "no block"
          end
        end
      end

      g = Greeter.new
      puts g.maybe_greet { |name| "Hello, #{name}!" }
      puts g.maybe_greet

      total = 0
      Collector.new.each_num(1, 2, 3) { |n| total += n }
      puts total

      class Box
        def initialize
          @sum = 0
        end
        def total
          @sum
        end
        def run
          c = Collector.new
          c.each_num(1, 2, 3) { |n| @sum += n }
        end
      end
      b = Box.new
      b.run
      puts b.total

      result = Collector.new.each_num(1, 2, 3) { |n| next if n == 2; break "stopped" if n == 3; puts n }
      puts result

      class Finder
        def find_even
          c = Collector.new
          c.each_num(1, 3, 4) { |n| return n if n % 2 == 0 }
          -1
        end
      end
      puts Finder.new.find_even

      total2 = 0
      Collector.new.send(:each_num, 1, 2, 3) { |n| total2 += n }
      puts total2

      3.times { |i| puts i * 10 }
      Collector.new.each_num(5, 6, 7) { puts _1 * 2 }
      Collector.new.each_num(8, 9, 10) { puts it + 1 }

      class Box2
        def call_with(&blk)
          blk.call(5)
        end
      end
      puts Box2.new.call_with { |x| x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, Ada!
      no block
      6
      6
      1
      stopped
      4
      6
      0
      10
      20
      10
      12
      14
      9
      10
      11
      10
    OUT
  end

  it "curry block and zero arg" do
    result = ze0(<<~'RUBY')
      add001 = ->(a, b) { a + b }.curry[10]
      p [1, 2, 3].map(&add001)
      p(->() { 5 }.curry.call)
      c002 = ->() { 5 }.curry
      p c002.call
      p c002[]
      mul = ->(a, b) { a * b }.curry
      p [1, 2, 3].select(&mul[1]).class
      p [4, 5].map(&->(a, b) { a * b }.curry[3])
    RUBY

    _(result).must_answer <<~'OUT'
      [11, 12, 13]
      5
      5
      5
      Array
      [12, 15]
    OUT
  end

  it "empty literal block param" do
    result = ze0(<<~'RUBY')
      # An unused block parameter over an empty literal has no element type to infer
      # from, so it is pruned and has no C declaration: the binding must be skipped
      # rather than name an undeclared variable (#3853).
      p([].each_with_index { |x, i| p i })
      p([1, 2].each_with_index { |x, i| p [x, i] })
      p([].each_with_index { |x, i| p x })
      p([].each { |x| p x })
      p([].map { |x| x })
      h = {}
      p(h.each_with_index { |pair, i| p i })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1, 0]
      [2, 1]
      [1, 2]
      []
      []
      []
      {}
    OUT
  end

  it "empty literal unused block param" do
    result = ze0(<<~'RUBY')
      p([].map { |x| 1 })

      p([].each_with_object([]) { |x, a| a })     # Ruby: []    Spinel: undeclared identifier 'lv_x'
      p([].each_with_object(0) { |x, a| a })      # Ruby: 0     Spinel: undeclared identifier 'lv_x'
      p([].each_with_object("s") { |x, a| a })    # Ruby: "s"   Spinel: undeclared identifier 'lv_x'
      p([].each_with_object([]) { |_x, a| a })    # Ruby: []    Spinel: undeclared identifier 'lv__x'

      p([].map { |x| x })                             # => []
      p([1].map { |x| 1 })                            # => [1]
      a = []; p(a.map { |x| 1 })                      # => []
      p([].each { |x| 1 })                            # => []
      p([].each_with_object([]) { |x, a| a << x })    # => []
      p([1].each_with_object([]) { |x, a| a })        # => []
      p([].each_with_index { |x, i| i })              # => []

      p([].select { |x| 1 })
      p([].reject { |x| true })
      p([].flat_map { |x| [1] })
      p([].each_with_index { |x, i| 1 })
      p([].sort_by { |x| 1 })
      p({}.map { |k, v| 1 })
      p([].map { |x| x })
      p([1, 2].map { |x| 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      0
      "s"
      []
      []
      [1]
      []
      []
      []
      []
      []
      []
      []
      []
      []
      []
      []
      []
      [1, 1]
    OUT
  end

  it "enum each family receiver" do
    result = ze0(<<~'RUBY')
      # Enumerable/Struct each-family block calls (reverse_each, each_with_index)
      # return the receiver, not the intermediate member array, and the synthesized
      # __enum_to_a bridge stays invisible to reflection while user methods do not.
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
        def __private_helper; 42; end
      end
      n = Nums.new(3, 1, 2)
      acc = []
      r = n.reverse_each { |x| acc << x }
      p acc
      p r.equal?(n)
      p n.each_with_index { |x, i| }.equal?(n)
      p n.respond_to?(:__enum_to_a)
      p n.respond_to?(:__private_helper)
      p n.respond_to?(:map)
      p Nums.instance_methods(false).include?(:__enum_to_a)
      p Nums.instance_methods(false).include?(:__private_helper)

      Pt = Struct.new(:a, :b, :c)
      s = Pt.new(3, 1, 2)
      sb = []
      sr = s.reverse_each { |v| sb << v }
      p sb
      p sr.equal?(s)
      p s.respond_to?(:__enum_to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 1, 3]
      true
      true
      false
      true
      true
      false
      true
      [2, 1, 3]
      true
      false
    OUT
  end

  it "escaping proc captures value self" do
    result = ze0(<<~'RUBY')
      # An escaping proc that reads its enclosing instance's ivars must capture self.
      # For a value-type (by-value) class, self is captured by value in the proc's
      # capture struct (a real sp_X field), not by pointer.

      class Box
        def initialize(a, b)
          @a = a
          @b = b
        end
        def mk = proc { @a + @b }
      end
      p Box.new(3, 4).mk.call

      # value-type with a String ivar (the captured self must be GC-scanned)
      class Pt
        def initialize(name, x)
          @name = name
          @x = x
        end
        def label = proc { "#{@name}=#{@x}" }
      end
      p Pt.new("a", 5).label.call

      # capture self AND a parameter local
      class Calc
        def initialize(base)
          @base = base
        end
        def adder(k) = proc { @base + k }
      end
      p Calc.new(10).adder(3).call

      # many escaping procs stored then called later
      class Acc
        def initialize(v)
          @v = v
        end
        def getter = proc { @v * 2 }
      end
      p [Acc.new(1).getter, Acc.new(2).getter, Acc.new(3).getter].map(&:call)

      # escaping proc CREATED INSIDE initialize: self is held as sp_X* there, so the
      # body's by-value captured self must still read ivars with `.`, not `->`.
      class Reg
        def initialize(n, sink)
          @n = n
          sink << proc { @n * 3 }
        end
      end
      sink = []
      Reg.new(5, sink)
      Reg.new(6, sink)
      p sink.map(&:call)

      # escaping Fiber created inside initialize of a value-type class -- the same
      # by-value-self / `.`-deref requirement as the proc path.
      class FibReg
        def initialize(v, fsink)
          @v = v
          fsink << Fiber.new { Fiber.yield(@v + 1); @v + 2 }
        end
      end
      fsink = []
      FibReg.new(10, fsink)
      fib = fsink[0]
      p fib.resume
      p fib.resume
    RUBY

    _(result).must_answer <<~'OUT'
      7
      "a=5"
      13
      [2, 4, 6]
      [15, 18]
      11
      12
    OUT
  end

  it "filter map poly receiver" do
    result = ze0(<<~'RUBY')
      # filter_map on a receiver known only at run time -- a hash value, a nested
      # array element, a container read. Every other collector in the family has an
      # arm for a poly receiver; filter_map had none, so the call fell past all of
      # them into the hash-face coercion, which reads the receiver as a Hash and
      # raises NoMethodError naming the method it was about to call (#4007):
      #
      #   {0 => [[]]}.map { |_, g| p g.filter_map{} }
      #   # undefined method 'filter_map' for an instance of Array
      #
      # The block body is not the trigger -- the reported spelling used an empty one
      # because it came out of #4006, but a full block fails identically.
      { 0 => [[]] }.map do |_, g|
        p g.filter_map {}
      end

      { 0 => [1, nil, 2] }.map do |_, g|
        p g.filter_map { |x| x }
      end

      { 0 => [1, 2, 3] }.each do |_, g|
        p g.filter_map { |x| x if x.odd? }
      end

      # a nested array element is the same shape without a hash
      [[1, nil, 2]].map { |g| p g.filter_map { |x| x } }

      # and so is a plain container read
      h = { 0 => [1, nil, 2] }
      g = h[0]
      p g.filter_map { |x| x }
      p g.filter_map {}

      # a forwarded proc reaches the runtime enumerable helper rather than a spliced
      # loop, and that surface was missing filter_map too
      f = ->(x) { x if x.odd? }
      { 0 => [1, 2, 3] }.map { |_, k| p k.filter_map(&f) }

      # the receiver really can be a Hash, and then filter_map is over its pairs
      { 0 => { a: 1, b: nil } }.map do |_, g|
        p g.filter_map { |k, v| v && k }
      end
      p({ a: 1, b: nil }.filter_map { |k, v| v && k })

      # the typed forms still answer
      p [1, nil, 2].filter_map { |x| x }
      p [1, 2, 3].filter_map { |x| x if x.odd? }
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1, 2]
      [1, 3]
      [1, 2]
      [1, 2]
      []
      [1, 3]
      [:a]
      [:a]
      [1, 2]
      [1, 3]
    OUT
  end

  it "forwarded block to iterator" do
    result = ze0(<<~'RUBY')
      def run001(&b001); [1, 2].map(&b001); end
      tri001 = ->(x001) { x001 * 3 }
      p run001(&tri001)

      def run002(&b002); [1, 2].map(&b002); end
      pr002 = proc { |x002| x002 * 3 }; p run002(&pr002)   # Ruby: [3, 6]
      def sq003(n003) = n003 * 3
      def run003(&b003); [1, 2].map(&b003); end
      p run003(&method(:sq003))                            # Ruby: [3, 6]

      def run004(&b004); [1, 2].map(&b004); end
      p run004 { |x004| x004 * 3 }         # => [3, 6]
      def run005(&b005); b005.call(3); end
      tri005 = ->(x005) { x005 * 3 }
      p run005(&tri005)                    # => 9
      p run005(&proc { |x006| x006 * 3 })  # => 9
      def sq007(n007) = n007 * n007
      p run005(&method(:sq007))            # => 9
      def run008; yield 3; end
      p run008(&tri005)                    # => 9
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [3, 6]
      [3, 6]
      [3, 6]
      9
      9
      9
      9
    OUT
  end

  it "it has no name in parameters" do
    result = ze0(<<~'RUBY')
      p proc { it }.parameters, lambda { it }.parameters
      p proc { _1 }.parameters, lambda { _1 }.parameters
      p proc { it }.arity, lambda { it }.arity
      p proc { it; binding.local_variables }.call(5)
      p proc { it; local_variables }.call(5)
      p [1, 2].map { it * 2 }
      p [[1, 2]].map { it }
      p [1, 2].map { [it, [3].map { it + 1 }] }
      p proc { defined?(it) }.call(1)

    RUBY

    _(result).must_answer <<~'OUT'
      [[:opt]]
      [[:req]]
      [[:opt, :_1]]
      [[:req, :_1]]
      1
      1
      []
      []
      [2, 4]
      [[1, 2]]
      [[1, [4]], [2, [4]]]
      "local-variable"
    OUT
  end

  it "it works through a real escaping proc" do
    result = ze0(<<~'RUBY')
      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      Collector.new.each_num(7, 8) { puts it + 1 }
    RUBY

    _(result).must_answer "8\n9\n"
  end

  it "lambda escaping inside an escaping block" do
    result = ze0(<<~'RUBY')
      # A lambda literal nested inside a stored (escaping) block used to be
      # rejected at compile time; it now composes through the capture analysis
      # like any other escaping closure.

      makers = [1, 2, 3].map do |n|
        -> { n * 10 }
      end
      p makers.map(&:call)

      def build
        total = 0
        adder = ->(x) { total += x }
        [adder, -> { total }]
      end
      add, get = build
      add.call(5)
      add.call(7)
      p get.call

      squares = (1..3).map { |i| -> { i * i } }
      p squares.map(&:call)
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30]
      12
      [1, 4, 9]
    OUT
  end

  it "lambda in escaping block" do
    result = ze0(<<~'RUBY')
      # A lambda defined INSIDE an escaping block (a stored Proc) -- previously
      # rejected at compile time, now composes through the capture analysis.

      # Each closure in `makers` builds and immediately calls a lambda that closes
      # over the closure's own parameter.
      makers = [1, 2, 3].map do |n|
        -> { n * 10 }
      end
      p makers.map(&:call)          # [10, 20, 30]

      # A lambda nested inside a stored block that closes over an enclosing-method
      # local (a shared cell), mutated between calls.
      def build
        total = 0
        adder = ->(x) { total += x }
        [adder, -> { total }]
      end
      add, get = build
      add.call(5)
      add.call(7)
      p get.call                    # 12

      # A lambda returned from within an iterator block, capturing the block param.
      squares = (1..3).map { |i| -> { i * i } }
      p squares.map(&:call)         # [1, 4, 9]
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30]
      12
      [1, 4, 9]
    OUT
  end

  it "map result widened by composition" do
    result = ze0(<<~'RUBY')
      # A local assigned a `map` whose block value type widens LATE. Composing the
      # same method with `>>` widens its parameters to poly -- the composition's
      # intermediate value is only known at run time -- so its return widens too and
      # the map builds a poly array. The local had already settled on the typed array
      # kind and kept it, so the assignment did not compile (#4009):
      #
      #   error: assignment to 'sp_IntArray *' from incompatible pointer type
      #          'sp_PolyArray *'
      #
      # `&method(:m)` is not the trigger: a literal block calling the same method
      # fails identically, and either statement alone compiles.
      def double(n) = n * 2

      v = [1, 2, 3].map(&method(:double))
      p v
      p (method(:double).to_proc >> ->(x) { x + 1 }).call(3)

      def triple(n) = n * 3
      w = [1, 2, 3].map { |x| triple(x) }
      p w
      p (method(:triple).to_proc << ->(x) { x + 1 }).call(3)

      # neither statement alone was ever a problem
      def quad(n) = n * 4
      p [1, 2, 3].map(&method(:quad))
      p method(:quad).to_proc.call(3)

      # and an ordinary typed map keeps its kind
      z = [1, 2, 3].map { |x| x * 2 }
      p z
      p z.sum
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      7
      [3, 6, 9]
      12
      [4, 8, 12]
      12
      [2, 4, 6]
      12
    OUT
  end

  it "multi yield map param" do
    result = ze0(<<~'RUBY')
      class Pairs
        include Enumerable
        def each; yield :a, 1; yield :b, 2; end
      end
      p(Pairs.new.map { |x001| x001 })

      p(Pairs.new.map { |k002, v002| [k002, v002] })   # => [[:a, 1], [:b, 2]]
      p(Pairs.new.select { |x003| true })              # => [[:a, 1], [:b, 2]]
      p(Pairs.new.find { |x004| true })                # => [:a, 1]
      p(Pairs.new.sort_by { |x005| x005.to_s })        # => [[:a, 1], [:b, 2]]
      p(Pairs.new.count)                               # => 2
      Pairs.new.each { |x006| p x006 }                 # => :a then :b
      def y007; yield :a, 1; end
      p(y007 { |x007| x007 })                          # => :a
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b]
      [[:a, 1], [:b, 2]]
      [[:a, 1], [:b, 2]]
      [:a, 1]
      [[:a, 1], [:b, 2]]
      2
      :a
      :b
      :a
    OUT
  end

  it "named block param can be forwarded to another call" do
    result = ze0(<<~'RUBY')
      # `c` is a `New`-assigned LOCAL inside `go`, not a parameter or an
      # implicit-self call target -- see the self-capture test's comment for
      # why (both are separate, pre-existing, unrelated gaps).

      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      class Relay
        def go(a, b, &blk)
          c = Collector.new
          c.each_num(a, b, &blk)
        end
      end
      total = 0
      Relay.new.go(3, 4) { |n| total += n }
      puts total
    RUBY

    _(result).must_answer "7\n"
  end

  it "nested block captures own local" do
    result = ze0(<<~'RUBY')
      # A nested escaping closure that captures the ENCLOSING block's own local
      # (not just the block param). That local must become a shared cell, declared
      # once -- previously the own-locals prelude also fresh-declared it, shadowing
      # the cell (the inner closure read nil), or tripped an internal invariant.

      adders = []
      [1, 2, 3].each do |n|
        base = n * 100          # the block's own local
        adders << -> { base + n }
      end
      p adders.map(&:call)      # [101, 202, 303]

      # The own local is mutated after the capturing closures are built, and every
      # closure observes the final value through the shared cell.
      procs = []
      [10, 20].each do |k|
        acc = 0
        procs << -> { acc }
        acc = k + 1
        procs << -> { acc }
      end
      p procs.map(&:call)       # [11, 11, 21, 21]
    RUBY

    _(result).must_answer "[101, 202, 303]\n[11, 11, 21, 21]\n"
  end

  it "numbered params work through a real escaping proc" do
    result = ze0(<<~'RUBY')
      class Collector
        def each_num(a, b)
          yield a
          yield b
        end
      end
      Collector.new.each_num(5, 6) { puts _1 * 2 }
    RUBY

    _(result).must_answer "10\n12\n"
  end

  it "poly map empty block" do
    result = ze0(<<~'RUBY')
      p({1 => [2]}.map { |k, g| g.map {} })

      box = [[2, 3]]
      p(box.map { |g| g.map {} })
      p(box.map { |g| g.map { |x| } })

      nested = [["a"], ["b", "c"]]
      p(nested.map { |g| g.map {} })
      p(nested.map { |g| g.map { |s| s.upcase } })
    RUBY

    _(result).must_answer <<~'OUT'
      [[nil]]
      [[nil, nil]]
      [[nil, nil]]
      [[nil], [nil, nil]]
      [["A"], ["B", "C"]]
    OUT
  end

  it "proc as block arg" do
    result = ze0(<<~'RUBY')
      def run001(&b001); b001.call(3); end
      tri001 = ->(x) { x * 3 }
      p run001(&tri001)

      def run002(&b002); b002.call(3); end
      pr002 = proc { |x| x * 3 }
      p run002(&pr002)

      def sq003(n) = n * n
      def run003(&b003); b003.call(3); end
      p run003(&method(:sq003))

      def run004(&b004); b004.call(3); end
      p run004(&->(x) { x * 3 })

      def run005; yield 3; end
      tri005 = ->(x) { x * 3 }
      p run005(&tri005)

      def twice(&b); [b.call(1), b.call(2)]; end
      p twice(&->(x) { x + 10 })

      def each_of(a, &b); a.each { |x| b.call(x) }; end
      out = []
      each_of([1, 2, 3], &->(x) { out << x * 2 })
      p out
    RUBY

    _(result).must_answer <<~'OUT'
      9
      9
      9
      9
      9
      [11, 12]
      [2, 4, 6]
    OUT
  end

  it "proc source location" do
    result = ze0(<<~'RUBY')
      # Proc#source_location returns [file, line] for a proc literal. Assert the
      # structure and types (the file path is invocation-dependent, and the exact
      # line requires the line map, which the test harness disables). Regression #2649.
      loc = ->(x) { x }.source_location
      p loc.class
      p loc.length
      p loc[0].class
      p loc[1].class
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      2
      String
      Integer
    OUT
  end

  it "proc source location var" do
    result = ze0(<<~'RUBY')
      # Proc#source_location resolves through a local whose sole write is a proc
      # literal (#2720). --no-line-map zeroes lines, so assert structure only.
      a = ->(x) { x }
      p a.source_location.is_a?(Array)
      p a.source_location.length
      b = proc { 1 }
      p b.source_location.is_a?(Array)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      2
      true
    OUT
  end

  it "runs inside the source" do
    result = ze0(<<~'RUBY')
      src = "[3,1,2].sort.map { |x| x * x }"
      p eval(src)
    RUBY

    _(result).must_answer "[1, 4, 9]\n"
  end

  it "singleton class object yields inside class shift obj" do
    result = ze0(<<~'RUBY')
      obj = Object.new
      class << obj
        def each_pair
          yield 1
          yield 2
          block_given? ? "done" : "noblock"
        end
      end
      collected = []
      r = obj.each_pair { |n| collected << n }
      p collected
      puts r
    RUBY

    _(result).must_answer "[1, 2]\ndone\n"
  end

  it "splat map lambda into rest" do
    result = ze0(<<~'RUBY')
      # Splatting an inline map-of-lambdas into a *args method whose vararg is
      # captured by a returned closure (#3242): the rest-consumed splat is not
      # hoisted as a normal arg (ill-typed dead temp + double evaluation), and a
      # lambda that is a block's tail value escapes (poly params via the boxed ABI).
      def alt(*parsers)
        ->(s) { parsers.map { |pr| pr.call(s) } }
      end
      g = alt(*(0..2).map { |d| ->(s) { s } })
      p g.call("5")
      ps = (0..2).map { |d| ->(s) { s } }
      h = alt(*ps)
      p h.call("7")
    RUBY

    _(result).must_answer <<~'OUT'
      ["5", "5", "5"]
      ["7", "7", "7"]
    OUT
  end

  it "top level def self singletons can call each other and yield" do
    result = ze0(<<~'RUBY')
      def self.outer
        "o:#{inner { 1 }}"
      end
      def self.inner
        yield + 41
      end
      puts outer
    RUBY

    _(result).must_answer "o:42\n"
  end

  it "yield inside a nested block literal drives the enclosing methods block" do
    result = ze0(<<~'RUBY')
      # `yield`/`block_given?` lexically inside a block literal refers to the
      # ENCLOSING METHOD's own block (a block has no implicit block of its
      # own): `analyze::scan_bare_block_use` counts it, so the method gets its
      # `__blk` parameter, and the emitted block captures it. Oracle-verified.

      class Foo
        def helper(x)
          yield x
        end
        def bar
          helper(1) { yield }
        end
        def baz
          [1, 2].map { |v| yield v }
        end
        def has_block
          [1].each { return block_given? }
        end
      end
      p(Foo.new.bar { "from-outer" })
      p(Foo.new.baz { |v| v * 10 })
      p Foo.new.has_block
      p(Foo.new.has_block {})
    RUBY

    _(result).must_answer <<~'OUT'
      "from-outer"
      [10, 20]
      false
      true
    OUT
  end
end
