# frozen_string_literal: true

require "spec_helper"

describe "Struct: frozen literals" do
  it "anonymous data define mints a native immutable class" do
    result = zr(<<~'RUBY')
      # `Data.define` outside a constant assignment mints a native immutable data
      # class -- keyword construction, `with`, frozen, byte-exact `inspect`.

      d = Data.define(:x, :y)
      pt = d.new(x: 1, y: 2)
      p pt
      p pt.x
      p pt.to_h
      p pt.with(x: 9)
      p pt.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      #<data x=1, y=2>
      1
      {x: 1, y: 2}
      #<data x=9, y=2>
      true
    OUT
  end

  it "anonymous struct runtime" do
    result = zr(<<~'RUBY')
      # A `Struct.new` / `Data.define` OUTSIDE a constant assignment mints a native
      # class at runtime (Batch E), so a struct can be an anonymous local, used
      # inline, or built in a loop -- not only `Name = Struct.new(...)`. The constant
      # form is still compile-time synthesized (so `super`/subclassing keep working).

      # anonymous struct assigned to a local
      pair = Struct.new(:a, :b)
      o = pair.new(1, 2)
      p o
      p o.a
      p o.to_a
      p o.members
      o.a = 10
      p o.a

      # Enumerable, and a class-body method block
      point = Struct.new(:x, :y) do
        def dist
          Math.sqrt(x**2 + y**2)
        end
      end
      pt = point.new(3, 4)
      p pt.dist
      p pt.map { |v| v * 2 }
      p pt.select(&:even?)

      # used inline
      p Struct.new(:n).new(42).n

      # an anonymous Data class: keyword construction, immutable, `with`
      coord = Data.define(:lat, :lng)
      c = coord.new(lat: 51, lng: 0)
      p c
      p c.lat
      p c.to_h
      p c.with(lng: 13)
      p c.frozen?

      # a struct built per row in a loop
      rows = [[1, 2], [3, 4]].map do |a, b|
        Struct.new(:a, :b).new(a, b)
      end
      rows.each { |r| p r.to_a }
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct a=1, b=2>
      1
      [1, 2]
      [:a, :b]
      10
      5.0
      [6, 8]
      [4]
      42
      #<data lat=51, lng=0>
      51
      {lat: 51, lng: 0}
      #<data lat=51, lng=13>
      true
      [1, 2]
      [3, 4]
    OUT
  end

  it "data constructs positionally or by keyword" do
    result = zr(<<~'RUBY')
      Point = Data.define(:x, :y)
      a = Point.new(1, 2)
      b = Point.new(x: 1, y: 2)
      p [a.x, a.y]
      p(a == b)
      p a.frozen?
      # The `rescue` modifier needs its own parens inside a call's arguments
      # (a bare `p(x rescue y)` is a SyntaxError in ruby 4.0.6 too).
      p((Point.new(1) rescue $!.class))
      p((Point.new(x: 1, y: 2, z: 3) rescue $!.class))
      p((a.with(z: 9) rescue $!.class))
      p a.with(y: 5).to_h
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      true
      ArgumentError
      ArgumentError
      ArgumentError
      {x: 1, y: 5}
    OUT
  end

  it "data dup clone frozen" do
    result = zr(<<~'RUBY')
      # A Data instance is frozen by construction and stays so through every copy:
      # dup and clone(freeze: false) both return a frozen value in CRuby (#2716).
      # Struct copies keep the ordinary rules (dup never freezes).
      P = Data.define(:x, :y)
      a = P.new(1, 2)
      p(a.dup.frozen?)
      p(a.clone(freeze: false).frozen?)
      p(a.clone.frozen?)
      p(a.dup.x)
      S = Struct.new(:v)
      s = S.new(5)
      p(s.dup.frozen?)
      p(s.clone.frozen?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      1
      false
      false
    OUT
  end

  it "data freezes inside its own initialize" do
    result = zr(<<~'RUBY')
      # A `Data` instance freezes inside `Data#initialize`, which is where CRuby
      # freezes it (`rb_data_initialize_m`) -- not after the constructor returns.
      # The difference is visible from a subclass:
      #
      #   * one that writes an ivar AFTER `super` must raise `FrozenError`;
      #   * one that never calls `super` leaves the instance MUTABLE, because
      #     nothing froze it.
      #
      # zeo froze after dispatching `initialize`, so the first shape silently
      # succeeded and the second was frozen when ruby leaves it open.
      #
      # The message that raise carries needed one more fix. `check_frozen` renders
      # the receiver through the runtime's own infallible inspect, which had no arm
      # for a struct or data instance and fell through to the address form -- so the
      # message read `#<D2:0x...>` where CRuby says `#<data D2 m=1>`. The Ruby-level
      # `inspect` was already right; it is a table row, which `call_user_method`
      # cannot see.

      D = Data.define(:m)

      class AfterSuper < D
        def initialize(**kw)
          super
          @z = 1
        end
      end
      begin
        AfterSuper.new(m: 1)
      rescue => e
        p e.class
        p e.message
      end

      class NoSuper < D
        def initialize(**kw)
          @z = 1
        end
      end
      o = NoSuper.new(m: 1)
      p [o.frozen?, o.instance_variables, o.m]

      class BeforeSuper < D
        def initialize(**kw)
          @z = 1
          super
        end
      end
      b = BeforeSuper.new(m: 2)
      p [b.m, b.instance_variables, b.frozen?]

      # The plain form is frozen, as it always was.
      p D.new(m: 3).frozen?
      p D.new(m: 3).inspect

      # A Struct is NOT frozen by its constructor, which is the contrast Data draws.
      S = Struct.new(:a)
      class SafterSuper < S
        def initialize(*args)
          super
          @z = 1
        end
      end
      s = SafterSuper.new(1)
      p [s.a, s.instance_variables, s.frozen?]
      p S.new(1).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      "can't modify frozen AfterSuper: #<data AfterSuper m=1>"
      [false, [:@z], nil]
      [2, [:@z], true]
      true
      "#<data D m=3>"
      [1, [:@z], false]
      "#<struct S a=1>"
    OUT
  end

  it "data instance frozen" do
    result = zr(<<~'RUBY')
      P = Data.define(:x, :y)
      p(P.new(1, 2).frozen?)
      a = P.new(1, 2); p(a.frozen?)
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "data new with no arguments passes no keywords" do
    result = zr(<<~'RUBY')
      # `Data.new` zips its positionals into a hash and hands it to `initialize`
      # AS KEYWORDS (`rb_class_new_instance_kw` + `RB_PASS_KEYWORDS`), so a user
      # `initialize(max: 256, live: [])` binds them by name -- and, as with any
      # `**{}`, an empty one is no argument at all, which is what lets that
      # override's defaults apply to a bare `P.new`. zeo handed it one positional
      # Hash: "wrong number of arguments (given 1, expected 0)".

      P = Data.define(:max, :live)
      class P
        DEFAULT_MAX = 256
        def initialize(max: DEFAULT_MAX, live: [])
          super(max: max, live: live.freeze)
        end
      end
      p P.new(max: 320)
      p P.new
      p P.new(max: 1, live: [2]).live.frozen?
      p P.new(320)
      p P.new(320, [1])

      # The default `initialize` still refuses a short call by keyword name, and a
      # memberless Data takes the bare call.
      D = Data.define(:a)
      begin
        D.new
      rescue ArgumentError => e
        p e.message
      end
      p D.new(**{ a: 1 })
      E = Data.define
      p E.new
      p E.new(**{})
    RUBY

    _(result).must_answer <<~'OUT'
      #<data P max=320, live=[]>
      #<data P max=256, live=[]>
      true
      #<data P max=320, live=[]>
      #<data P max=320, live=[1]>
      "missing keyword: :a"
      #<data D a=1>
      #<data E>
      #<data E>
    OUT
  end

  it "data positional construction" do
    result = zr(<<~'RUBY')
      # Data.define values construct positionally or by keyword, are frozen, and
      # validate unknown/missing members.
      Point = Data.define(:x, :y)

      pos = Point.new(1, 2)
      kw  = Point.new(x: 1, y: 2)
      p [pos.x, pos.y]
      p (pos == kw)
      p pos.frozen?
      p pos.to_h
      p pos.with(y: 9).to_h

      p (Point.new(1) rescue $!.class)
      p (Point.new(x: 1) rescue $!.class)
      p (Point.new(x: 1, y: 2, z: 3) rescue $!.class)
      p (pos.with(z: 9) rescue $!.class)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      true
      {x: 1, y: 2}
      {x: 1, y: 9}
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
    OUT
  end

  it "a literal member list compiles to a real class, and the whole protocol still answers" do
    result = zr(<<~'RUBY')
      # A `NAME = Struct.new(:a, :b)` with a literal member list compiles to a real
      # class whose members are slots rather than an overlay minted at runtime. What
      # the program can observe must not change, so this pins the whole protocol
      # against the oracle -- including the parts that are NOT ivars.

      Point = Struct.new(:x, :y)
      pt = Point.new(1, 2)

      p pt.x, pt.y, pt.to_a, pt.members, Point.members, pt.size, pt.length
      p pt == Point.new(1, 2), pt == Point.new(1, 3), pt.eql?(Point.new(1, 2))
      p pt.hash == Point.new(1, 2).hash

      # Members are storage, but they are not instance variables.
      p pt.instance_variables
      p pt.instance_variable_get(:@x)
      p pt.instance_variable_defined?(:@x)

      # An ivar invented on top of the members is a real, separate one.
      pt.instance_variable_set(:@note, "hi")
      p pt.instance_variables, pt.instance_variable_get(:@note), pt.x

      p pt[0], pt[1], pt[-1], pt[:x], pt["y"]
      pt[:x] = 10
      pt.y = 20
      p pt.to_a, pt.to_h, pt.inspect, pt.to_s

      # Short and empty construction nil-fill rather than raise.
      p Point.new(1).to_a, Point.new.to_a

      begin
        Point.new(1, 2, 3)
      rescue ArgumentError => e
        p e.class
      end
      begin
        pt[9]
      rescue IndexError => e
        p e.class
      end
      begin
        pt[:nope]
      rescue NameError => e
        p e.class
      end

      pt.each { |v| print v, " " }
      puts
      pt.each_pair { |k, v| print k, "=", v, " " }
      puts

      p pt.dig(0), pt.dig(:y), pt.values_at(0, 1), pt.values

      case pt
      in [a, b]
        p [a, b]
      end
      case pt
      in {x:, y:}
        p [x, y]
      end

      p Marshal.load(Marshal.dump(Point.new(3, 4))).to_a
      p pt.is_a?(Struct), Point.ancestors.include?(Struct), Point.superclass
      p pt.dup.to_a, pt.clone.to_a
      p Point.new(1, 2).frozen?

      # Enumerable arrives through Struct, and so does `select`/`map`.
      p pt.map { |v| v * 2 }
      p pt.select { |v| v > 15 }
      p pt.include?(10)

      # A subclass of a compiled struct inherits the members.
      class Point3 < Point
        def norm = x + y
      end
      q = Point3.new(4, 5)
      p q.to_a, q.members, q.norm, q.x, q.is_a?(Point)

      # A user method on the struct body itself, and a member reassigned inside it.
      Boxed = Struct.new(:v)
      class Boxed
        def bump
          self.v = v + 1
          self
        end
      end
      p Boxed.new(1).bump.v

      # Frozen members raise on write, as any frozen object does.
      f = Point.new(1, 2).freeze
      begin
        f.x = 3
      rescue FrozenError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      [1, 2]
      [:x, :y]
      [:x, :y]
      2
      2
      true
      false
      true
      true
      []
      nil
      false
      [:@note]
      "hi"
      1
      1
      2
      2
      1
      2
      [10, 20]
      {x: 10, y: 20}
      "#<struct Point x=10, y=20>"
      "#<struct Point x=10, y=20>"
      [1, nil]
      [nil, nil]
      ArgumentError
      IndexError
      NameError
      10 20 
      x=10 y=20 
      10
      20
      [10, 20]
      [10, 20]
      [10, 20]
      [10, 20]
      [3, 4]
      true
      true
      Struct
      [10, 20]
      [10, 20]
      false
      [20, 40]
      [20]
      true
      [4, 5]
      [:x, :y]
      9
      4
      true
      2
      FrozenError
    OUT
  end
end
