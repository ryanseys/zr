# frozen_string_literal: true

require "spec_helper"

describe "Object: blocks and yields" do
  it "block auto splat" do
    result = ze0(<<~'RUBY')
      # A non-lambda block yielded EXACTLY ONE Array argument spreads it across its
      # positional parameters -- the rule that makes `Hash#each { |k, v| }` and
      # `[[1, 2]].each { |a, b| }` read naturally. Whether a given block splats at
      # all is decided by its own parameter shape (CRuby's `has_lead &&
      # !ambiguous_param0`), so every shape below is covered.

      def one(v)
        yield v
      end

      # No leading required parameter -> never splats.
      p(one([1, 2]) { |*a| a })
      p(one([1, 2]) { |*a, **k| [a, k] })

      # Exactly ONE positional slot -> the one-parameter case is exempt.
      p(one([1, 2]) { |a| a })
      p(one([1, 2]) { |a, **k| [a, k] })

      # A lead parameter plus any second positional slot -> splats.
      p(one([1, 2]) { |a, b| [a, b] })
      p(one([1, 2]) { |a, b, **k| [a, b, k] })
      p(one([1, 2]) { |a, *b| [a, b] })
      p(one([1, 2]) { |a, b = 5| [a, b] })
      p(one([1, 2, 3]) { |a, *b, c| [a, b, c] })

      # More parameters than elements nil-fills; fewer drops the extras.
      p(one([1]) { |a, b| [a, b] })
      p(one([1, 2, 3]) { |a, b| [a, b] })

      # Two yielded values are already separate arguments -- no splat involved.
      def two(a, b)
        yield a, b
      end
      p(two(1, 2) { |a, b| [a, b] })
      p(two([1, 2], 3) { |a, b| [a, b] })

      # The idioms this exists for.
      [[1, 2], [3, 4]].each { |a, b| p [a, b] }
      p({ a: 1, b: 2 }.map { |k, v| "#{k}=#{v}" })
      p [[1, 2], [3, 4]].map { |a, b| a + b }
      p [[1, 2], [3, 4]].to_h { |a, b| [b, a] }

      # A single-element array still splats (the element binds, the rest nil-fill).
      p(one([9]) { |a, b| [a, b] })

      # A lambda is STRICT: no auto-splat, and a wrong count raises.
      strict = ->(a, b) { [a, b] }
      p strict.call(1, 2)
      begin
        strict.call([1, 2])
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end

      # The trailing-Hash-to-keywords split happens BEFORE the splat, so a Hash
      # element lands in a positional slot rather than the keyword rest.
      p(one([1, { x: 9 }]) { |a, b, **k| [a, b, k] })

      # Keywords yielded alongside a value are not part of the splat decision.
      def with_kw(v)
        yield v, x: 9, y: 8
      end
      p(with_kw(1) { |v, x:, **k| [v, x, k] })

      # A user object defining to_ary coerces through it, like CRuby's
      # rb_check_array_type.
      class Pair
        def initialize(a, b)
          @a = a
          @b = b
        end

        def to_ary
          [@a, @b]
        end
      end
      p(one(Pair.new(1, 2)) { |a, b| [a, b] })
      p(one(Pair.new(1, 2)) { |a| a.class })

      # An object WITHOUT to_ary binds as a single argument.
      class Opaque; end
      p(one(Opaque.new) { |a, b| [a.class, b] })
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2]]
      [[[1, 2]], {}]
      [1, 2]
      [[1, 2], {}]
      [1, 2]
      [1, 2, {}]
      [1, [2]]
      [1, 2]
      [1, [2], 3]
      [1, nil]
      [1, 2]
      [1, 2]
      [[1, 2], 3]
      [1, 2]
      [3, 4]
      ["a=1", "b=2"]
      [3, 7]
      {2 => 1, 4 => 3}
      [9, nil]
      [1, 2]
      ArgumentError: wrong number of arguments (given 1, expected 2)
      [1, {x: 9}, {}]
      [1, 9, {y: 8}]
      [1, 2]
      Pair
      [Opaque, nil]
    OUT
  end

  it "block auto splat follows the ambiguous param0 rule" do
    result = ze0(<<~'RUBY')
      # A lone Array argument spreads across a block's positional params -- but a
      # block with exactly ONE plain param receives it whole (`ambiguous_param0`,
      # the `each { |pair| }` idiom), and so does a lone optional. Oracle-derived.

      def one(x) = yield x
      one([1, 2]) { |a| p a }
      one([1, 2]) { |a = 9| p a }
      one([1, 2]) { |*a| p a }
      one([1, 2]) { |a, **k| p a }
      one([1, 2]) { |a, b| p [a, b] }
      one([1, 2]) { |a, *b| p [a, b] }
      one([1, 2]) { |*a, b| p [a, b] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [[1, 2]]
      [1, 2]
      [1, 2]
      [1, [2]]
      [[1], 2]
    OUT
  end

  it "block auto splat triggers on more than one optional" do
    result = ze0(<<~'RUBY')
      # More than one OPTIONAL param auto-splats even with no required param at
      # all, while a single optional plus a rest does not. This pair is what rules
      # out the tempting "count the positional slots" formulation of the rule.

      def one(x) = yield x
      one([1, 2]) { |a = 5, b = 4| p [a, b] }
      one([1, 2]) { |a = 5, *b| p [a, b] }
      one([1, 2]) { |a = 5, b = 4, *c| p [a, b, c] }
      one([1, 2]) { |a = 5, *b, c| p [a, b, c] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [[1, 2], []]
      [1, 2, []]
      [1, [], 2]
    OUT
  end

  it "escaping block can mutate an ivar via self capture" do
    result = ze0(<<~'RUBY')
      # Exercises the self:Rc<Self> migration + self-capture path: the block
      # is written inside `Box#run` (so `self`/`@sum` are in scope there) and
      # passed to a call on an EXPLICIT other receiver (`c`, a Collector
      # constructed directly as a LOCAL, not taken as a method parameter --
      # method params are always statically `Poly`, a separate
      # pre-existing gap; a `New`-assigned local's class IS statically known,
      # so this routes around that while still exercising real self-capture.
      # Implicit-self calls to a user method are ALSO a separate, unrelated,
      # still-unsupported gap, avoided here the same way).

      class Collector
        def each_num(a, b, c)
          yield a
          yield b
          yield c
        end
      end
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
    RUBY

    _(result).must_answer "6\n"
  end

  it "for iterates any object answering each" do
    result = ze0(<<~'RUBY')
      # Ruby's `for` performs NO type dispatch: `for x in obj` compiles to
      # `obj.each { |x| ... }` (compile_iter, compile.c:8548). So a user class
      # iterates, a pair-yielding each destructures, the loop variable outlives
      # the loop (`for` introduces no scope), and an object with no `each`
      # fails at RUNTIME rather than failing the compile.

      class Nums
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each; @xs.each { |x| yield x }; end
      end
      class Pairs
        include Enumerable
        def each; yield [1, :a]; yield [2, :b]; end
      end
      total = 0
      for x in Nums.new(1, 2, 3, 4)
        total += x
      end
      p total
      pairs = []
      for k, v in Pairs.new
        pairs << "#{k}:#{v}"
      end
      p pairs
      for survivor in [10, 20, 30]
      end
      p survivor
      begin
        for z in 5; end
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      ["1:a", "2:b"]
      30
      undefined method 'each' for an instance of Integer
    OUT
  end

  it "forwarded block ivar" do
    result = ze0(<<~'RUBY')
      class Holder
        def store(&b); @proc = b; end
        def run; @proc.call; end
      end
      def forward(h, &b); h.store(&b); end
      h = Holder.new
      n = 0
      forward(h) { n += 1 }
      h.run
      puts "n=#{n}"
      h.run
      puts "n=#{n}"

      class Registry
        def initialize; @cbs = []; end
        def on(&b); @cbs << b; end
        def fire; @cbs.each { |c| c.call }; end
      end
      def register(r, &b); r.on(&b); end
      r = Registry.new
      count = 0
      register(r) { count += 2 }
      register(r) { count += 3 }
      r.fire
      p count
    RUBY

    _(result).must_answer <<~'OUT'
      n=1
      n=2
      5
    OUT
  end

  it "lambda never auto splats" do
    result = ze0(<<~'RUBY')
      # A lambda is strict: it never auto-splats, whatever its param shape.

      p(->(a) { a }.call([1, 2]))
      p(->(a, b) { [a, b] }.call(1, 2))
    RUBY

    _(result).must_answer "[1, 2]\n[1, 2]\n"
  end

  it "lambda return and break terminate only the lambda itself" do
    result = ze0(<<~'RUBY')
      # Real Ruby: unlike an ordinary Proc/block, `return`/`break` inside a
      # lambda act like a method boundary -- they terminate just the lambda
      # call, never the enclosing method.

      class Runner
        def return_test
          f = -> {
            return 10
            20
          }
          puts f.call
          "after"
        end

        def break_test
          g = -> {
            break 99
            100
          }
          puts g.call
          "after"
        end
      end

      r = Runner.new
      puts r.return_test
      puts r.break_test
    RUBY

    _(result).must_answer <<~'OUT'
      10
      after
      99
      after
    OUT
  end

  it "method owner composition equality and curry" do
    result = ze0(<<~'RUBY')
      class Animal
        def speak(sound) = "#{sound}!"
      end
      class Dog < Animal
      end
      d = Dog.new
      m = d.method(:speak)
      p m.owner
      p m.original_name
      shout = ->(s) { s.upcase }
      p (m >> shout).call("woof")
      p (m << shout).call("woof")
      p (1.method(:+) >> ->(n) { n * 2 }).call(10)
      p d.method(:speak) == d.method(:speak)
      p Dog.new.method(:speak) == Dog.new.method(:speak)
      p m.hash == d.method(:speak).hash
      class Adder
        def add3(a, b, c) = a + b + c
      end
      p Adder.new.method(:add3).curry[1][2][3]
      um = Dog.instance_method(:speak)
      p um.owner
      p um.bind(Dog.new).call("bark")
    RUBY

    _(result).must_answer <<~'OUT'
      Animal
      :speak
      "WOOF!"
      "WOOF!"
      22
      true
      false
      true
      6
      Animal
      "bark!"
    OUT
  end

  it "a value-typed object used as a condition is truthy, and its side effects still run" do
    result = ze0(<<~'RUBY')
      # Regression test for issue #20: a value-typed object used directly
      # as a condition must be treated as truthy. C cannot use a struct as
      # a scalar in `if (...)`, so the codegen wraps value-type objects
      # with `((expr), 1)` to evaluate side effects then yield 1.

      class Value
        def initialize(x)
          @x = x
        end
      end

      # Direct constructor in postfix-if predicate
      puts "1 ok" if Value.new(0)

      # Value-typed local in if-statement
      v = Value.new(1)
      puts "2 ok" if v

      # Inside a loop
      i = 0
      while i < 1
        puts "3 ok" if Value.new(0)
        i += 1
      end

      # Ternary if-expression
      puts (Value.new(2) ? "4 yes" : "4 no")

      # unless: value-type is always truthy, so the body must be skipped
      puts "5 not run" unless Value.new(3)
      puts "5 done"
    RUBY

    _(result).must_answer <<~'OUT'
      1 ok
      2 ok
      3 ok
      4 yes
      5 done
    OUT
  end

  it "singleton method block" do
    result = ze0(<<~'RUBY')
      # A runtime-installed singleton method threads its call-site block, so
      # yield / block_given? / &blk all work inside it (Batch G).

      obj = Object.new

      def obj.greet
        yield "world"
      end
      puts obj.greet { |x| "hello #{x}" }

      def obj.wrap(&blk)
        blk.nil? ? "no block" : "[#{blk.call}]"
      end
      puts obj.wrap { "boxed" }
      puts obj.wrap

      class << obj
        def each_pair
          yield 1
          yield 2
          block_given? ? "done" : "noblock"
        end
      end
      seen = []
      puts obj.each_pair { |n| seen << n }
      p seen

      # A `yield` reached with no block is a rescuable LocalJumpError, not a crash.
      def obj.demands_block
        yield
      end
      begin
        obj.demands_block
      rescue LocalJumpError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hello world
      [boxed]
      no block
      done
      [1, 2]
      LocalJumpError: no block given (yield)
    OUT
  end

  it "singleton method inner block yields to the methods own block" do
    result = ze0(<<~'RUBY')
      # Inside a singleton method, an ORDINARY block's `yield` targets the
      # method's own (call-site) block -- the lexical-clone path composing over
      # the method-body lambda's call-site `__blk`.

      obj = Object.new
      def obj.sum_pairs
        total = 0
        [1, 2, 3].each { |n| total += yield(n) }
        total
      end
      p obj.sum_pairs { |n| n * 10 }
    RUBY

    _(result).must_answer "60\n"
  end

  it "singleton method object binds a named block param" do
    result = ze0(<<~'RUBY')
      # A `&blk` param on a per-object singleton binds to the method's call-site
      # block (nil when none is passed), not the unconditional nil it used to.

      obj = Object.new
      def obj.wrap(&blk)
        blk.nil? ? "no block" : blk.call(41) + 1
      end
      puts obj.wrap { |n| n }
      puts obj.wrap
    RUBY

    _(result).must_answer "42\nno block\n"
  end

  it "singleton method yields params and multiple values" do
    result = ze0(<<~'RUBY')
      obj = Object.new
      def obj.combine(a, b)
        yield a, b, a + b
      end
      obj.combine(2, 3) { |x, y, s| puts "#{x} #{y} #{s}" }
    RUBY

    _(result).must_answer "2 3 5\n"
  end

  it "tap then tail value" do
    result = ze0(<<~'RUBY')
      # tap / then / yield_self at method-tail position carry their value out as
      # the return: tap returns the (mutated) receiver, then returns the block's
      # value. Struct member writes inside the tap block mutate the same instance.
      Point = Struct.new(:x, :y)

      def build = Point.new(1, 2).tap { |pt| pt.x = 9 }
      p build.x
      p build.y

      def shifted(p0) = p0.tap { |pt| pt.y = pt.y + 10 }
      q = Point.new(3, 4)
      p shifted(q).y
      p q.y

      def doubled(n) = n.then { |v| v * 2 }
      p doubled(21)

      def renamed(s) = s.yield_self { |v| v + "!" }
      p renamed("hi")

      def chained = Point.new(5, 6).tap { |pt| pt.x = 7 }.tap { |pt| pt.y = 8 }
      r = chained
      p [r.x, r.y]

      mid = Point.new(0, 0).tap { |pt| pt.x = 4 }
      p mid.x
    RUBY

    _(result).must_answer <<~'OUT'
      9
      2
      14
      14
      42
      "hi!"
      [7, 8]
      4
    OUT
  end

  it "then without block" do
    result = ze0(<<~'RUBY')
      # `Kernel#then` / `yield_self` without a block is an Enumerator over one
      # element -- the receiver -- and it knows its own SIZE.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # `then` / `yield_self` given no block is an Enumerator over exactly one
      # element, the receiver -- spinel refused the call outright (#4028):
      #
      #   undefined method 'then' for an instance of Array (NoMethodError)
      #
      # and a `then` whose block body is EMPTY declared its result slot `void`,
      # because the desugared `then { nil }` types as nil, which has no C slot.

      [].then{}
      p([].then{})
      p(5.then{})
      p("x".then{})
      p({a: 1}.then{})

      e = 5.then
      p e
      p e.class
      p e.to_a
      p e.next
      p e.size
      p 5.yield_self.to_a

      # the receiver is carried whatever it is -- a nil one is a real source, not the
      # absence of one, which #inspect must not read as "fall back to the items"
      p nil.then
      p nil.then.to_a
      p :sym.then.next
      p 1.5.then.to_a
      p((1..3).then.to_a)
      p({a: 1}.then.to_a)
      p [1, 2].then.to_a
      p "s".yield_self.to_a

      class Holder
        def initialize(v) = @v = v
        def v = @v
      end
      p Holder.new(3).then.next.v

      # reached through a poly slot, where the receiver's class is a run-time question
      p [1, [2, "x"]][1].then.to_a
      p [1, [2, "x"]][0].then.next

      # and it still composes with the enumerator surface
      p 7.then.with_index.to_a
      p [4].then.first
      puts "OK"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      #<Enumerator: 5:then>
      Enumerator
      [5]
      5
      1
      [5]
      #<Enumerator: nil:then>
      [nil]
      :sym
      [1.5]
      [1..3]
      [{a: 1}]
      [[1, 2]]
      ["s"]
      3
      [[2, "x"]]
      1
      [[7, 0]]
      [4]
      OK
    OUT
  end

  it "top level def self defines a singleton method on main" do
    result = ze0(<<~'RUBY')
      # A top-level `def self.name` is a SINGLETON method on `main` --
      # callable via implicit self at the top level, but (CRuby's asymmetry with
      # a plain top-level `def`, a private Object instance method) NOT from
      # inside another object's method, where self isn't `main`.

      def self.only_main; "main-only"; end
      def self.wrap; "[#{yield}]"; end
      puts only_main
      puts wrap { "b" }
      class Widget
        def try; only_main rescue "not-visible"; end
      end
      puts Widget.new.try
    RUBY

    _(result).must_answer <<~'OUT'
      main-only
      [b]
      not-visible
    OUT
  end

  it "trailing comma param is an anonymous rest" do
    result = ze0(<<~'RUBY')
      # A trailing comma (`|a, |`) means "this block takes more than one param",
      # which turns auto-splat on and then discards everything past the named
      # ones -- exactly an anonymous rest, which is how it lowers.

      def one(x) = yield x
      one([1, 2]) { |a,| p a }
      one([1, 2, 3]) { |a, b,| p [a, b] }
    RUBY

    _(result).must_answer "1\n[1, 2]\n"
  end

  it "yield tail tap value" do
    result = ze0(<<~'RUBY')
      # The value of a spliced block is its tail, and a tail CALL whose statement
      # form drops that value has to be emitted as an expression: tap answers its
      # receiver, not its block's body, and a receiver-returning iterator on a
      # computed receiver answers the receiver (#4155).
      class Rec
        def hello = "hi"
      end

      module Conn
        def self.transaction
          yield
        end
      end

      p Conn.transaction { Rec.new.tap { |r| r.hello } }.hello
      p Conn.transaction { Rec.new.tap { |r| r } }.hello
      p Conn.transaction { Rec.new }.hello
      p Conn.transaction { 5.then { |n| n * 2 } }
      p Conn.transaction { [3, 1, 2].each { |x| x } }
      p Conn.transaction { [1, 2].map { |x| x + 1 } }
      p Conn.transaction { [3, 1, 2].dup.each { |x| x } }
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      "hi"
      "hi"
      10
      [3, 1, 2]
      [2, 3]
      [3, 1, 2]
    OUT
  end

  it "the type questions and case arms answer by the class alone until a class defines one" do
    result = ze0(<<~'RUBY')
      # `is_a?`, `kind_of?` and `instance_of?` are Kernel's for every
      # object, so a site answers them from the classes alone with no
      # cell (GATE_IS_A, GATE_INSTANCE_OF); a definition of the name --
      # by def, alias, define_method or a singleton -- closes the gate for
      # every site, and a BasicObject has no is_a? to answer. `Mod ===
      # obj` answers from the classes where the arm's cell holds
      # Module's === (SHAPE_MOD_EQQ), and calls whatever else it holds --
      # a `===` on a singleton, on Module, on Object.
      class Num; end
      class Sub < Num; end
      module Mod; end
      class WithMod; include Mod; end
      n = Num.new; s = Sub.new; w = WithMod.new
      p n.is_a?(Num), s.is_a?(Num), n.is_a?(Sub), s.kind_of?(Object), n.is_a?(Mod), w.is_a?(Mod), w.kind_of?(Comparable)
      p n.instance_of?(Num), s.instance_of?(Num), s.instance_of?(Sub), w.instance_of?(Mod)
      p nil.is_a?(NilClass), true.is_a?(TrueClass), 1.is_a?(Integer), 1.is_a?(Comparable), :s.is_a?(Symbol), 2.5.is_a?(Float), 1.instance_of?(Integer)
      begin
        n.is_a?(3)
      rescue TypeError => e
        puts e.message
      end
      begin
        BasicObject.new.is_a?(Object)
      rescue NoMethodError => e
        puts e.message
      end
      class Bare < BasicObject
        def is_a?(k) = :bare
      end
      p Bare.new.is_a?(Object)
      def probe(x) = x.is_a?(Num)
      p probe(n), probe(s), probe(1)
      class Sub
        def is_a?(k) = :redefined
      end
      p probe(s), probe(n), s.kind_of?(Num), n.kind_of?(Num)
      class Num
        alias kind_of? is_a?
      end
      p n.kind_of?(Num)
      o = Object.new
      def o.instance_of?(k) = :single
      p o.instance_of?(Object), Object.new.instance_of?(Object)
      class Late; end
      l = Late.new
      def late_probe(x) = x.instance_of?(Late)
      p late_probe(l)
      Late.define_method(:instance_of?) { |k| :defined }
      p late_probe(l)
      # `case` arms ask Module#===
      def classify(x)
        case x
        when Num then :num
        when Sub then :sub
        when Mod then :mod
        when Integer then :int
        when NilClass then :nil
        else :other
        end
      end
      p classify(n), classify(s), classify(w), classify(1), classify(nil), classify("s")
      class Late2; end
      def late_case(x) = (case x when Late2 then :late else :no end)
      p late_case(Late2.new), late_case(1)
      def Late2.===(o) = :singleton
      p late_case(Late2.new), late_case(1), classify(n)
      class Module
        def ===(o) = :module_eqq
      end
      p classify(n), classify(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
      false
      true
      false
      true
      false
      true
      true
      true
      true
      true
      true
      true
      class or module required
      undefined method 'is_a?' for an instance of BasicObject
      :bare
      true
      true
      false
      :redefined
      true
      true
      true
      true
      :single
      true
      true
      :defined
      :num
      :num
      :mod
      :int
      :nil
      :other
      :late
      :no
      :late
      :late
      :num
      :num
      :num
    OUT
  end
  it "a ranked class answers is_a?, a case arm, nil? and identity equality at the site" do
    result = ze0(<<~'RUBY')
      # A ranked class -- one in Object's family with its rank table built,
      # which every class gets at birth -- answers `is_a?`, a `case` arm and
      # `nil?` at the site from its header and its table, with no call
      # (FL_RANKED, GATE_NIL_P); `==`, `equal?` and `!=` answer by identity
      # where the cell holds BasicObject's (SHAPE_EQ, SHAPE_NE). A module, a
      # BasicObject's class, a class made by Class.allocate, and every
      # definition of one of the names take the road that calls.
      class A; end
      class B < A; end
      class C < B; end
      module M; end
      class D; include M; end
      class Bare < BasicObject; def self.mk = new; end
      a, b, c, d = A.new, B.new, C.new, D.new
      p [a.nil?, nil.nil?, 1.nil?, :s.nil?, 1.5.nil?, "".nil?, true.nil?, (Bare.mk.nil? rescue $!.class)]
      p [b.is_a?(A), a.is_a?(B), c.kind_of?(A), c.is_a?(Object), c.is_a?(BasicObject), c.is_a?(Kernel), d.is_a?(M), a.is_a?(M), 1.is_a?(Integer), 1.is_a?(Comparable), nil.is_a?(NilClass), 1.5.is_a?(Float), 1.is_a?(Float)]
      p [(a.is_a?(1) rescue $!.class), (a.is_a?(nil) rescue $!.class), A.is_a?(Class), A.is_a?(A), a.is_a?(a.singleton_class), (Bare.mk.is_a?(Object) rescue $!.class)]
      def kind(x)
        case x
        when C then :c
        when B then :b
        when A then :a
        when M then :m
        when Integer then :int
        when Symbol then :sym
        when NilClass then :nil
        when Comparable then :cmp
        when BasicObject then :basic
        else :other
        end
      end
      p [a, b, c, d, 1, 1.5, :s, nil, Bare.mk, 2**70].map { |x| kind(x) }
      p [A === a, B === a, M === d, M === a, Class === A, Module === M, BasicObject === Bare.mk, Object === Bare.mk]
      p [a == a, a == b, a != a, a != b, a.equal?(a), a.equal?(b), nil != false, :s == :s, :s != :t, A == A, A != B, "a" == "a", "a" != "b", 1 == 1.0, 1 != 1.0]
      class E; def ==(o) = true; end
      class F; def !=(o) = :ne; end
      class G < A; def nil? = :g; end
      class H; def is_a?(k) = :h; end
      class I; def self.===(o) = :i; end
      p [E.new == E.new, E.new != E.new, E.new.equal?(E.new), F.new != F.new, F.new == F.new, G.new.nil?, a.nil?, nil.nil?, H.new.is_a?(A), a.is_a?(A), (case 1 when I then :yes else :no end), kind(c)]
      s = Class.new(A)
      t = Class.new(s)
      k = Class.allocate
      u = Class.new
      p [t.new.is_a?(A), s === t.new, B === t.new, (k.new rescue $!.class), u.new.is_a?(Object), u === u.new, u.new.nil?]
      n = 0
      i = 0
      while i < 100_000
        n += 1 if kind(i.even? ? b : c) == :b
        n += 1 if b.nil?
        n += 1 if b != c
        n += 1 if c.is_a?(A)
        i += 1
      end
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      [false, true, false, false, false, false, false, NoMethodError]
      [true, false, true, true, true, true, true, false, true, true, true, true, false]
      [TypeError, TypeError, true, false, true, NoMethodError]
      [:a, :b, :c, :m, :int, :cmp, :sym, :nil, :basic, :int]
      [true, false, true, false, true, true, true, false]
      [true, false, false, true, true, false, true, true, true, true, true, true, true, true, false]
      [true, false, false, :ne, false, :g, false, true, :h, true, :yes, :c]
      [true, true, false, TypeError, true, true, false]
      250000
    OUT
  end
end
