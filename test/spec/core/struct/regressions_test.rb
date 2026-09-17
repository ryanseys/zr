# frozen_string_literal: true

require "spec_helper"

describe "Struct: regressions" do
  it "issue 2872" do
    result = ze0(<<~'RUBY')
      Item = Struct.new(:cat, :qty) do
        def value = qty
      end
      items = [Item.new(:a, 1), Item.new(:b, 2), Item.new(:a, 3)]
      items.group_by(&:cat).each { |cat, g| p [cat, g.sum(&:value)] }

      Rec = Struct.new(:name, :amt) do
        def cost = amt
      end
      recs = [Rec.new("x", 1.5), Rec.new("y", 2.5), Rec.new("x", 3.0)]
      by = recs.group_by(&:name)
      by.each { |k, g| p [k, g.sum(0.0, &:cost)] }
      by.each { |k, g| p [k, g.sum { |r| r.cost * 2 }] }

      strs = { p: %w[a b], q: %w[c] }
      strs.each { |k, g| p g.sum("") { |s| s } }
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 4]
      [:b, 2]
      ["x", 4.5]
      ["y", 2.5]
      ["x", 9.0]
      ["y", 5.0]
      "ab"
      "c"
    OUT
  end

  it "issue 2890" do
    result = ze0(<<~'RUBY')
      C = Data.define(:a)
      r = [C.new(1), C.new(2)]
      p r.map { |c| c.with(a: c.a + 1) }.map(&:a)

      D = Data.define(:a, :b)
      ds = [D.new(1, "x"), D.new(2, "y")]
      p ds.map { |d| d.with(a: d.a * 10) }.map(&:a)
      p ds.map { |d| d.with(b: d.b.upcase).to_h }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [10, 20]
      [{a: 1, b: "X"}, {a: 2, b: "Y"}]
    OUT
  end

  it "issue 2906" do
    result = ze0(<<~'RUBY')
      Point = Struct.new(:x, :y)
      pts = [Point.new(1, 2), Point.new(3, 4)]
      p pts.min_by { |pt| pt.x }.to_h
      p pts.max_by { |pt| pt.x }.to_h
      p pts[0].to_h
      D = Data.define(:a, :b)
      ds = [D.new(5, 6), D.new(7, 8)]
      p ds.min_by { |d| d.a }.to_h
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1, y: 2}
      {x: 3, y: 4}
      {x: 1, y: 2}
      {a: 5, b: 6}
    OUT
  end

  it "issue 2937" do
    result = ze0(<<~'RUBY')
      # to_a / members / to_h on a Struct read out of a poly container (Struct#to_a
      # is its member values, #members the field-name symbols).
      E = Struct.new(:a, :b)
      x = [E.new(1, 2), E.new(3, 4)].max_by(&:b)
      p x.to_h
      p x.to_a
      p x.members
      D = Data.define(:x, :y)
      d = [D.new(1, 2), D.new(5, 6)].max_by(&:y)
      p d.to_h
      p d.members
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 3, b: 4}
      [3, 4]
      [:a, :b]
      {x: 5, y: 6}
      [:x, :y]
    OUT
  end

  it "issue 2940" do
    result = ze0(<<~'RUBY')
      # Multiple assignment from #deconstruct of a Data/Struct value read out of a
      # poly container: deconstruct is the member values (an Array), which the poly
      # receiver derives via sp_poly_to_a_arr.
      V = Data.define(:x, :y)
      first = [V.new(1, 2)].first
      a, b = first.deconstruct
      p [a, b]
      p first.deconstruct
      S = Struct.new(:m, :n)
      s = [S.new(5, 6), S.new(7, 8)].last
      c, d = s.deconstruct
      p [c, d]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [7, 8]
    OUT
  end

  it "issue 2971" do
    result = ze0(<<~'RUBY')
      Point = Data.define(:x, :y)
      p Point.new(*[1, 2])
      p (Point.new(*[1]) rescue $!.class)
      p (Point.new(*[1,2,3]) rescue $!.class)
      S = Struct.new(:a, :b)
      p S.new(*[1, 2]).to_a
      p S.new(*[1]).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Point x=1, y=2>
      ArgumentError
      ArgumentError
      [1, 2]
      [1, nil]
    OUT
  end

  it "issue 2972" do
    result = ze0(<<~'RUBY')
      Point = Data.define(:x, :y)
      a = Point.new(1, 2)
      p a.with(**{x: 10})
      p a.with(**{x: 10, y: 20})
      p a.with(y: 5, **{x: 9})
      p a.with(**{})
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Point x=10, y=2>
      #<data Point x=10, y=20>
      #<data Point x=9, y=5>
      #<data Point x=1, y=2>
    OUT
  end

  it "issue 2973" do
    result = ze0(<<~'RUBY')
      syms = [:sx, :sy, :sz]
      K = Data.define(*syms)
      p K.members
      k = K.new(1, 2, 3)
      p [k.sx, k.sy, k.sz]
      ms = [:a, :b]
      S = Struct.new(*ms)
      p S.members
      p S.new(7, 8).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [:sx, :sy, :sz]
      [1, 2, 3]
      [:a, :b]
      [7, 8]
    OUT
  end

  it "issue 2974" do
    result = ze0(<<~'RUBY')
      Point = Data.define(:x, :y)
      p1 = Point.new(1, 2)
      p(p1.deconstruct_keys([:x, :nope]))
      p(p1.deconstruct_keys([:x, :y]))
      p(p1.deconstruct_keys(nil))
      p(p1.deconstruct_keys([:nope]))
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1}
      {x: 1, y: 2}
      {x: 1, y: 2}
      {}
    OUT
  end

  it "issue 2975" do
    result = ze0(<<~'RUBY')
      C = Data.define(:class, :hash)
      c = C.new("k", 5)
      p(c.class)
      p(c.hash)
      # a Struct member named after a builtin shadows it too
      S = Struct.new(:class)
      s = S.new("sv")
      p(s.class)
      # normal Data still reports its class and a consistent hash
      P = Data.define(:x, :y)
      p P.new(1, 2).class
      p(P.new(1, 2).hash == P.new(1, 2).hash)
    RUBY

    _(result).must_answer <<~'OUT'
      "k"
      5
      "sv"
      P
      true
    OUT
  end

  it "issue 3078" do
    result = ze0(<<~'RUBY')
      Pt = Struct.new(:x, :y)
      a = Pt.new(1, 2).freeze
      p(begin; a.x = 5; rescue => e; e.class; end)
      b = Pt.new(1, 2).freeze
      p(begin; b[0] = 5; rescue => e; e.class; end)
      c = Pt.new(3, 4)
      c.x = 9; p c.x
      d = Pt.new(3, 4)
      d[1] = 9; p d.y
    RUBY

    _(result).must_answer <<~'OUT'
      FrozenError
      FrozenError
      9
      9
    OUT
  end

  it "issue 3079" do
    result = ze0(<<~'RUBY')
      KW = Struct.new(:a, :b, keyword_init: true)
      r = (begin; KW.new(a: 1, z: 9); "no error"; rescue ArgumentError => e; e.class; end); p r
      p(KW.new(a: 1, b: 2).to_a)
      p(KW.new(a: 1).to_a)
      D = Data.define(:x, :y)
      p((D.new(x: 1, w: 2) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      [1, 2]
      [1, nil]
      ArgumentError
    OUT
  end

  it "issue 3101" do
    result = ze0(<<~'RUBY')
      class C; end
      class D; end
      C.freeze
      p C.frozen?
      p D.frozen?
      S = Struct.new(:a)
      S.freeze
      p S.frozen?
      p String.frozen?
      String.freeze
      p String.frozen?
      module M; end
      M.freeze
      p M.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      true
    OUT
  end

  it "issue 3110" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:verbose?, :name)
      o = S.new(true, "x")
      p o.verbose?
      p o.members
      p o.to_h
      p o.inspect
      p o["verbose?"]
      o["verbose?"] = false
      p o.verbose?
      p o == S.new(false, "x")
      # writer/reader via send (the only way to reach `verbose?=`, since
      # `o.verbose? = x` is a syntax error) -- static, dynamic, and public_send
      p o.send(:"verbose?=", true)
      p o.verbose?
      p o.send(:verbose?)
      m = :"verbose?="
      o.send(m, false)
      p o.verbose?
      o.public_send(:"verbose?=", true)
      p o.verbose?
      p o.respond_to?(:"verbose?=")
      D = Data.define(:ok?, :count)
      d = D.new(ok?: true, count: 3)
      p d.ok?
      p d.members
      p d.to_h
      p d.inspect
      p d.with(ok?: false).ok?
      p d.send(:ok?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [:verbose?, :name]
      {verbose?: true, name: "x"}
      "#<struct S :verbose?=true, name=\"x\">"
      true
      false
      true
      true
      true
      true
      false
      true
      true
      true
      [:ok?, :count]
      {ok?: true, count: 3}
      "#<data D :ok?=true, count=3>"
      false
      true
    OUT
  end

  it "issue 3112" do
    result = ze0(<<~'RUBY')
      name = :port
      S = Struct.new(name)
      p S.members
      p S.new(5).port
      a = :x; b = :y
      T = Struct.new(a, b)
      p T.members
      p T.new(1, 2).y
      U = Struct.new(:direct, b)
      p U.members
      f = :label
      D = Data.define(f)
      p D.members
      p D.new(label: "hi").label
    RUBY

    _(result).must_answer <<~'OUT'
      [:port]
      5
      [:x, :y]
      2
      [:direct, :y]
      [:label]
      "hi"
    OUT
  end

  it "issue 3119" do
    result = ze0(<<~'RUBY')
      r = (begin; h = {a: 1}.freeze; h[:b] = 2; rescue FrozenError => e; e.receiver; end)
      p r
      h2 = { "k" => 1 }.freeze
      r2 = begin; h2.delete("k"); rescue FrozenError => e; e.receiver.equal?(h2); end
      p r2
      S = Struct.new(:a)
      s = S.new(1).freeze
      r3 = begin; s.a = 2; rescue FrozenError => e; e.receiver.equal?(s); end
      p r3
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1}
      true
      true
    OUT
  end

  it "issue 3161" do
    _(ze0(<<~'RUBY')).must_answer "3,4\n"
      Vec = Data.define(:x, :y)

      top = [Vec.new(3, 4)].first
      case top
      in { x:, y: }
        puts "#{x},#{y}"
      end
    RUBY
  end

  it "issue 3179" do
    result = ze0(<<~'RUBY')
      A = Struct.new(:x)
      B = Struct.new(:y)
      def ev(node)
        case node
        in A[x] then "a:#{x}"
        in B[y] then "b:#{y}"
        end
      end
      p ev(A.new(5))
      p ev(B.new(9))

      C = Struct.new(:p, :q)
      def ev2(n)
        case n
        in A[x] then "A #{x}"
        in C[p, q] then "C #{p} #{q}"
        else "none"
        end
      end
      p ev2(A.new(1))
      p ev2(C.new(2, 3))
      p ev2(B.new(4))
    RUBY

    _(result).must_answer <<~'OUT'
      "a:5"
      "b:9"
      "A 1"
      "C 2 3"
      "none"
    OUT
  end

  it "issue 3180" do
    result = ze0(<<~'RUBY')
      User = Data.define(:name)
      h = { user: User.new("Alice") }
      case h
      in { user: User[name:] }
        p name
      end
      u = User.new("Alice")
      case u
      in User[name:]
        p name          # => "Alice" under both
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "Alice"
      "Alice"
    OUT
  end

  it "issue 3183" do
    result = ze0(<<~'RUBY')
      def greet3(g, n) = "#{g}, #{n}!"
      cg = method(:greet3).to_proc.curry
      p cg["Hi"]["there"]
      p cg["Hi", "world"]

      Point = Struct.new(:x, :y)
      def combine(a, b, c) = "#{a.x}-#{b}-#{c}"
      f = method(:combine).to_proc.curry
      p f[Point.new(1, 2)]["mid"][3]

      g = ->(a, b) { "#{a}/#{b}" }.curry
      p g["x"]["y"]

      def add3(a, b, c) = a + b + c
      h = method(:add3).to_proc.curry
      p h[1][2][3]
    RUBY

    _(result).must_answer <<~'OUT'
      "Hi, there!"
      "Hi, world!"
      "1-mid-3"
      "x/y"
      6
    OUT
  end

  it "issue 3226" do
    result = ze0(<<~'RUBY')
      D = Data.define(:a, :b) do
        def to_hash = to_h
        def bump = with(b: b + 1)
        def keys = members
        def dk = deconstruct_keys(nil)
        def bad_to_a = (to_a rescue $!.class)
      end
      d = D.new(a: 1, b: 2)
      p d.to_hash
      p d.bump.to_h
      p d.keys
      p d.dk
      p d.bad_to_a

      S = Struct.new(:a, :b) do
        def pair = to_a
        def sz = size
        def h = to_h
      end
      s = S.new(1, 2)
      p s.pair
      p s.sz
      p s.h
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {a: 1, b: 3}
      [:a, :b]
      {a: 1, b: 2}
      NameError
      [1, 2]
      2
      {a: 1, b: 2}
    OUT
  end

  it "issue 3239" do
    result = ze0(<<~'RUBY')
      # A Data/Struct field reader whose name collides with a Time builtin must
      # dispatch to the member reader when the value flows through a poly block param.
      Event = Data.define(:day, :hour)
      events = [Event.new("Mon", 9), Event.new("Wed", 14)]
      p events.map { |e| e.day }
      events.each { |e| p e.hour }

      Point = Struct.new(:day)
      pts = [Point.new("x"), Point.new("y")]
      p pts.map { |e| e.day }
    RUBY

    _(result).must_answer <<~'OUT'
      ["Mon", "Wed"]
      9
      14
      ["x", "y"]
    OUT
  end
end
