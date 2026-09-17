# frozen_string_literal: true

require "spec_helper"

describe "Struct: formatting and inspection" do
  it "anon struct class value" do
    result = ze0(<<~'RUBY')
      # `Struct.new(:a)` used as a VALUE rather than bound to a name -- printed,
      # passed, put in an array -- had no class registered for it at all, and the
      # call reported `Struct.new` as undefined (#4031). Only the forms that are a
      # name's value or another call's receiver were registered.
      #
      # Such a class is anonymous: CRuby renders it as the address form, and the
      # StructAnon_<n> the compiler keys it by is not a Ruby-visible name. #name
      # already answered nil; #to_s and #inspect say the same thing now.
      def anon?(s) = s.start_with?("#<Class:0x") && s.end_with?(">")

      p anon?(Struct.new.to_s)
      p anon?(Struct.new(:a).to_s)
      p anon?(Struct.new(:a).inspect)
      p anon?(Data.define(:x).to_s)
      p Struct.new(:a).name
      p Data.define(:x).name

      s = Struct.new(:a, :b)
      p anon?(s.to_s)
      p s.name
      p s.new(1, 2).to_a
      p s.members

      # a NAMED one keeps its name
      S = Struct.new(:a)
      p S.to_s
      p S.name
      p S.new(3).a

      D = Data.define(:x)
      p D.name
      p D.new(x: 4).x

      # and the chained forms that already worked
      p Struct.new(:a).new(1).a
      p Struct.new(:a).members
      p [Struct.new(:a), Struct.new(:b)].size
      p Struct.new(:a).new(7).class.name
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      nil
      nil
      true
      nil
      [1, 2]
      [:a, :b]
      "S"
      "S"
      3
      "D"
      4
      1
      [:a]
      2
      nil
    OUT
  end

  it "anon struct local" do
    result = ze0(<<~'RUBY')
      # Struct.new(:a, :b) / Data.define(:x, :y) assigned DIRECTLY to a local
      # (never through a constant): register_structs synthesizes an anonymous
      # struct class keyed to the write node, class_var_static_ci resolves the
      # local's reads to it (so .new/.members and the member accessors dispatch
      # like the constant form), the value itself is a first-class class object,
      # and #inspect omits the synthetic name like CRuby (#<struct a=1, b=2>).
      k144 = Struct.new(:a, :b)
      obj = k144.new(1, 2)
      p(obj.a)
      p(obj.b)
      obj.b = 20
      p(obj.b)
      p(k144.members)
      p obj
      p obj.to_a

      d = Data.define(:x, :y)
      dv = d.new(x: 5, y: 6)
      p dv.x
      p dv

      pair = Struct.new(:l, :r)
      p1 = pair.new("L", "R")
      p p1.sum { |v| v.length }
      p(p1.map { |v| v * 2 })

      begin
        k144.new(1, 2, 3)
      rescue ArgumentError => e
        puts "AE: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      20
      [:a, :b]
      #<struct a=1, b=20>
      [1, 20]
      5
      #<data x=5, y=6>
      2
      ["LL", "RR"]
      AE: struct size differs
    OUT
  end

  it "cell value struct capture" do
    result = ze0(<<~'RUBY')
      # A captured-and-reassigned local needs a heap cell. Float, poly and class each
      # got a cell of their own C type; Range, Rational and Complex are the same shape
      # -- small by-value structs with no GC pointer -- but were left on the
      # "non-integer capture" reject, in the cell prologue AND in the capture struct.
      # And the block-local reset had no by-value arm at all, so a captured class
      # there fell through to the sp_int else and assigned an sp_int * to an
      # sp_Class *: ill-typed C for a program CRuby runs.

      2.times do |n|
        v = (n..3)
        pr = proc { v = (n..4); nil }
        pr.call
        puts v.to_s
      end

      2.times do |n|
        v = Rational(n + 1, 2)
        pr = proc { v = Rational(n + 1, 3); nil }
        pr.call
        puts v.to_s
      end

      2.times do |n|
        v = Complex(n, 1)
        pr = proc { v = Complex(n, 2); nil }
        pr.call
        puts v.to_s
      end

      2.times do |n|
        v = (n + 0.5)..3.5
        pr = proc { v = (n + 0.5)..4.5; nil }
        pr.call
        puts v.to_s
      end

      # the class cell, whose reset arm was the missing one
      2.times do |n|
        k = Struct.new(:x)
        pr = proc { k.new(n) }
        puts pr.call.x.to_s
      end

      # reading a captured by-value struct without reassigning it
      2.times do |n|
        span = (n..(n + 2))
        rat = Rational(n + 1, 4)
        pr = proc { span.to_a.length + rat.denominator }
        puts pr.call.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0..4
      1..4
      1/3
      2/3
      0+2i
      1+2i
      0.5..4.5
      1.5..4.5
      0
      1
      7
      5
    OUT
  end

  it "data inspect in container" do
    result = ze0(<<~'RUBY')
      I = Data.define(:v)
      x = I.new(1)
      p([x])
      p({ k: x })
    RUBY

    _(result).must_answer <<~'OUT'
      [#<data I v=1>]
      {k: #<data I v=1>}
    OUT
  end

  it "data positional args are keywords" do
    result = ze0(<<~'RUBY')
      # `Data.define` builds a class whose two constructor forms are the SAME
      # constructor: ruby converts positional arguments to keywords and reports a
      # shortfall as a missing KEYWORD, never as an arity error.
      #
      #     Coord.new(1)  ->  ArgumentError: missing keyword: :lng
      #
      # zeo reports "wrong number of arguments (given 1, expected 2)", which is
      # `Struct`'s message -- and `Struct` really does allow the short form
      # (`S.new(1)` leaves `b` nil), so the two classes need different bodies here.
      # `Data` is the immutable half of that pair, and refusing an incomplete
      # instance is the whole reason it exists.
      #
      # The memberless case has a stray space: zeo inspects `Data.define.new` as
      # `#<data D2 >`, ruby as `#<data D2>` -- the separator is emitted before the
      # member list rather than between members.

      Coord = Data.define(:lat, :lng)

      begin
        Coord.new(1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        Coord.new(1, 2, 3)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        Coord.new(lat: 1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      Empty = Data.define
      p Empty.new
      p Empty.new.inspect

      # Struct keeps the short form and the arity message -- these must not change.
      Pair = Struct.new(:a, :b)
      p Pair.new(1)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: missing keyword: :lng
      ArgumentError: wrong number of arguments (given 3, expected 0..2)
      ArgumentError: missing keyword: :lng
      #<data Empty>
      "#<data Empty>"
      #<struct Pair a=1, b=nil>
    OUT
  end

  it "data reopen reader" do
    result = ze0(<<~'RUBY')
      # A Data.define (or Struct.new) generated reader must resolve inside a method
      # defined on the REOPENED class.
      #
      # `D = Data.define(:x)` is a ConstantWriteNode; the following `class D ... end`
      # is a ClassNode. walk_scope runs before struct registration and, not knowing D
      # is a Data class, pre-creates a memberless class D. Struct registration then
      # saw D already existed and skipped it, so `def double = x * 2` could not
      # resolve the generated reader `x` and rejected the arithmetic. Register the
      # members onto the existing class instead of skipping.

      D = Data.define(:x)
      class D
        def double = x * 2
      end
      p D.new(3).double                  #=> 6

      # Multiple members, several methods.
      P = Data.define(:x, :y)
      class P
        def sum = x + y
        def to_s = "(#{x}, #{y})"
      end
      p P.new(3, 4).sum                  #=> 7
      puts P.new(1, 2).to_s              #=> (1, 2)

      # Data#with produces a new instance whose reader still resolves.
      p D.new(5).with(x: 10).double      #=> 20

      # Struct reopen works the same way.
      S = Struct.new(:a)
      class S
        def twice = a * 2
      end
      p S.new(7).twice                   #=> 14

      # The block form (no reopen) still works.
      E = Data.define(:v) do
        def neg = -v
      end
      p E.new(9).neg                     #=> -9

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      6
      7
      (1, 2)
      20
      14
      -9
      done
    OUT
  end

  it "i994" do
    result = ze0(<<~'RUBY')
      Person = Struct.new(:name, :age)
      p = Person.new("Alice", 30)
      puts p.name
      puts p.age
      puts p[:name]
      puts p[:age]
      puts p[0]
      puts p[1]
      puts p[-1]

      Point = Struct.new(:x, :y) do
        def to_s
          "(#{x}, #{y})"
        end
      end
      pt = Point.new(3, 4)
      puts pt.to_s
      puts pt
    RUBY

    _(result).must_answer <<~'OUT'
      Alice
      30
      Alice
      30
      Alice
      30
      30
      (3, 4)
      (3, 4)
    OUT
  end

  it "process times returns a process tms struct" do
    result = ze0(<<~'RUBY')
      # Process.times returns a Process::Tms with Float utime/stime/cutime/cstime
      # (via getrusage); the class name and struct-style inspect match CRuby.

      p Process::Tms
      t = Process.times
      p t.class
      p t.utime.class
      p t.stime >= 0.0
      p t.cutime.class
      p t.cstime.class
      p t.inspect.start_with?("#<struct Process::Tms utime=")
    RUBY

    _(result).must_answer <<~'OUT'
      Process::Tms
      Process::Tms
      Float
      true
      Float
      Float
      true
    OUT
  end

  it "struct accessor is an entry of the kernels" do
    result = ze0(<<~'RUBY', path: "core/struct/a_struct_accessor_is_an_entry_of_the_kernels.rb")
      # A Struct member's reader and writer are entries of the kernel's, with
      # no frame of their own: the arity error is the caller's, a trace sees
      # a C call, the writer's one parameter is `_`, and an allocated struct
      # reads nil and takes a write; Data's readers are the same entries.
      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      begin; s.a(2); rescue ArgumentError => e; puts e.message; puts e.backtrace.first(2); end
      begin; s.send(:a=, 1, 2); rescue ArgumentError => e; puts e.message; puts e.backtrace.first(2); end
      begin; s.a(k: 1); rescue ArgumentError => e; puts e.message; end
      begin; s.freeze.a = 3; rescue => e; puts e.class, e.message; end
      m = S.instance_method(:a)
      p m.source_location, m.owner, m.inspect, m.arity, m.parameters, S.instance_method(:a=).inspect
      ev = []
      tp = TracePoint.new(:call, :return, :c_call, :c_return) { |t| ev << [t.event, t.method_id] if %i[a a=].include?(t.method_id) }
      t = S.new(5, 6)
      tp.enable { t.a; t.a = 1 }
      p ev
      class T < S
        def a = super + 100
        def a=(v); super(v * 2); end
      end
      u = T.new(1, 2)
      u.a = 3
      p u.a, u.to_a
      x = S.allocate
      p x.a
      x.b = 9
      p x.to_a
      D = Data.define(:q)
      p D.new(q: 1).q, D.instance_method(:q).parameters, D.instance_method(:q).source_location
      p S.instance_method(:a).bind(T.new(7, 8)).call
      begin; S.instance_method(:a).bind(Object.new); rescue TypeError => e; puts e.message; end
      p s.respond_to?(:a=), S.public_instance_methods(false).sort
      p s.method(:a).to_proc.lambda?, s.method(:a).to_proc.call
      p S.new(1).a, (S.new(1, 2, 3) rescue $!.message)

    RUBY

    _(result).must_answer <<~'OUT'
      wrong number of arguments (given 1, expected 0)
      core/struct/a_struct_accessor_is_an_entry_of_the_kernels.rb:7:in '<main>'
      wrong number of arguments (given 2, expected 1)
      core/struct/a_struct_accessor_is_an_entry_of_the_kernels.rb:8:in '<main>'
      wrong number of arguments (given 1, expected 0)
      FrozenError
      can't modify frozen S: #<struct S a=1, b=2>
      nil
      S
      "#<UnboundMethod: S#a()>"
      0
      []
      "#<UnboundMethod: S#a=(_)>"
      [[:c_call, :a], [:c_return, :a], [:c_call, :a=], [:c_return, :a=]]
      106
      [6, 2]
      nil
      [nil, 9]
      1
      []
      nil
      7
      bind argument must be an instance of S
      true
      [:a, :a=, :b, :b=]
      true
      1
      1
      "struct size differs"
    OUT
  end

  it "struct data inspect" do
    result = ze0(<<~'RUBY')
      # p / puts / print / interpolation / #inspect / #to_s of Struct and Data
      # instances render like CRuby. A user-defined #inspect or #to_s overrides the
      # generated one. Regular objects with a user #inspect also print via p now.
      P = Data.define(:a, :b)
      x = P.new(a: 1, b: 2)
      p x
      puts x
      puts x.inspect
      puts x.to_s
      puts "val=#{x}"

      S = Struct.new(:m, :n)
      y = S.new(3, "hi")
      p y
      puts "s=#{y}"

      # nested struct member inspects recursively
      Q = Data.define(:inner)
      p Q.new(inner: P.new(a: 9, b: 8))


      # user-defined inspect/to_s win over the generated ones
      class Pt
        def initialize(v); @v = v; end
        def inspect; "Pt(#{@v})"; end
        def to_s; "pt:#{@v}"; end
      end
      p Pt.new(7)
      puts Pt.new(8)
    RUBY

    _(result).must_answer <<~'OUT'
      #<data P a=1, b=2>
      #<data P a=1, b=2>
      #<data P a=1, b=2>
      #<data P a=1, b=2>
      val=#<data P a=1, b=2>
      #<struct S m=3, n="hi">
      s=#<struct S m=3, n="hi">
      #<data Q inner=#<data P a=9, b=8>>
      Pt(7)
      pt:8
    OUT
  end

  it "struct display to s" do
    _(ze0(<<~'RUBY')).must_answer "#<struct Point x=1, y=2>\n"
      Point = Struct.new(:x, :y)
      Point.new(1, 2).display
      puts
    RUBY
  end

  it "struct keyword init inspect" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A keyword_init Struct's inspect omits the "(keyword_init: true)" suffix.
      #
      K = Struct.new(:a, keyword_init: true)
      J = Struct.new(:a)
      DD = Data.define(:a)

      p K.name
      p K.to_s
      p K.inspect
      p K
      p J.name, J.to_s, J.inspect, J
      p DD.name, DD.to_s, DD.inspect, DD

      k = K.new(a: 1)
      p k
      p k.class
      p k.class.inspect
      p k.class.to_s
      p k.class.name
      p K.keyword_init?
      p J.keyword_init?

      j = J.new(2)
      p j.class
      p "#{K}"
    RUBY

    _(result).must_answer <<~'OUT'
      "K"
      "K"
      "K(keyword_init: true)"
      K(keyword_init: true)
      "J"
      "J"
      "J"
      J
      "DD"
      "DD"
      "DD"
      DD
      #<struct K a=1>
      K(keyword_init: true)
      "K(keyword_init: true)"
      "K"
      "K"
      true
      nil
      J
      "K"
    OUT
  end

  it "struct local zero arg new" do
    result = ze0(<<~'RUBY')
      # A member-less `Struct`/`Data` inspects with the space CRuby prints.
      #
      # CRuby writes `#<struct ` and then the NAME, so the separator belongs to
      # the name's position: a named memberless struct is `#<struct Empty>` and
      # an ANONYMOUS one keeps the space the name would have gone in
      # (`#<struct >`). zeo dropped it whenever the member list was empty.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # `.new` with no arguments on a Struct held in a LOCAL was claimed by the
      # runtime-class switch, which a local statically holding one class should never
      # reach -- it dispatches like the constant it holds. That switch also has no arm
      # for a Struct, so it came out empty and its nil seed was cast to the struct
      # pointer. A memberless anonymous struct also inspects with the space that would
      # precede its first member, as CRuby does.

      p Struct.new.new
      p Data.define.new

      s = Struct.new
      p s.new
      x = s.new
      p x.to_a
      p x.size

      t = Struct.new(:a)
      p t.new
      p t.new(1)
      p t.new(1).a
      p t.new.a

      u = Struct.new(:a, :b)
      p u.new(1)
      p u.new(1, 2).to_a

      S9 = Struct.new
      p S9.new
      S8 = Struct.new(:a)
      p S8.new
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct >
      #<data >
      #<struct >
      []
      0
      #<struct a=nil>
      #<struct a=1>
      1
      nil
      #<struct a=1, b=nil>
      [1, 2]
      #<struct S9>
      #<struct S8 a=nil>
    OUT
  end

  it "struct member size reader" do
    result = ze0(<<~'RUBY')
      # A Struct member named `size` (or `length`) must dispatch to the generated
      # member reader, not the built-in length/size, even on a poly receiver.
      E = Struct.new(:offset, :size, :name)
      entries = 3.times.map do |i|
        E.new(i * 10, i * 100 + 5, "n#{i}")
      end
      entries.each { |e| puts "#{e.offset},#{e.size},#{e.name}" }
      # poly-typed element access
      list = entries
      puts list[1].size
      puts list.map(&:size).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      0,5,n0
      10,105,n1
      20,205,n2
      105
      [5, 105, 205]
    OUT
  end

  it "struct to a values" do
    result = ze0(<<~'RUBY')
      # Struct#to_a and #values gather the member values into an array,
      # preserving declaration order. Members may be heterogeneous.
      Person = Struct.new(:name, :age)
      pp = Person.new("Alice", 30)
      p pp.values
      p pp.to_a
      puts pp.values.inspect
      Point = Struct.new(:x, :y)
      p Point.new(3, 4).to_a
      Mixed = Struct.new(:a, :b, :c)
      p Mixed.new(1.5, [1, 2, 3], "hi").to_a
      p Mixed.new(1.5, [1, 2, 3], "hi").values
    RUBY

    _(result).must_answer <<~'OUT'
      ["Alice", 30]
      ["Alice", 30]
      ["Alice", 30]
      [3, 4]
      [1.5, [1, 2, 3], "hi"]
      [1.5, [1, 2, 3], "hi"]
    OUT
  end
end
