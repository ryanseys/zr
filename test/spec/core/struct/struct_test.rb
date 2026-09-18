# frozen_string_literal: true

require "spec_helper"

describe "Struct programs" do
  it "accessor reports rubys parameter name" do
    result = ze0(<<~'RUBY')
      # A generated WRITER's reported parameter, which differs by where it came from.
      #
      # ruby names an `attr_writer`/`attr_accessor` slot NOTHING -- the C accessor
      # entry declares only a count -- and names a Struct member's slot `_`. zeo
      # spells both as the same generated accessor, so the struct half renames its
      # slot after lowering; the mark that elides the frame survives either way.

      class Plain
        attr_accessor :a
        attr_writer :b
        attr_reader :c
      end
      p Plain.instance_method(:a=).parameters
      p Plain.instance_method(:a).parameters
      p Plain.instance_method(:b=).parameters
      p Plain.instance_method(:c).parameters
      p Plain.instance_method(:a=).arity

      S = Struct.new(:x, :y)
      p S.instance_method(:x=).parameters
      p S.instance_method(:x).parameters
      p S.instance_method(:x=).arity

      # A struct minted where the compiler cannot fold it takes the same answers.
      def mint(*names) = Struct.new(*names)
      T = mint(:z)
      p T.instance_method(:z=).parameters

      D = Data.define(:d)
      p D.instance_method(:d).parameters

      # The writers still WORK, and still write the slot they name.
      o = Plain.new
      o.a = 1
      o.b = 2
      p [o.a, o.instance_variable_get(:@b)]
      s = S.new(1, 2)
      s.x = 9
      p [s.x, s.to_a]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:req]]
      []
      [[:req]]
      []
      1
      [[:req, :_]]
      []
      1
      [[:req, :_]]
      []
      [1, 2]
      [9, [9, 2]]
    OUT
  end

  it "anon struct name nil" do
    result = ze0(<<~'RUBY')
      k = Struct.new(:a)
      p k.name
      d = Data.define(:z)
      v = d.name
      p v
      K = Struct.new(:a)
      p K.name
      p Struct.new(:a).name
      i = k.new(1)
      p i.a
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "K"
      nil
      1
    OUT
  end

  it "anonymous struct mints a native class at runtime" do
    result = ze0(<<~'RUBY')
      # `Struct.new` in ANY position mints a native struct class at runtime: an
      # anonymous local/inline struct is a runtime value, exactly like the
      # constant form -- there is no compile-time-synthesized path.

      k = Struct.new(:a, :b)
      o = k.new(1, 2)
      p o
      p o.a
      p o.to_a
      p o.members
      o.a = 9
      p o.a
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct a=1, b=2>
      1
      [1, 2]
      [:a, :b]
      9
    OUT
  end

  it "block param widen multi struct" do
    result = ze0(<<~'RUBY')
      # A block over an unresolved receiver, for a name the builtin Enumerable
      # surface also owns, must have its params widened to poly: the dispatch can
      # reach a container at run time, and a user method's yield types describe only
      # the user arm. That widening was tied to a class having been ADOPTED, which
      # happens only when EXACTLY ONE user class defines the name. Every Struct
      # defines `each`, so a second Struct in the file meant nothing was adopted, the
      # widening was skipped, and the param kept an earlier round's guess -- Integer.
      # The Struct members typed from it followed, and the C build stopped (#4086).
      #
      # More candidates is a stronger case for poly, not a weaker one. The widening
      # now needs a candidate to exist, not to be unique.

      module Probe
        Disallowed = Struct.new(:term)
        Finding = Struct.new(:path, :term)

        def self.check(scope)
          scope.keys.each { |a| [1].each { |b| Finding.new(a, a) } }
        end
      end

      f = Probe::Finding.new("a.rb", "Order")
      puts "#{f.path} #{f.term}"

      # and the method actually called (its RETURN is a separate gap, on master too:
      # `each` through a module method answers nil rather than the receiver, so what
      # is checked here is that calling it works and the members stay right)
      Probe.check({ "x" => 1 })
      p Probe::Finding.new("b.rb", "Term").path

      # one Struct, which is the shape that worked by accident
      module Solo
        Only = Struct.new(:v)

        def self.walk(scope)
          scope.keys.each { |a| [1].each { |b| Only.new(a) } }
        end
      end
      p Solo::Only.new("s").v
      Solo.walk({ "y" => 2 })

      # three, to show it is not about the count
      module Trio
        A = Struct.new(:x)
        B = Struct.new(:y)
        C = Struct.new(:z)

        def self.walk(scope)
          scope.each { |a| [1].each { |b| C.new(a) } }
        end
      end
      p Trio::C.new("t").z
      Trio.walk(["u"])

      # a name no user class defines still types its param from the receiver: this is
      # what over-widening broke (a Range element is an Integer, not a poly)
      total = 0
      (1..3).each { |x| total += x }
      p total
      p (1..3).map { |x| x * 2 }
      p [1, 2, 3].each_cons(2).map { |pair| pair[0] + pair[1] }
    RUBY

    _(result).must_answer <<~'OUT'
      a.rb Order
      "b.rb"
      "s"
      "t"
      6
      [2, 4, 6]
      [3, 5]
    OUT
  end

  it "class ordering vs data" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      S = Struct.new(:a)
      p(P < Data)
      p(S < Struct)
      p(P < Struct)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      nil
    OUT
  end

  it "const struct matches the oracle" do
    result = ze0(<<~'RUBY')
      # `Point = Struct.new(:x, :y)` mints a native struct class at runtime (Batch
      # E) and the constant write names it: accessors, positional init (nil-filled),
      # members/to_a/to_h/==/[]/[]=/each_pair/inspect, and Enumerable through the
      # real ancestor chain. Plus keyword_init and the block-with-methods form. The
      # constant form now takes the exact same runtime path as the anonymous one --
      # no compile-time synthesis.

      Point = Struct.new(:x, :y)
      pt = Point.new(1, 2)
      p pt
      puts pt.x
      pt.y = 9
      p pt.to_a
      p pt.to_h
      p pt.members
      p pt == Point.new(1, 9)
      p pt == Point.new(1, 2)
      p pt[0]
      p pt[:y]
      p pt["x"]
      p pt[-1]
      pt[1] = 20
      p pt.y
      p pt.length
      p pt.map { |v| v }
      p pt.select { |v| v.is_a?(Integer) }
      acc = []
      pt.each_pair { |k, v| acc << [k, v] }
      p acc
      p Point.ancestors.include?(Struct)
      p Point.ancestors.include?(Enumerable)
      Label = Struct.new(:text, keyword_init: true)
      l = Label.new(text: "hi")
      p l
      Pair = Struct.new(:a, :b) do
        def total
          a + b
        end
      end
      p Pair.new(3, 4).total
      p Point.new(5).y
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct Point x=1, y=2>
      1
      [1, 9]
      {x: 1, y: 9}
      [:x, :y]
      true
      false
      1
      9
      1
      9
      20
      2
      [1, 20]
      [1, 20]
      [[:x, 1], [:y, 20]]
      true
      true
      #<struct Label text="hi">
      7
      nil
    OUT
  end

  it "data bare new in factory" do
    result = ze0(<<~'RUBY')
      # A bare `new(...)` (implicit self) inside a Data/Struct singleton factory must
      # forward its arguments to the generated constructor -- positional AND keyword --
      # exactly like an explicit `Klass.new(...)`.
      #
      # A prior bug: the self-call codegen path emitted the constructor only with args
      # when a USER `initialize` existed. A Data/Struct class has no user initialize
      # (its constructor is generated per-member), so `initm < 0` and every argument
      # was dropped -- `def self.default = new(x: 1)` compiled to `sp_Klass_new()`,
      # yielding a zero-arg call the C constructor rejects. The receiver path
      # (`Klass.new(...)`) already did the member-wise fill; the self-call path now
      # mirrors it.

      Size = Data.define(:w, :h) do
        def self.square(n) = new(w: n, h: n)   # bare new, keyword args
        def self.unit = new(1, 1)              # bare new, positional args
      end

      sq = Size.square(4)
      puts sq.w        # 4
      puts sq.h        # 4

      u = Size.unit
      puts u.w         # 1
      puts u.h         # 1

      # Nested: a factory whose bare `new` takes another Data value as a field, and a
      # default-carrying factory (the shell-model shape).
      Box = Data.define(:name, :size, :open) do
        def self.default = new(name: "box", size: Size.square(3), open: false)
      end

      b = Box.default
      puts b.name      # box
      puts b.size.w    # 3
      puts b.open      # false

      b2 = b.with(open: true)
      puts b2.open     # true
      puts b2.name     # box
    RUBY

    _(result).must_answer <<~'OUT'
      4
      4
      1
      1
      box
      3
      false
      true
      box
    OUT
  end

  it "data define" do
    result = ze0(<<~'RUBY')
      # `Data.define` builds an IMMUTABLE value class: keyword construction, readers
      # (no writers), structural `==`, and `deconstruct`/`deconstruct_keys` for
      # pattern matching. `with` returns a copy with some members replaced.
      Point = Data.define(:x, :y)

      p1 = Point.new(x: 1, y: 2)
      p p1                            # #<data Point x=1, y=2>
      p p1.x                         # 1
      p p1.to_h                      # {x: 1, y: 2}
      p p1.members                   # [:x, :y]

      # Immutable: `with` returns a NEW value, leaving the original untouched.
      p2 = p1.with(y: 9)
      p p2                           # #<data Point x=1, y=9>
      p p1                           # #<data Point x=1, y=2>  (unchanged)

      # Structural equality by class + members.
      p(p1 == Point.new(x: 1, y: 2)) # true
      p(p1 == p2)                    # false

      # Pattern matching deconstructs by keys...
      def describe(pt)
        case pt
        in { x: 0, y: } then "on the y-axis at #{y}"
        in { x:, y: }   then "at (#{x}, #{y})"
        end
      end
      puts describe(Point.new(x: 0, y: 5))
      puts describe(Point.new(x: 3, y: 4))

      # ...or positionally.
      case p1
      in [a, b] then p [a, b]        # [1, 2]
      end

      # A missing required member on construction is an ArgumentError.
      begin
        Point.new(x: 1)
      rescue ArgumentError => e
        puts "error: #{e.message}"   # missing keyword: :y
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Point x=1, y=2>
      1
      {x: 1, y: 2}
      [:x, :y]
      #<data Point x=1, y=9>
      #<data Point x=1, y=2>
      true
      false
      on the y-axis at 5
      at (3, 4)
      [1, 2]
      error: missing keyword: :y
    OUT
  end

  it "data define constructs deconstructs and is immutable" do
    result = ze0(<<~'RUBY')
      # Data.define synthesizes an immutable value class with keyword
      # construction, deconstruct_keys (hash patterns), to_h, with, ==, inspect.

      Coord = Data.define(:x, :y)
      c = Coord.new(x: 1, y: 2)
      p c
      p c.x
      p c.to_h
      p c.with(y: 9)
      p c
      puts(c == Coord.new(x: 1, y: 2))
      def take(d); case d; in {x:, y:}; x + y; end; end
      p take(c)
      begin
        Coord.new(x: 1)
      rescue ArgumentError => e
        puts "err: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Coord x=1, y=2>
      1
      {x: 1, y: 2}
      #<data Coord x=1, y=9>
      #<data Coord x=1, y=2>
      true
      3
      err: missing keyword: :y
    OUT
  end

  it "data define duplicate member" do
    result = ze0(<<~'RUBY')
      r1 = (begin; k1 = Data.define(:x, :x); "members=#{k1.members}"; rescue ArgumentError; "argerr"; end)
      p r1
      r2 = (begin; k2 = Struct.new(:a, :a); "ok"; rescue ArgumentError; "argerr"; end)
      p r2
      # no-dup definitions still work
      Good = Data.define(:x, :y)
      p Good.new(1, 2).x
      p Good.members
    RUBY

    _(result).must_answer <<~'OUT'
      "argerr"
      "argerr"
      1
      [:x, :y]
    OUT
  end

  it "data is a data" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      p(P.new(1, 2).is_a?(Data))
      a = P.new(1, 2); p(a.is_a?(Data))
      p(P.ancestors.include?(Data))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "data missing keyword message" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x)
      begin
        P.new(y: 1)
      rescue ArgumentError => e
        p e.message
      end
      begin
        P.new
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "missing keyword: :x"
      "missing keyword: :x"
    OUT
  end

  it "data new kwsplat" do
    result = ze0(<<~'RUBY')
      Point = Data.define(:x, :y)
      h = { x: 1, y: 2 }
      p(Point.new(**h))
      p(Point.new(**{ x: 3, y: 4 }))
    RUBY

    _(result).must_answer "#<data Point x=1, y=2>\n#<data Point x=3, y=4>\n"
  end

  it "data new validation" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      r1 = (begin; P.new(1); "no error"; rescue ArgumentError; "argerror"; end); p r1
      r2 = (begin; P.new; "no error"; rescue ArgumentError; "argerror"; end); p r2
      r3 = (begin; P.new(x: 1, y: 2, z: 3); "no error"; rescue ArgumentError; "argerror"; end); p r3
      r4 = (begin; P.new(1, y: 2); "no error"; rescue ArgumentError; "argerror"; end); p r4
    RUBY

    _(result).must_answer <<~'OUT'
      "argerror"
      "argerror"
      "argerror"
      "argerror"
    OUT
  end

  it "data reopen body may nest a class" do
    result = ze0(<<~'RUBY', files: {"data_reopen/target/spec.rb" => "module Pkg3\n  class Target\n    class Spec\n      def initialize(name) = (@name = name; @build = nil)\n      def build(&block) = (@build = block)\n      def fin!\n        raise ArgumentError, \"needs a build block\" if @build.nil?\n        Pkg3::Target.new(name: @name, build_block: @build)\n      end\n    end\n  end\nend\n", "data_reopen/target.rb" => "module Pkg3\n  Target = Data.define(:name, :build_block) do\n    def call(*a) = build_block.call(*a)\n  end\nend\nrequire_relative \"target/spec\"\n"})
      # Reopening a `Data.define` constant with a bare `class` runs the body as a
      # `class_eval` block, and every class-body statement but a local write has a
      # spelling there -- a nested class included. The nested `class Spec` used to
      # send the whole definition back to the static path, which minted a
      # memberless `Target` over the Data class, so `Target.new(name:)` inside
      # `Spec#fin!` raised "wrong number of arguments (given 1, expected 0)".
      #
      # Sow's `lib/sow/reap/target.rb` + `target/spec.rb` is this shape across two
      # files, which `require_relative` below reproduces.

      module Pkg
        Target = Data.define(:name)
        class Target
          class Spec
            def fin! = Pkg::Target.new(name: :t)
          end
          include Comparable
          def <=>(o) = name <=> o.name
        end
      end
      p Pkg::Target::Spec.new.fin!.name
      p Pkg::Target.new(name: :b) > Pkg::Target.new(name: :a)
      p Pkg::Target.ancestors.include?(Data)

      require_relative "data_reopen/target"

      spec = Pkg3::Target::Spec.new(:t)
      spec.build { |x| x + 1 }
      t = spec.fin!
      p t.name, t.call(41)
      p Pkg3::Target.ancestors.include?(Data)
      begin
        Pkg3::Target::Spec.new(:u).fin!
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :t
      true
      true
      :t
      42
      true
      "needs a build block"
    OUT
  end

  it "data respond to" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      a = P.new(1, 2)
      p(a.respond_to?(:with))
      p(a.respond_to?(:members))
      p(a.respond_to?(:deconstruct))
      p(a.respond_to?(:deconstruct_keys))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "data struct ivar get nil" do
    result = ze0(<<~'RUBY')
      # Data/Struct members are not @-instance variables: a literal
      # instance_variable_get answers nil and instance_variables is [] (#2849).
      Point = Data.define(:x, :y)
      p Point.new(1, 2).instance_variable_get(:@x)
      S = Struct.new(:x, :y)
      p S.new(10, 20).instance_variable_get(:@x)
      p S.new(1, 2).instance_variables
      class PL; def initialize; @z = 5; end; end
      p PL.new.instance_variable_get(:@z)
      p PL.new.instance_variables
      p Point.new(1, 2).x
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      []
      5
      [:@z]
      1
    OUT
  end

  it "data value eq container" do
    result = ze0(<<~'RUBY')
      I = Data.define(:v)
      O = Data.define(:m)
      a = I.new(1)
      p([a] == [I.new(1)])
      p([a].include?(I.new(1)))
      p([a, I.new(2)].index(I.new(2)))
      p([a, I.new(1)].uniq.length)
      p({ k: a } == { k: I.new(1) })
      p(O.new(a) == O.new(I.new(1)))
      S = Struct.new(:a, :b)
      p([S.new("x", 1)] == [S.new("x", 1)])
      Pt = Data.define(:name, :tags)
      p(Pt.new("a", [1,2]) == Pt.new("a", [1,2]))
      p(Pt.new("a", [1,2]) == Pt.new("a", [1,3]))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      1
      1
      true
      true
      true
      true
      false
    OUT
  end

  it "data with" do
    result = ze0(<<~'RUBY')
      # Data#with returns a copy of a Data instance with the given members overridden
      # and the rest carried over. Only Data classes (Data.define) have #with.
      P = Data.define(:x, :y)
      a = P.new(x: 1, y: 2)

      b = a.with(x: 9)
      p [b.x, b.y]          # [9, 2]
      p [a.x, a.y]          # [1, 2]  -- original is unchanged

      c = a.with(x: 10, y: 20)
      p [c.x, c.y]          # [10, 20]

      d = a.with             # no overrides -> an equal copy
      p [d.x, d.y]          # [1, 2]

      # string and mixed members.
      Person = Data.define(:name, :age)
      e = Person.new(name: "bob", age: 5)
      f = e.with(age: 6)
      p [f.name, f.age]     # ["bob", 6]
      g = e.with(name: "ann")
      p [g.name, g.age]     # ["ann", 5]
    RUBY

    _(result).must_answer <<~'OUT'
      [9, 2]
      [1, 2]
      [10, 20]
      [1, 2]
      ["bob", 6]
      ["ann", 5]
    OUT
  end

  it "data with unknown kw" do
    result = ze0(<<~'RUBY')
      P = Data.define(:x, :y)
      a = P.new(1, 2)
      r = (a.with(z: 9) rescue $!.class); p r
    RUBY

    _(result).must_answer "ArgumentError\n"
  end

  it "nested pattern data deconstruct" do
    result = ze0(<<~'RUBY')
      D001 = Data.define(:a, :b)
      arr001 = [D001.new(1, 2)]
      r001 = (case arr001; in [D001[x001, y001]] then [x001, y001]; end rescue $!.class)
      p r001

      r002 = (case arr001; in [[x002, y002]] then [x002, y002]; end rescue $!.class); p r002

      r003 = (case arr001; in [D001(a: x003, b: y003)] then [x003, y003]; end rescue $!.class); p r003  # => [1, 2]
      r004 = (case arr001; in [D001 => e004] then e004.a; end rescue $!.class); p r004                  # => 1
      r005 = (case D001.new(1, 2); in [x005, y005] then [x005, y005]; end rescue $!.class); p r005      # => [1, 2]
      p D001.new(1, 2).deconstruct                                                                      # => [1, 2]

      D9 = Data.define(:a, :b)
      r = (D9.new(3, 4).to_a rescue $!.class); p r
      r = (D9.new(3, 4).deconstruct rescue $!.class); p r
      S9 = Struct.new(:a, :b)
      r = (case [S9.new(5, 6)]; in [S9[u, v]] then [u, v]; end rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [1, 2]
      1
      [1, 2]
      [1, 2]
      NoMethodError
      [3, 4]
      [5, 6]
    OUT
  end

  it "nested struct name collision" do
    result = ze0(<<~'RUBY')
      # Two sibling namespaces each defining `TreeNode` -- one a class, one a Struct
      # constant. Only `class` definitions were qualified by their enclosing path, so
      # the Struct constant kept the bare leaf name and every reference to it bound
      # to the other namespace's class (a three-member construction reached a
      # two-parameter constructor and raised ArgumentError).

      module Trees
        class Obj
          class TreeNode
            attr_accessor :item, :left
            def initialize(item, depth = 0)
              @item = item
              @left = depth
            end
          end

          def run
            n = TreeNode.new(5, 2)
            n.item + n.left
          end
        end

        class Arena
          TreeNode = Struct.new(:item, :left, :right)

          def run
            n = TreeNode.new(7, -1, -1)
            n.item + n.left + n.right
          end
        end
      end

      p Trees::Obj.new.run
      p Trees::Arena.new.run
    RUBY

    _(result).must_answer "7\n5\n"
  end

  it "poly dispatch struct arg arm" do
    result = ze0(<<~'RUBY')
      # A poly dispatch drops an arm whose parameter cannot receive the argument.
      # It knew about String and object/non-object mismatches, but not about the
      # kinds C passes as a struct BY VALUE -- Range, Time, Complex, Rational, Class.
      # A struct converts to nothing, and the arm passes its temps raw, so matching
      # `s[0...-5]` by name against a `#[](Symbol)` handed an sp_Range to an sp_sym
      # slot and the generated C did not compile.
      class Tag
        def [](sym) = "sym:#{sym}"
      end

      class Slice
        def [](rng) = rng.to_a.length
      end

      xs = [Tag.new, Slice.new]
      p xs[0][:abc]
      p xs[1][1..4]

      # the same name reached from one union, with each arm getting its own kind
      class A
        def take(r) = r.to_a.length
        def stamp(t) = t.year > 0
      end

      class B
        def take(r) = r.to_a.first
        def stamp(t) = t.month > 0
      end

      both = [A.new, B.new]
      both.each { |o| p o.take(1..3) }
      both.each { |o| p o.stamp(Time.at(0)) }

      # a String slice through an untyped receiver still slices
      def slice_it(s)
        s[0...-5]
      end
      p slice_it("hello.json")
      p slice_it("abcdefgh")
    RUBY

    _(result).must_answer <<~'OUT'
      "sym:abc"
      4
      3
      1
      true
      true
      "hello"
      "abc"
    OUT
  end

  it "poly enum to a builtin arm" do
    result = ze0(<<~'RUBY')
      # The Enumerable desugar puts `__enum_to_a` in front of `obj.map { }` when the
      # receiver's class defines #each. That rewrite is on the AST and permanent, so
      # a receiver that was an object type when the desugar ran and widened to poly
      # afterwards arrives at the dispatch as an Array -- and was told it has no such
      # method:
      #
      #   undefined method '__enum_to_a' for an instance of Array (NoMethodError)
      #
      # Reached here because a Struct member and an unrelated class's instance method
      # share a name, which is what let the parameter look like the Struct for long
      # enough (#4150). The dispatch now carries the builtin arm, the way `join`
      # already does for the same reason (#4071).
      module Contract
        Pair = Struct.new(:registered)

        def self.spell(params)
          params.map { |x| x }
        end

        def self.pick(params)
          params.select { |x| true }
        end

        def self.walk
          [Pair.new].each do |pair|
            Contract.spell(pair.registered)
          end
        end

        class Builder
          def registered
            Pair.new
          end
        end
      end

      # an Array reaches the parameter the desugar typed as the Struct
      p Contract.spell(Contract::Pair.new([1]).registered)
      p Contract.spell([1, 2, 3])
      p Contract.spell(["a", "b"])
      p Contract.spell([1.5, 2.5])
      p Contract.pick([1, 2])

      # the Struct itself still goes through its own arm
      p Contract.spell(Contract::Pair.new(9))

      # and a Hash, which materializes as pairs
      p Contract.spell({ a: 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, 2, 3]
      ["a", "b"]
      [1.5, 2.5]
      [1, 2]
      [9]
      [[:a, 1]]
    OUT
  end

  it "poly map receiver rooted" do
    result = ze0(<<~'RUBY')
      # The receiver of a fused map loop is what the loop reads from, and the body
      # allocates: a receiver built on the spot was held by nothing, so the first
      # collection inside the loop freed the array being walked (#3801).
      S = Struct.new(:x, :y)
      g = (0...40).map { |i| S.new(i * 1.5, i * 2.5) }

      total = 0.0
      count = 0
      g.each do |vertex|
        (g - [vertex]).map do |v|
          p v.x if count.zero?
          count += 1
          total += (v.x - vertex.x).abs
        end
      end
      p count
      p total.round(3)

      # the same shape with a hash receiver built on the spot
      h = { a: 1, b: 2, c: 3 }
      p (h.reject { |k, _| k == :b }).map { |k, v| "#{k}#{v}" }
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      1560
      31980.0
      ["a1", "c3"]
    OUT
  end

  it "proc param value struct types" do
    result = ze0(<<~'RUBY')
      # A by-value struct (Range, Time, Rational, Complex) reaching a lambda or proc
      # parameter rides the boxed side channel, as a Float already did: the mrb_int
      # argument slot cannot hold one, and the emitted C did not compile (#3962).
      f = ->(r) { r.cover?(5) }
      p f.call(1..10)
      g = proc { |r| r.to_a }
      p g.call(1..3)
      h = ->(r, v) { r.include?(v) }
      p h.call(1..10, 3)
      K = ->(r) { r.first }
      p K.call(5..9)
      t = ->(x) { x.to_i }
      p t.call(Time.at(1234))
      q = ->(x) { x.to_s }
      p q.call(Rational(3,4))
      c = ->(x) { x.real }
      p c.call(Complex(1,2))
      fr = ->(x) { x.first }
      p fr.call(1.5..3.5)
      p [1..3, 4..6].map { |r| r.sum }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [1, 2, 3]
      true
      5
      1234
      "3/4"
      1
      1.5
      [6, 15]
    OUT
  end

  it "proc return value struct" do
    result = ze0(<<~'RUBY')
      # A first-class proc publishes its result boxed and the `.call` site unboxes it.
      # That unbox was a second, hand-written copy of emit_unbox_text and had drifted:
      # Range, Time and Class were named, so Rational and Complex fell to the generic
      # `(T)slot.v.p` at the end -- a pointer cast to a struct, which does not compile.
      # The hash variants fell there too, and those read another variant's layout
      # without a diagnostic. The list is gone; the one unbox answers for every kind.

      pr = proc { Rational(3, 2) }
      puts pr.call.to_s

      pc = proc { Complex(1, 2) }
      puts pc.call.to_s

      pg = proc { 1..3 }
      puts pg.call.to_s

      pf = proc { 1.5..3.5 }
      puts pf.call.to_s

      pk = proc { 1.5 }
      puts pk.call.to_s

      ps = proc { "ab" }
      puts ps.call

      # the value flowing on, not just printed
      puts (pr.call + Rational(1, 2)).to_s
      puts (pc.call * Complex(0, 1)).to_s
      puts pg.call.to_a.length.to_s

      # a lambda, and a proc stored and called later
      lm = lambda { Rational(5, 4) }
      puts lm.call.to_s
      store = [proc { Complex(2, 3) }]
      puts store[0].call.to_s

      # Hash#to_proc boxes the hash's VALUE type through the same ABI: the boxing
      # half had the same drift, with no Range arm at all
      h = { "a" => (1..3), "b" => (4..6) }
      p ["a", "b"].map(&h)
      r = { "a" => Rational(1, 2), "b" => Rational(3, 4) }
      p ["a", "b"].map(&r)
      c = { "a" => Complex(1, 2) }
      p ["a"].map(&c)
    RUBY

    _(result).must_answer <<~'OUT'
      3/2
      1+2i
      1..3
      1.5..3.5
      1.5
      ab
      2/1
      -2+1i
      3
      5/4
      2+3i
      [1..3, 4..6]
      [(1/2), (3/4)]
      [(1+2i)]
    OUT
  end

  it "respond to struct data" do
    result = ze0(<<~'RUBY')
      # `respond_to?` on a class receiver answered false for class methods the same
      # program calls: `Struct.new`, `Data.define`, and a generated struct class's
      # own `members` (#3482). Neighbouring core classes already answered true, so
      # these were the odd ones out.
      S = Struct.new(:x, :y)
      D = Data.define(:z)

      p S.new(1, 2).x
      p S.members
      p D.new(z: 3).z

      p Struct.respond_to?(:new)
      p Struct.respond_to?(:members)
      p Data.respond_to?(:define)
      p S.respond_to?(:members)
      p D.respond_to?(:members)
      p S.respond_to?(:new)
      p D.respond_to?(:new)

      # the neighbours that already answered
      p Array.respond_to?(:new)
      p Hash.respond_to?(:[])
      p String.respond_to?(:new)

      # and names a class object genuinely does not answer
      p S.respond_to?(:no_such_method)
      p Struct.respond_to?(:no_such_method)
      p Data.respond_to?(:no_such_method)

      # an instance still answers its own surface
      s = S.new(1, 2)
      p s.respond_to?(:members)
      p s.respond_to?(:x)
      p s.respond_to?(:to_h)
      p s.respond_to?(:no_such_method)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [:x, :y]
      3
      true
      false
      true
      true
      true
      true
      true
      true
      true
      true
      false
      false
      false
      true
      true
      true
      false
    OUT
  end

  it "a Struct reads, writes and prints its members" do
    result = ze0(<<~'RUBY')
      # Test Struct

      Point = Struct.new(:x, :y)

      p1 = Point.new(3, 4)
      puts p1.x       # 3
      puts p1.y       # 4

      p1.x = 10
      puts p1.x       # 10

      # Struct with methods
      Color = Struct.new(:r, :g, :b)

      c = Color.new(255, 128, 0)
      puts c.r        # 255
      puts c.g        # 128
      puts c.b        # 0

      # Struct synthetic constructor path should also handle iv_ prefixed names.
      Pair = Struct.new(:x, :iv_x)
      p2 = Pair.new(3, 4)
      puts p2.x + p2.iv_x   # 7
      p2.iv_x = 6
      puts p2.x + p2.iv_x   # 9
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      10
      255
      128
      0
      7
      9
    OUT
  end

  it "a Struct binds each member from its position, and names the argument it cannot place" do
    result = ze0(<<~'RUBY')
      # A compiled `S = Struct.new(:a)` binds through the runtime kernel, so a
      # program that patches a core Array or Hash method cannot reach inside the
      # constructor. CRuby's `rb_struct_initialize` is C, and reads `argc`.
      module PB
        def size = super * 10
        def empty? = false
        def keys = super
      end
      class Array; prepend PB; end
      class Hash; prepend PB; end
      p [1, 2].size

      S1 = Struct.new(:a, :b)
      p S1.new(1, 2).to_a
      p S1.new(1).to_a
      p S1.new.to_a
      p S1.new(a: 1, b: 2).to_a
      p S1.new(a: 1).to_a
      p(S1.new({ a: 1 }, 2).to_a)
      p(begin; S1.new(1, 2, 3); rescue ArgumentError => e; e.message; end)
      p(begin; S1.new(z: 9); rescue ArgumentError => e; e.message; end)

      D1 = Data.define(:x, :y)
      p D1.new(x: 1, y: 2).to_h
      p(begin; D1.new(x: 1); rescue ArgumentError => e; e.message; end)
      p(begin; D1.new(x: 1, y: 2, z: 3); rescue ArgumentError => e; e.message; end)
      p(begin; D1.new(x: 1, y: 2, z: 3, w: 4); rescue ArgumentError => e; e.message; end)

      S2 = Struct.new(:a, keyword_init: true)
      p(begin; S2.new(z: 1, w: 2); rescue ArgumentError => e; e.message; end)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      [1, 2]
      [1, nil]
      [nil, nil]
      [1, 2]
      [1, nil]
      [{a: 1}, 2]
      "struct size differs"
      "unknown keywords: z"
      {x: 1, y: 2}
      "missing keyword: :y"
      "unknown keyword: :z"
      "unknown keywords: :z, :w"
      "unknown keywords: z, w"
    OUT
  end

  it "a constant assigned in a Struct.new block body is initialized" do
    result = ze0(<<~'RUBY')
      # A constant assigned inside a `Struct.new(...) do ... end` block body must be
      # initialized. register_structs consumes the block only for class/ivar/method
      # registration, never as executable statements, so such a constant stayed
      # NULL/default -- a method reading it saw an empty value (doom's Linedef
      # FLAGS[:TWOSIDED] came back nil, so every linedef read as one-sided and the
      # two-sided portal walls never rendered).
      Line = Struct.new(:flags) do
        FLAGS = {
          BLOCKING: 0x0001,
          TWOSIDED: 0x0004,
          SECRET: 0x0020
        }.freeze
        def two_sided?
          (flags & FLAGS[:TWOSIDED]) != 0
        end
        def flag(name)
          FLAGS[name]
        end
      end
      puts Line::FLAGS[:TWOSIDED]
      l = Line.new(0x0004)
      puts l.two_sided?
      puts Line.new(0x0001).two_sided?
      puts l.flag(:SECRET)
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/struct/struct_test.rb:20:in '<main>': uninitialized constant Line::FLAGS (NameError)

      puts Line::FLAGS[:TWOSIDED]
               ^^^^^^^
    ERR
  end

  it "a method defined in the block body wins over the generated one" do
    result = ze0(<<~'RUBY')
      # A method defined in a Struct.new / Data.define block overrides the built-in
      # member accessor of the same name, as it does in CRuby. `[]` written in the
      # block was ignored: the call went to the generated member lookup, so a key
      # that is not a member raised
      #
      #   NameError: no member 'text' in struct
      #
      # instead of running the user's body. The same applies to any built-in the
      # block redefines (`to_s`, `==`, ...).
      #
      # Found porting tobi/try, which wraps a Hash payload in a Data and defines
      # `[]` to forward unknown keys into that Hash.
      Item = Data.define(:data, :score) do
        def [](key)
          if key == :score
            score
          else
            data[key]
          end
        end
      end

      i = Item.new(data: { text: "hello", path: "/tmp/x" }, score: 1.5)
      p i[:score]
      p i[:text]
      p i[:path]

      # The generated readers still work alongside the override.
      p i.score
      p i.data[:text]

      # Struct.new takes the same treatment.
      Pair = Struct.new(:a, :b) do
        def [](key)
          "custom:#{key}"
        end
      end
      s = Pair.new(1, 2)
      p s[:a]
      p s[:zzz]
      p s.a
      p s.b

      # A Struct that does NOT override [] keeps the built-in member lookup,
      # including the integer-offset form and the NameError for an unknown name.
      Plain = Struct.new(:x, :y)
      pl = Plain.new(7, 8)
      p pl[:x]
      p pl[1]
      p pl[-1]
      begin
        pl[:nope]
      rescue NameError => e
        puts "NameError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      "hello"
      "/tmp/x"
      1.5
      "hello"
      "custom:a"
      "custom:zzz"
      1
      2
      7
      8
      8
      NameError: no member 'nope' in struct
    OUT
  end

  it "a Struct class answers members and keyword_init?" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:a, :b)
      p S.methods.include?(:members)
      p S.methods.include?(:keyword_init?)
      p S.members
      p S.keyword_init?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [:a, :b]
      nil
    OUT
  end

  it "each_pair yields the pair whole, and values_at pads past the last member" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:a, :b, :c)
      s = S.new(1, 2, 3)

      # each_pair yields the [name, value] PAIR, so a one-parameter block sees it
      # whole; it was yielding two values, and the 1-param form got only the name
      s.each_pair { |pair| p pair }
      s.each_pair { |k, v| p [k, v] }

      # blockless each_pair answers an Enumerator over those pairs, not LocalJumpError
      r = (s.each_pair.to_a rescue $!.class); p r
      p s.each_pair.class

      # values_at pads a Range that runs past the last member, as Array#values_at does
      T = Struct.new(:a, :b)
      p T.new(1, 2).values_at(0..5)
      p T.new(1, 2).values_at(0, 1)
      p T.new(1, 2).values_at(1)
      p [1, 2].values_at(0..5)

      # an anonymous Struct has no name
      p Struct.new(:z).name
      p S.name

      # a keyword_init Struct takes keywords and nothing else
      K = Struct.new(:a, :b, keyword_init: true)
      r = (K.new(1, 2) rescue $!.class); p r
      p K.new(a: 1, b: 2).a
      p K.keyword_init?

      # a plain Struct still takes positionals
      p S.new(1, 2, 3).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:b, 2]
      [:c, 3]
      [:a, 1]
      [:b, 2]
      [:c, 3]
      [[:a, 1], [:b, 2], [:c, 3]]
      Enumerator
      [1, 2, nil, nil, nil, nil]
      [1, 2]
      [2]
      [1, 2, nil, nil, nil, nil]
      nil
      "S"
      ArgumentError
      1
      true
      [1, 2, 3]
    OUT
  end

  it "a custom initialize sets the members through super" do
    result = ze0(<<~'RUBY')
      # A custom `initialize` in the block calls `super` (bare or explicit,
      # positional) into the synthesized member-setter, reached via a two-level
      # base/leaf hierarchy -- not the old "no initialize above" panic.

      Trip = Struct.new(:x, :y, :z) do
        def initialize(x, y)
          super
        end
      end
      p Trip.new(1, 2).to_a
      V = Struct.new(:a, :b, :c) do
        def initialize(a, b)
          super(a, b, a + b)
        end
      end
      p V.new(3, 4).to_a
    RUBY

    _(result).must_answer "[1, 2, nil]\n[3, 4, 7]\n"
  end

  it "a Struct and a Data match an array pattern and a hash pattern" do
    result = ze0(<<~'RUBY')
      # Struct and Data support pattern matching: #deconstruct (array patterns)
      # and #deconstruct_keys (hash patterns). Neither has an explicit method;
      # the compiler synthesizes the member array / member hash inline.
      S = Struct.new(:x, :y, :z)
      D = Data.define(:a, :b)

      # case/in, array pattern
      case S.new(1, 2, 3)
      in [a, b, c]
        p [a, b, c]
      end

      # case/in, hash pattern (subset of keys)
      case S.new(10, 20, 30)
      in { x:, z: }
        p [x, z]
      end

      # case/in with a trailing splat
      case S.new(1, 2, 3)
      in [first, *rest]
        p [first, rest]
      end

      # type guards inside the pattern
      case S.new(1, 2, 3)
      in [Integer => p1, Integer, Integer]
        puts p1
      end

      # Data: array + hash patterns
      case D.new(4, 5)
      in [a, b]
        p [a, b]
      end
      case D.new(6, 7)
      in { a:, b: }
        p [a, b]
      end

      # one-line rightward assignment
      S.new(8, 9, 10) => [q, r, s]
      p [q, r, s]
      D.new(11, 12) => { a:, b: }
      p [a, b]

      # non-matching arm falls through
      result =
        case S.new(1, 2, 3)
        in [0, _, _] then "zero"
        in [1, _, _] then "one"
        else "other"
        end
      puts result
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [10, 30]
      [1, [2, 3]]
      1
      [4, 5]
      [6, 7]
      [8, 9, 10]
      [11, 12]
      one
    OUT
  end

  it "values, values_at and dig, including a dig into a member that holds a Hash" do
    result = ze0(<<~'RUBY')
      # Struct: values / values_at / dig (including nested dig into a Hash)
      Point = Struct.new(:x, :y)
      p Point.new(3, 4).values
      p Point.new(3, 4).values_at(0, 1)
      p Point.new(3, 4).values_at(-1)

      Config = Struct.new(:name, :opts)
      c = Config.new("web", { port: 8080, tags: %w[a b] })
      p c.dig(:opts, :port)
      p c.dig(:name)
      p c.dig(:opts, :missing)

      # The new rows also reach a custom-initialize Struct (two-level base split).
      Measure = Struct.new(:amount, :unit) do
        def initialize(amount, unit = "kg")
          super(amount, unit)
        end
      end
      m = Measure.new(5)
      p m.values
      p m.values_at(1, 0)
      p m.dig(:unit)

      # Data still answers to_h / deconstruct_keys unchanged.
      Coord = Data.define(:lat, :lng)
      d = Coord.new(lat: 1, lng: 2)
      p d.to_h
      p d.deconstruct_keys([:lat])
      p d.deconstruct
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [3, 4]
      [4]
      8080
      "web"
      nil
      [5, "kg"]
      ["kg", 5]
      "kg"
      {lat: 1, lng: 2}
      {lat: 1}
      [1, 2]
    OUT
  end

  it "a subscript that is not a literal reads by index, counting back from the end" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # The out-of-range Struct#[] message says "too large" for a negative
      # offset; ruby says "too small".
      #
      # Struct#[] with an index that is not a literal: the member chain was emitted
      # as bare statements, so the whole read was a void expression and the C would
      # not compile. A negative offset counts from the end, and a miss raises.
      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      i = 1
      p s[i]
      k = -1
      p s[k]
      m = -9
      p((s[m] rescue $!.message))
      n = 9
      p((s[n] rescue $!.message))
      p s[0]
      p s[:a]
      j = :b
      p s[j]
      p((s[:zz] rescue $!.message))
      p s["a"]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      "offset -9 too small for struct(size:2)"
      "offset 9 too large for struct(size:2)"
      1
      1
      2
      "no member 'zz' in struct"
      1
    OUT
  end

  it "a Struct built with no arguments reads nil at every member" do
    result = ze0(<<~'RUBY')
      Rec = Struct.new(:id, :name)

      full = Rec.new(1, "alice")
      puts full.id
      puts full.name

      empty = Rec.new
      puts empty.id.nil?
      puts empty.name.nil?

      empty.id = 7
      empty.name = "bob"
      puts empty.id
      puts empty.name
    RUBY

    _(result).must_answer <<~'OUT'
      1
      alice
      true
      true
      7
      bob
    OUT
  end

  it "the call's shape decides whether a trailing Hash is keywords or a member" do
    result = ze0(<<~'RUBY')
      # KEYWORDS to a Struct constructor build the wrong instance. A Struct
      # declared WITHOUT `keyword_init:` still accepts keywords -- ruby decides by
      # whether the CALLER passed keywords, not by how the class was declared --
      # and zeo takes the trailing Hash as the first member's value instead:
      #
      #     Pair.new(a: 1)   ruby #<struct Pair a=1, b=nil>
      #                      zeo  #<struct Pair a={a: 1}, b=nil>
      #
      # `bind_members` decides from the argument shape plus the declared
      # `keyword_init`, because the keyword-vs-positional-Hash flag ruby reads
      # (`rb_keyword_given_p`) does not reach a builtin row. A real positional Hash
      # must keep working, which is why the shape alone cannot settle it; the flag
      # has to travel. Same root cause as
      # `tests/gaps/keyword_given_flag_does_not_travel.rb`.
      #
      # `keyword_init: true` is unaffected (it decides from the declaration). The
      # arity-message half of the old combined gap lives in
      # `struct_size_differs_on_the_compiled_path.rb`.

      Pair = Struct.new(:a, :b)

      p Pair.new(a: 1)
      p Pair.new(a: 1, b: 2)
      p Pair.new({ a: 1 })

      kw = Struct.new(:a, :b, keyword_init: true)
      p kw.new(a: 1)
      begin
        kw.new(1)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct Pair a=1, b=nil>
      #<struct Pair a=1, b=2>
      #<struct Pair a={a: 1}, b=nil>
      #<struct a=1, b=nil>
      ArgumentError: wrong number of arguments (given 1, expected 0)
    OUT
  end

  it "a keyword_init Struct takes its members by name" do
    result = ze0(<<~'RUBY')
      # Test Struct with keyword_init

      Session = Struct.new(
        :pid, :name, :status,
        keyword_init: true
      )

      s = Session.new(pid: 123, name: "test", status: "running")
      puts s.pid     # 123
      puts s.name    # test
      puts s.status  # running

      s.status = "done"
      puts s.status  # done

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      123
      test
      running
      done
      done
    OUT
  end

  it "a Struct class held in a local types its members the same as one in a constant" do
    result = ze0(<<~'RUBY')
      # A Struct held in a local is the same class as one held in a constant, so its
      # construction types the members the same way. It used to leave every member
      # poly, which put each field read and the arithmetic on it through the boxed
      # path even when every construction passed the same scalar type.
      st = Struct.new :x, :y
      a = st.new(1.5, 2.5)
      b = st.new(0.5, 4.0)
      p [a.x - a.y, b.x + b.y]
      p [a.x.class, a.y.class]

      pt = Struct.new :name, :count
      q = pt.new("a", 2)
      p [q.name * q.count, q.count + 1]

      # a member left unsupplied is nil, which keeps the member wide
      part = Struct.new :a, :b
      r = part.new(1)
      p [r.a, r.b]

      # assignment through the writer still lands
      w = st.new(1.0, 2.0)
      w.x = 9.5
      p w.x + w.y
      p w.to_a
      p w == st.new(9.5, 2.0)
    RUBY

    _(result).must_answer <<~'OUT'
      [-1.0, 4.5]
      [Float, Float]
      ["aa", 3]
      [1, nil]
      11.5
      [9.5, 2.0]
      true
    OUT
  end

  it "a local reassigned to a second anonymous Struct class dispatches at run time" do
    result = ze0(<<~'RUBY')
      # A local holding an anonymous Struct class, reassigned to a SECOND one. No
      # single class resolves for it any more, so `s.new` dispatches at run time --
      # and the switch had no arm for a Struct at all, so the call answered nil.
      # The write that followed then took the nil box's cls_id, which is 0, as a real
      # class id and stored through its NULL pointer: a segfault, and the program
      # printed nothing (#4048).
      s = Struct.new :a
      x = s.new
      x.a = 0
      s = Struct.new
      puts "OK"
      p x.a

      t = Struct.new(:a)
      y = t.new
      y.a = 7
      t = Struct.new(:b)
      z = t.new
      z.b = 9
      p [y.a, z.b]

      # a nil receiver for a member write is a NoMethodError, not a crash
      begin
        n = [nil, Struct.new(:a).new(1)][0]
        n.a = 5
      rescue NoMethodError => e
        p e.class
      end

      # the single-class local, unchanged
      u = Struct.new(:a)
      w = u.new
      w.a = 3
      p w.a
      p u.new.a

      # and the constant spelling
      S = Struct.new(:a, :b)
      p S.new.to_a
      p S.new(1, 2).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      OK
      0
      [7, 9]
      NoMethodError
      3
      nil
      [nil, nil]
      [1, 2]
    OUT
  end

  it "a member value built in argument position survives until the constructor stores it" do
    result = ze0(<<~'RUBY')
      # A Struct member value built in argument position had to survive until the
      # constructor stored it. The constructor roots its parameters on entry, but that
      # is already too late: a sibling member expression can collect while the call's
      # arguments are still being evaluated, and C leaves the order among them
      # unspecified, so whichever fresh member is evaluated before the allocating one
      # was freed and the constructor stored a dangling pointer (#4049). Members are
      # placed on both sides of the allocating one so the shape is exercised whichever
      # order the C compiler picks.
      Inner = Struct.new(:n)
      Tri = Struct.new(:head, :bulk, :tail)

      def churn(i)
        ls = []
        60.times { |j| ls.push("line #{i} #{j} ......................") }
        GC.start
        ls.join("\n")
      end

      built = []
      40.times { |i| built.push(Tri.new(Inner.new(i), churn(i), "t#{i}")) }
      bad_head = 0
      bad_tail = 0
      built.each_with_index do |o, i|
        bad_head += 1 if o.head.n != i
        bad_tail += 1 if o.tail != "t#{i}"
      end
      p bad_head
      p bad_tail

      # The same for a Data instance, which shares the constructor emitter.
      Pair = Data.define(:name, :bulk)
      pairs = []
      40.times { |i| pairs.push(Pair.new("n#{i}", churn(i))) }
      p pairs.each_with_index.count { |d, i| d.name != "n#{i}" }
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
    OUT
  end

  it "a subscript takes an index, a name or a string, and raises for a member that is not there" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      i = 1
      s[i] = 9
      p s.b
      r = (begin; s[9] = 1; "no error"; rescue => e; e.class; end); p r
      r2 = (begin; p s[9]; rescue => e; p e.class; end)
      r3 = (begin; p s[:zz]; rescue => e; p e.class; end)
      p s["a"]
      p s.values_at
      k = :b
      p s.dig(k)
      r4 = (begin; p s.values_at(k); rescue => e; p e.class; end)
      s[:a] = 5
      p s.a
      s["b"] = 6
      p s.b
      p s.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      9
      IndexError
      IndexError
      NameError
      1
      []
      9
      TypeError
      5
      6
      [5, 6]
    OUT
  end

  it "a member reader wins over a same-named String method through a block parameter" do
    result = ze0(<<~'RUBY')
      # A Struct / Data / attr_accessor read inside a block, where the receiver is a
      # poly array element: the member must win over a same-named String method, and
      # #[] must reach the member table.
      E = Struct.new(:ip, :ms)
      [E.new("a", 10)].each { |e| p e[:ms] }
      [E.new("a", 10)].each { |e| p e["ms"] }
      [E.new("a", 10)].each { |e| p e[1] }
      [E.new("a", 10)].each { |e| p e[0] }
      [E.new("a", 10)].each { |e| p e[-1] }
      [E.new("a", 10)].each { |e| p e.ms }

      # a reader named after a String method
      S = Struct.new(:ip, :bytes)
      [S.new("a", 10)].each { |e| p e.bytes }
      class K
        attr_accessor :ip, :bytes, :chars
        def initialize(a, b, ch); @ip = a; @bytes = b; @chars = ch; end
      end
      [K.new("a", 10, 7)].each { |e| p e.bytes }
      [K.new("a", 10, 7)].each { |e| p e.chars }

      # a real String in a poly slot still gets String#bytes
      p ["ab"].map { |s| s.bytes }
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      10
      "a"
      10
      10
      10
      10
      7
      [[97, 98]]
    OUT
  end

  it "a member is not an instance variable of the same name" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:a, :b)
      class S
        def peek = @a
        def poke = @a = 99
      end
      s = S.new(1, 2)
      p s.peek
      p s.instance_variables
      s.poke
      p [s.a, s.instance_variables, s.instance_variable_get(:@a)]
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      []
      [1, [:@a], 99]
    OUT
  end

  it "a member name does not merge types with an unrelated method of that name" do
    result = ze0(<<~'RUBY')
      # A Struct member name must not globally type-merge with an unrelated
      # method of the same name. Here Struct member `b` (an Integer) shares
      # its name with Weight#b (a Float array); the int use through an
      # unresolved receiver must stay Integer, not get widened to FloatArray.
      class Weight
        def initialize
          @v = [1.0, 2.0, 3.0]
        end
        def b
          @v
        end
      end
      Ctx = Struct.new(:t, :b)
      def sum_to(batch)
        r = batch % 7
        i = 0
        s = 0
        while i < batch
          s = s + i
          i = i + 1
        end
        s + r
      end
      w = Weight.new
      puts w.b.length
      ctx = Ctx.new(3, 5)
      puts sum_to(ctx.b)
      puts sum_to(10)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      15
      48
    OUT
  end

  it "Struct.[], a negative-index write, entries, reverse_each, compact and each_with_index" do
    result = ze0(<<~'RUBY')
      # Struct method surface (#2488-2491, #2506, #2534-2539)
      S = Struct.new(:a, :b, :c)
      p(S[10, 20, 30])                 # 2488 Struct.[]
      s = S.new(1, 2, 3)
      s[-1] = 99                       # 2489 []= negative index
      p(s.c)
      p(s.entries)                     # 2490
      s.reverse_each { |x| print x }; puts   # 2491
      r = s.each_with_index { |x, i| }       # 2506 returns receiver
      p(r == s)
      p(s.compact)                     # 2538
      S2 = Struct.new(:a, keyword_init: true)
      p(S2.keyword_init?)              # 2534
      p(S.keyword_init?)
      p(s.chain([4, 5]).to_a)          # 2535
      t = S.new(1, 1, 2)
      p(t.slice_before { |x| x == 1 }.to_a)  # 2536
      p(t.slice_after { |x| x == 1 }.to_a)
      e = s.each_entry                 # 2537 blockless -> Enumerator
      p(e.to_a)
      require "set"
      p(s.to_set)                      # 2539
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct S a=10, b=20, c=30>
      99
      [1, 2, 99]
      9921
      true
      [1, 2, 99]
      true
      nil
      [1, 2, 99, 4, 5]
      [[1], [1, 2]]
      [[1], [1], [2]]
      [1, 2, 99]
      Set[1, 2, 99]
    OUT
  end

  it "Struct.new with a leading name defines the class under Struct" do
    result = ze0(<<~'RUBY')
      Struct.new("Named", :a)
      p Struct::Named.new(1).a
      p Struct::Named.name
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "Struct::Named"
    OUT
  end

  it "keyword_init? is true, false or nil, and a Struct equals itself" do
    result = ze0(<<~'RUBY')
      # `s == s` must not deadlock: comparing a struct to itself used to lock the
      # same slots Mutex twice and hang. `keyword_init?` is tri-state, matching
      # CRuby -- `nil` when never specified, else the boolean passed.

      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      p(s == s)
      p(s == S.new(1, 2))
      p(s == S.new(1, 9))
      p S.keyword_init?
      p Struct.new(:a, keyword_init: true).keyword_init?
      p Struct.new(:a, keyword_init: false).keyword_init?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      nil
      true
      false
    OUT
  end

  it "too many arguments raises, where too few fill with nil" do
    result = ze0(<<~'RUBY')
      # TOO MANY POSITIONALS to a Struct constructor say `struct size differs` on
      # BOTH paths: the compiled constant-assigned form (which once reported a
      # generic arity range -- fixed) and the runtime-minted form. The keyword half
      # lives in `struct_keywords_by_call_shape.rb`.

      Pair = Struct.new(:a, :b)

      begin
        Pair.new(1, 2, 3)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      anon = Struct.new(:a, :b)
      begin
        anon.new(1, 2, 3)
      rescue ArgumentError => e
        puts "#{e.class}: #{e.message}"
      end

      # These already agree and must not move.
      p [Pair.new(1), Pair.new, Pair.new(1, 2)]
      p Pair.new(1, 2).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: struct size differs
      ArgumentError: struct size differs
      [#<struct Pair a=1, b=nil>, #<struct Pair a=nil, b=nil>, #<struct Pair a=1, b=2>]
      [1, 2]
    OUT
  end

  it "two Structs are equal when their class and every member match" do
    result = ze0(<<~'RUBY')
      # Struct instances compare by member value (identity was compared before);
      # a string/array member compares by content, and eql? follows ==.
      S = Struct.new(:a, :b)
      p(S.new(1, 2) == S.new(1, 2))
      p(S.new(1, 2) == S.new(1, 3))
      x = S.new(5, 6)
      p(x == S.new(5, 6))
      p(x != S.new(5, 6))
      p(x.eql?(S.new(5, 6)))
      T = Struct.new(:name, :tags)
      p(T.new("a", [1, 2]) == T.new("a", [1, 2]))
      p(T.new("a", [1, 2]) == T.new("a", [1, 3]))
      p(T.new("a", [1]) == T.new("b", [1]))
      p(S.new(1, 2).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      true
      false
      false
      [1, 2]
    OUT
  end

  it "a custom initialize that yields runs its block during construction" do
    result = ze0(<<~'RUBY')
      # A custom initialize that calls its block (yield / block_given? / a called
      # &blk) runs its body during construction. For a Struct/Data value class this
      # body was previously skipped -- the members were set member-wise from the raw
      # args, dropping the block. It now runs inlined at the .new site, so the block
      # drives the member values via super. Args are routed through a method so the
      # values are not constant-folded at the call site.

      Scaled = Struct.new(:a, :b) do
        def initialize(a, b)
          super(yield(a), b * 10)
        end
      end

      def make_scaled(a, b)
        Scaled.new(a, b) { |n| n * 3 }
      end

      s = make_scaled(5, 2)
      p [s.a, s.b]

      # A keyword-parameter yielding initialize (here on a plain class) binds each
      # keyword param by name inside the inlined body -- not positionally, which
      # would drop the whole keyword hash into the first param.
      class Box
        def initialize(x:, y: 10)
          @v = yield(x) + y
        end
        def v = @v
      end

      def make_box(a)
        Box.new(x: a) { |n| n * 2 }
      end

      p make_box(5).v
      p make_box(9).v

      # block_given? inside a Struct initialize still constructs without a block.
      Maybe = Struct.new(:n) do
        def initialize(n)
          super(block_given? ? yield(n) : n)
        end
      end

      p Maybe.new(4) { |x| x + 100 }.n
      p Maybe.new(7).n
    RUBY

    _(result).must_answer <<~'OUT'
      [15, 20]
      20
      28
      104
      7
    OUT
  end

  it "structs" do
    result = ze0(<<~'RUBY')
      # Phase 17.1 -- Struct: compile-time class synthesis. `Point = Struct.new`
      # becomes an ordinary `class Point < Struct` (accessors, initialize,
      # members/to_a/to_h/==/[]/each_pair, Enumerable via the real chain), with
      # keyword_init and block-with-methods forms.

      Point = Struct.new(:x, :y)

      pt = Point.new(3, 4)
      p pt
      puts pt.x
      pt.y = 9
      p pt.to_a
      p pt.to_h
      p pt.members
      p pt == Point.new(3, 9)
      p pt[0]
      p pt[:y]
      pt[1] = 12
      p pt.y
      p pt.map { |v| v * 2 }
      pt.each_pair { |k, v| puts "#{k}=#{v}" }
      p Point.ancestors.include?(Struct)

      Label = Struct.new(:text, :size, keyword_init: true)
      l = Label.new(text: "hi", size: 12)
      p l
      puts l.text

      Vec2 = Struct.new(:dx, :dy) do
        def norm
          Math.sqrt(dx * dx + dy * dy)
        end
      end
      puts Vec2.new(3, 4).norm
      p Point.new(1).y
    RUBY

    _(result).must_answer <<~'OUT'
      #<struct Point x=3, y=4>
      3
      [3, 9]
      {x: 3, y: 9}
      [:x, :y]
      true
      3
      9
      12
      [6, 24]
      x=3
      y=12
      true
      #<struct Label text="hi", size=12>
      hi
      5.0
      nil
    OUT
  end

  it "to enum works on user classes and structs" do
    result = ze0(<<~'RUBY')
      # `to_enum`/`enum_for` on a user class -- the real-Ruby
      # `return to_enum(:each) unless block_given?` pattern -- and the
      # synthesized Struct `each` using exactly that pattern.

      class Deck
        include Enumerable
        def initialize(cards)
          @cards = cards
        end
        def each
          return to_enum(:each) unless block_given?
          i = 0
          while i < @cards.length
            yield @cards[i]
            i += 1
          end
          self
        end
      end
      d = Deck.new([5, 3, 9])
      e = d.each
      p e.class
      p e.next
      p d.each.sort
      p d.map.with_index { |c, i| "#{i}:#{c}" }
      p 7.to_enum(:upto, 9).to_a
      P17 = Struct.new(:x, :y)
      pt = P17.new(1, 2)
      en = pt.each
      p en.class
      p en.next
      p en.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      5
      [3, 5, 9]
      ["0:5", "1:3", "2:9"]
      [7, 8, 9]
      Enumerator
      1
      [1, 2]
    OUT
  end
end
