# frozen_string_literal: true

require "spec_helper"

describe "Struct: inheritance and ancestors" do
  it "anonymous struct and data custom initialize super" do
    result = ze0(<<~'RUBY')
      # #192 feature (1): a `super` inside a method defined in a NON-const
      # `Struct.new`/`Data.define` block resolves through the runtime method-frame
      # stack into the native member-binding `initialize`, where previously it
      # panicked "`super` outside a method" at codegen. Bare (zsuper) and explicit
      # positional forms, plus the keyword form for Data.

      pair = Struct.new(:x, :y) do
        def initialize(x)
          super(x, x * 2)
        end
      end
      p pair.new(5).to_a

      echo = Struct.new(:a, :b) do
        def initialize(a, b)
          super
        end
      end
      p echo.new(1, 2).to_a

      coord = Data.define(:lat, :lng) do
        def initialize(lat:, lng:)
          super(lat: lat * 10, lng: lng)
        end
      end
      p coord.new(lat: 1, lng: 2)
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 10]
      [1, 2]
      #<data lat=10, lng=2>
    OUT
  end

  it "anonymous subclass of a compiled struct reads nil" do
    result = ze0(<<~'RUBY')
      S1 = Struct.new(:a, :b)
      K = Class.new(S1)
      o = K.new(1, 2)
      p [o.a, o.b, o.to_a]
      class L < S1; end
      p [L.new(3, 4).a, L.new(3, 4).to_a]
      o.a = 9
      p [o.a, o[:a], o.to_a]
      p Class.new(K).new(7, 8).a
      M = Class.new(S1) do
        def sum = a + b
      end
      p [M.new(2, 3).sum, M.new(2, 3).a]
      KI = Struct.new(:x, :y, keyword_init: true)
      p Class.new(KI).new(x: 1, y: 2).x
      D1 = Data.define(:p, :q)
      p Class.new(D1).new(p: 1, q: 2).p
      p Class.new(Struct.new(:z)).new(6).z
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, [1, 2]]
      [3, [3, 4]]
      [9, 9, [9, 2]]
      7
      [5, 2]
      1
      1
      6
    OUT
  end

  it "data custom initialize supers with keyword args" do
    result = ze0(<<~'RUBY')
      # an explicit keyword `super(x: .., y: ..)` binds the parent's
      # keyword params by name; omitting a required one raises CRuby's
      # `missing keyword` ArgumentError.

      Point = Data.define(:x, :y) do
        def initialize(x:, y:)
          super(x: x * 100, y: y + 1)
        end
      end
      def mk(a, b); Point.new(x: a, y: b); end
      p mk(5, 2)
      Pair = Data.define(:m, :n) do
        def initialize(m:, n:)
          super(m: m)
        end
      end
      begin
        Pair.new(m: 1, n: 2)
      rescue ArgumentError => e
        puts "err: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Point x=500, y=3>
      err: missing keyword: :n
    OUT
  end

  it "data super kwarg" do
    result = ze0(<<~'RUBY')
      # A custom initialize on a Data/Struct value class delegates to super to set
      # the members. Data passes its members as keywords (super(x: ..., y: ...)),
      # which must map each member by name -- not positionally, which would drop the
      # whole keyword hash into the first member's slot. Args are routed through a
      # method so the values are not constant-folded at the call site.

      Point = Data.define(:x, :y) do
        def initialize(x:, y:)
          super(x: x * 100, y: y + 1)
        end
      end

      def make_point(a, b)
        Point.new(x: a, y: b)
      end

      p make_point(5, 2)
      p make_point(3, 7)

      # Struct with a positional super still assigns members positionally.
      Tally = Struct.new(:a, :b) do
        def initialize(a, b)
          super(a * 2, b * 3)
        end
      end

      def make_tally(a, b)
        Tally.new(a, b)
      end

      t = make_tally(4, 5)
      p [t.a, t.b]

      # A keyword super that omits a member raises ArgumentError, as in CRuby.
      Pair = Data.define(:m, :n) do
        def initialize(m:, n:)
          super(m: m)
        end
      end

      begin
        Pair.new(m: 1, n: 2)
      rescue ArgumentError => e
        puts "error: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Point x=500, y=3>
      #<data Point x=300, y=8>
      [8, 15]
      error: missing keyword: :n
    OUT
  end

  it "nested data reopen keeps the outer super" do
    result = ze0(<<~'RUBY')
      # A Data reopen whose body holds ANOTHER Data class with its own
      # `initialize`/`super`. The nested `class Particle` is what pushed the outer
      # reopen onto the static path, and the outer `super` then reached
      # `Object#initialize`: "wrong number of arguments (given 1, expected 0)".
      # Sow's `lib/sow/particles.rb` is exactly this shape.

      module Sow
        Particles = Data.define(:max, :live)
        class Particles
          def initialize(max: 256, live: [])
            super(max: max, live: live.freeze)
          end

          Particle = Data.define(:x, :age)
          class Particle
            def initialize(x:, age: 0.0)
              super(x: x.to_f, age: age.to_f)
            end
          end
        end
      end
      p Sow::Particles.new(max: 320)
      p Sow::Particles.new.live.frozen?
      p Sow::Particles::Particle.new(x: 1)
      p Sow::Particles::Particle.new(x: 1, age: 2).age
    RUBY

    _(result).must_answer <<~'OUT'
      #<data Sow::Particles max=320, live=[]>
      true
      #<data Sow::Particles::Particle x=1.0, age=0.0>
      2.0
    OUT
  end

  it "struct bare super initialize" do
    result = ze0(<<~'RUBY')
      # A bare `super` (no parens) inside a Struct's custom initialize forwards the
      # method's own params into the members -- it must not leave them nil.
      Pair = Struct.new(:a, :b) do
        def initialize(a, b)
          super
        end
      end
      p = Pair.new(3, 4)
      puts [p.a, p.b].inspect

      # Bare super still forwards when the params are recomputed before the call and
      # when member types are mixed (int + string).
      Rec = Struct.new(:n, :label) do
        def initialize(n, label)
          n = n * 10
          super
        end
      end
      r = Rec.new(2, "hi")
      puts [r.n, r.label].inspect

      # Fewer forwarded params than members: the rest stay nil (Struct semantics).
      Trip = Struct.new(:x, :y, :z) do
        def initialize(x, y)
          super
        end
      end
      t = Trip.new(1, 2)
      puts [t.x, t.y, t.z].inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [20, "hi"]
      [1, 2, nil]
    OUT
  end

  it "struct constructor frame names the subclass" do
    result = ze0(<<~'RUBY', path: "core/struct/a_struct_constructor_frame_names_the_subclass.rb")
      # A `Data` subclass's constructor reports the two frames ruby reports, and its
      # `Struct` twin still reports its one.
      #
      # It was two bugs, and the Struct half being right all along is what narrowed
      # both.
      #
      # THE BODY'S LABEL said `Object#initialize`. A `def` inside a class whose
      # superclass is a RUNTIME value (`D = Data.define(:m)`) is lifted to a
      # top-level method and installed on the class afterwards, so the emitter bakes
      # the only owner it can see. Ruby names the frame from the class's name AT
      # RAISE TIME, which is not a compile-time fact at all -- the same anonymous
      # class reports a bare `initialize` while held in a local and `K#initialize`
      # once a constant assignment names it. So the INSTALLER, which knows the real
      # class, hands the label to the next frame push.
      #
      # That handover is one-shot and replaces only the `Object#` fallback. Both
      # narrowings are load-bearing: a top-level `def foo` called from inside such a
      # method must keep its own label, and the same install path also carries a
      # genuine `define_method` block, whose body keeps its `block in ...` label
      # (`tests/define_method_body_frame_label.rb` caught that one).
      #
      # THE `D.new` FRAME was missing. Ruby pushes one because a Data class's `new`
      # is a distinct cfunc -- the one that zips positionals against the member list
      # -- where `Struct`'s is the ordinary `Class#new` and pushes none. The label
      # names the class that OWNS the cfunc, so a subclass of `D` still reports
      # `D.new` rather than its own name.
      D = Data.define(:m)

      class D2 < D
        def initialize(**kw)
          super
          @z = 1
        end
      end

      begin
        D2.new(m: 1)
      rescue => e
        puts e.backtrace.first(2).map { |l| l.sub(/\A.*?([^\/]+\.rb)/, '\1') }
      end

      S = Struct.new(:a)
      class S2 < S
        def initialize(*args)
          super
          raise "from the subclass"
        end
      end
      begin
        S2.new(1)
      rescue => e
        puts e.backtrace.first(2).map { |l| l.sub(/\A.*?([^\/]+\.rb)/, '\1') }
      end

      # The sweep.

      def frames(label, n = 2)
        yield
      rescue => e
        puts "#{label}:"
        puts e.backtrace.first(n).map { |l| "  " + l.sub(%r{\A.*?([^/]+):}, '\1:') }
      end

      # A subclass of the Data subclass still names the class that owns `new`.
      class D3 < D2
        def initialize(**kw)
          super
          raise "deeper"
        end
      end
      frames("Data sub-subclass") { D3.new(m: 1) }

      # A Data class constructed DIRECTLY, with no subclass in between.
      DD = Data.define(:v)
      frames("Data direct, arity error") { DD.new(1, 2, 3) }

      # A named runtime class reports its constant name; the SAME class held in a
      # local stays anonymous and reports the bare method name.
      Named = Class.new do
        def boom
          raise "named"
        end
      end
      frames("named runtime class", 1) { Named.new.boom }

      anon = Class.new do
        def boom
          raise "anon"
        end
      end
      frames("anonymous runtime class", 1) { anon.new.boom }

      # A subclass of a runtime class, written with `class ... < ...`.
      class NamedSub < Named
        def other
          raise "sub"
        end
      end
      frames("subclass of a runtime class", 1) { NamedSub.new.other }

      # The one-shot must not leak: a top-level `def` called from inside a runtime
      # class's method keeps its OWN label.
      def top_level_helper
        raise "helper"
      end
      Leaky = Class.new do
        def outer
          top_level_helper
        end
      end
      frames("top-level def called from a runtime method") { Leaky.new.outer }
    RUBY

    _(result).must_answer "a_struct_constructor_frame_names_the_subclass.rb:32:in 'D2#initialize'\na_struct_constructor_frame_names_the_subclass.rb:37:in 'D.new'\na_struct_constructor_frame_names_the_subclass.rb:46:in 'S2#initialize'\na_struct_constructor_frame_names_the_subclass.rb:50:in '<main>'\nData sub-subclass:\n  a_struct_constructor_frame_names_the_subclass.rb:32:in 'D2#initialize'\n  a_struct_constructor_frame_names_the_subclass.rb:67:in 'D3#initialize'\nData direct, arity error:\n  a_struct_constructor_frame_names_the_subclass.rb:75:in 'DD.new'\n  a_struct_constructor_frame_names_the_subclass.rb:75:in 'block in <main>'\nnamed runtime class:\n  a_struct_constructor_frame_names_the_subclass.rb:81:in 'Named#boom'\nanonymous runtime class:\n  a_struct_constructor_frame_names_the_subclass.rb:88:in 'boom'\nsubclass of a runtime class:\n  a_struct_constructor_frame_names_the_subclass.rb:96:in 'NamedSub#other'\ntop-level def called from a runtime method:\n  a_struct_constructor_frame_names_the_subclass.rb:104:in 'Object#top_level_helper'\n  a_struct_constructor_frame_names_the_subclass.rb:108:in 'Leaky#outer'\n"
  end

  it "struct custom initialize super" do
    result = ze0(<<~'RUBY')
      # A Struct with a custom initialize that calls super(...) must set every member
      # via super, including computed (Array) args -- not leave them nil.
      SW = 4
      V = Struct.new(:a, :b, :top, :bottom, :minx, :maxx) do
        def initialize(a, b)
          super(a, b, Array.new(SW, 100), Array.new(SW, -1), SW, -1)
        end
        def mark(x, y1)
          top[x] = [top[x], y1].min
          bottom[x] = [bottom[x], y1].max
        end
      end
      v = V.new(1, 2)
      puts [v.a, v.b, v.minx, v.maxx].inspect
      puts v.top.inspect
      puts v.bottom.inspect
      v.mark(0, 50)
      puts v.top.inspect
      puts v.bottom.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 4, -1]
      [100, 100, 100, 100]
      [-1, -1, -1, -1]
      [50, 100, 100, 100]
      [50, -1, -1, -1]
    OUT
  end

  it "struct inherit" do
    result = ze0(<<~'RUBY')
      class Point < Struct.new(:x, :y, keyword_init: true)
        def distance
          (x * x + y * y)
        end

        def to_s
          "(#{x}, #{y})"
        end
      end

      p1 = Point.new(x: 3, y: 4)
      puts p1.x         # 3
      puts p1.y         # 4
      puts p1.distance  # 25
      p1.x = 10
      puts p1.x         # 10

      class Entry < Struct.new(:name, :value, keyword_init: true)
        def display
          "#{name}=#{value}"
        end
      end

      e = Entry.new(name: "foo", value: 42)
      puts e.name    # foo
      puts e.value   # 42

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      25
      10
      foo
      42
      done
    OUT
  end

  it "struct subclass" do
    result = ze0(<<~'RUBY')
      # `class Kid < Base` where Base is a Struct. The subclass is registered before
      # the anonymous Struct it inherits from, and the member merge ran strictly in
      # index order, so the subclass came out with no members at all -- its methods
      # read fields the struct did not have. A Struct subclass is a Struct: it keeps
      # the members, the positional constructor and the member face.
      Base = Struct.new(:a, :b)
      class Kid < Base
        def total = a + b
      end
      k = Kid.new(1, 2)
      p k.total
      p k.a
      p k.b
      p k.to_a
      p k.members
      p k.to_h
      p k == Kid.new(1, 2)
      p Kid.new(1, 2).inspect
      p k[0]
      p k.class

      class Named < Struct.new(:x)
        def double = x * 2
      end
      n = Named.new(4)
      p n.double
      p n.x
      p n.to_a

      # the plain Struct is unchanged
      p Base.new(5, 6).a
      p Base.new(5, 6).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      2
      [1, 2]
      [:a, :b]
      {a: 1, b: 2}
      true
      "#<struct Kid a=1, b=2>"
      1
      Kid
      8
      4
      [4]
      5
      [5, 6]
    OUT
  end

  it "struct subclass keeps its own ivars" do
    result = ze0(<<~'RUBY')
      # A subclass of a Struct inherits the member list, so an instance of it has to
      # hold BOTH its ancestor's members and its own instance variables -- and the
      # ancestor's compiled body addresses a member by slot index, so the two must
      # not land on the same slot.
      #
      # They did. Members were laid out after the declared ivars, and a subclass
      # declaring one of its own pushed them along: `@p` took slot 0, which is where
      # the struct's `initialize` writes member 0. `super` then wrote the member's
      # value into `@p`, and reading the member answered nil. rspec's
      # `FailedExampleNotification` is the shape -- a `Struct.new(:example)`
      # subclass whose `initialize` sets `@exception_presenter` and calls
      # `super(example)` -- and it reported the example where the presenter belonged.
      #
      # Members now occupy the FIRST slots, which every descendant agrees on.

      Base = Struct.new(:example)

      class Sub < Base
        def initialize(example, presenter = "P<#{example}>")
          @presenter = presenter
          super(example)
        end
        def show = [@presenter, example, to_a]
      end

      s = Sub.new("ex")
      p s.show
      p s.instance_variables
      p s
      p Sub.new("ex", "given").show

      # Two of its own, and a write through the member accessor afterwards.
      class Two < Base
        def initialize(a, b)
          @a = a
          @b = b
          super("m")
        end
        def show = [@a, @b, example]
      end
      t = Two.new(1, 2)
      p t.show
      t.example = "changed"
      p t.show
      p t.instance_variables

      # A deeper subclass adds a third ivar without moving the member again.
      class Three < Two
        def initialize
          super(10, 20)
          @c = 30
        end
        def show3 = [@a, @b, @c, example]
      end
      p Three.new.show3
      p Three.new.instance_variables

      # The struct's own reflection still reports members, not ivars.
      p Sub.members
      p Sub.new("z").to_h
    RUBY

    _(result).must_answer <<~'OUT'
      ["P<ex>", "ex", ["ex"]]
      [:@presenter]
      #<struct Sub example="ex">
      ["given", "ex", ["ex"]]
      [1, 2, "m"]
      [1, 2, "changed"]
      [:@a, :@b]
      [10, 20, 30, "m"]
      [:@a, :@b, :@c]
      [:example]
      {example: "z"}
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of Struct's own methods its methods call on a subclass: every
      # method Struct defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      class Probe < Struct.new(:a, :b)
        CALLING = []
        LOG = []
        [:==, :[], :[]=, :all?, :any?, :chain, :chunk, :chunk_while, :collect, :collect_concat, :compact, :count, :cycle, :deconstruct, :deconstruct_keys, :detect, :dig, :drop, :drop_while, :each, :each_cons, :each_entry, :each_pair, :each_slice, :each_with_index, :each_with_object, :entries, :eql?, :filter, :filter_map, :find, :find_all, :find_index, :first, :flat_map, :grep, :grep_v, :group_by, :hash, :include?, :initialize_copy, :inject, :inspect, :lazy, :length, :map, :max, :max_by, :member?, :members, :min, :min_by, :minmax, :minmax_by, :none?, :one?, :partition, :reduce, :reject, :reverse_each, :select, :size, :slice_after, :slice_before, :slice_when, :sort, :sort_by, :sum, :take, :take_while, :tally, :to_a, :to_h, :to_s, :to_set, :uniq, :values, :values_at, :zip].each do |m|
          define_method(m) do |*args, &blk|
            LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
            CALLING << m
            begin
              super(*args, &blk)
            ensure
              CALLING.pop
            end
          end
          ruby2_keywords(m)
        end
      end

      def call(name)
        r = Probe.new(1, 2)
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
      call("[]=") { |r| r.__send__(:[]=, 0, 1) { |*x| x.first } }
      call("all?") { |r| r.all?() { |*x| x.first } }
      call("any?") { |r| r.any?() { |*x| x.first } }
      call("chain") { |r| r.chain() { |*x| x.first } }
      call("chunk") { |r| r.chunk() { |*x| x.first } }
      call("chunk_while") { |r| r.chunk_while() { |*x| x.first } }
      call("collect") { |r| r.collect() { |*x| x.first } }
      call("collect_concat") { |r| r.collect_concat() { |*x| x.first } }
      call("compact") { |r| r.compact() { |*x| x.first } }
      call("count") { |r| r.count() { |*x| x.first } }
      call("deconstruct") { |r| r.deconstruct() { |*x| x.first } }
      call("deconstruct_keys") { |r| r.deconstruct_keys([1, 2]) { |*x| x.first } }
      call("detect") { |r| r.detect() { |*x| x.first } }
      call("dig") { |r| r.dig(1) { |*x| x.first } }
      call("drop") { |r| r.drop(1) { |*x| x.first } }
      call("drop_while") { |r| r.drop_while() { |*x| x.first } }
      call("each") { |r| r.each() { |*x| x.first } }
      call("each_cons") { |r| r.each_cons(1) { |*x| x.first } }
      call("each_entry") { |r| r.each_entry() { |*x| x.first } }
      call("each_pair") { |r| r.each_pair() { |*x| x.first } }
      call("each_slice") { |r| r.each_slice(1) { |*x| x.first } }
      call("each_with_index") { |r| r.each_with_index() { |*x| x.first } }
      call("each_with_object") { |r| r.each_with_object(1) { |*x| x.first } }
      call("entries") { |r| r.entries() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("filter") { |r| r.filter() { |*x| x.first } }
      call("filter_map") { |r| r.filter_map() { |*x| x.first } }
      call("find") { |r| r.find() { |*x| x.first } }
      call("find_all") { |r| r.find_all() { |*x| x.first } }
      call("find_index") { |r| r.find_index() { |*x| x.first } }
      call("first") { |r| r.first() { |*x| x.first } }
      call("flat_map") { |r| r.flat_map() { |*x| x.first } }
      call("grep") { |r| r.grep(1) { |*x| x.first } }
      call("grep_v") { |r| r.grep_v(1) { |*x| x.first } }
      call("group_by") { |r| r.group_by() { |*x| x.first } }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("include?") { |r| r.include?(1) { |*x| x.first } }
      call("inject") { |r| r.inject() { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("lazy") { |r| r.lazy() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("map") { |r| r.map() { |*x| x.first } }
      call("max") { |r| r.max() { |*x| x.first } }
      call("max_by") { |r| r.max_by() { |*x| x.first } }
      call("member?") { |r| r.member?(1) { |*x| x.first } }
      call("members") { |r| r.members() { |*x| x.first } }
      call("min") { |r| r.min() { |*x| x.first } }
      call("min_by") { |r| r.min_by() { |*x| x.first } }
      call("minmax") { |r| r.minmax() { |*x| x.first } }
      call("minmax_by") { |r| r.minmax_by() { |*x| x.first } }
      call("none?") { |r| r.none?() { |*x| x.first } }
      call("one?") { |r| r.one?() { |*x| x.first } }
      call("partition") { |r| r.partition() { |*x| x.first } }
      call("reduce") { |r| r.reduce() { |*x| x.first } }
      call("reject") { |r| r.reject() { |*x| x.first } }
      call("reverse_each") { |r| r.reverse_each() { |*x| x.first } }
      call("select") { |r| r.select() { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice_after") { |r| r.slice_after() { |*x| x.first } }
      call("slice_before") { |r| r.slice_before() { |*x| x.first } }
      call("slice_when") { |r| r.slice_when() { |*x| x.first } }
      call("sort") { |r| r.sort() { |*x| x.first } }
      call("sort_by") { |r| r.sort_by() { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("take") { |r| r.take(1) { |*x| x.first } }
      call("take_while") { |r| r.take_while() { |*x| x.first } }
      call("tally") { |r| r.tally() { |*x| x.first } }
      call("to_a") { |r| r.to_a() { |*x| x.first } }
      call("to_h") { |r| r.to_h() }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_set") { |r| r.to_set() { |*x| x.first } }
      call("uniq") { |r| r.uniq() { |*x| x.first } }
      call("values") { |r| r.values() { |*x| x.first } }
      call("values_at") { |r| r.values_at() { |*x| x.first } }
      call("zip") { |r| r.zip() { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      all?: all?->each
      any?: any?->each
      collect: collect->each
      collect_concat: collect_concat->each
      compact: compact->each
      count: count->each
      detect: detect->each
      drop: drop->each
      drop_while: drop_while->each
      each_cons: each_cons->size each_cons->each
      each_entry: each_entry->each
      each_slice: each_slice->size each_slice->each
      each_with_index: each_with_index->each
      each_with_object: each_with_object->each
      entries: entries->each
      filter_map: filter_map->each
      find: find->each
      find_all: find_all->each
      find_index: find_index->each
      first: first->each
      flat_map: flat_map->each
      grep: grep->each
      grep_v: grep_v->each
      group_by: group_by->each
      include?: include?->each
      inject: inject->each
      map: map->each
      max: max->each
      max_by: max_by->each
      member?: member?->each
      min: min->each
      min_by: min_by->each
      minmax: minmax->each
      minmax_by: minmax_by->each
      none?: none?->each
      one?: one?->each
      partition: partition->each
      reduce: reduce->each
      reject: reject->each
      reverse_each: reverse_each->each
      sort: sort->each
      sort_by: sort_by->each
      sum: sum->each
      take: take->each
      take_while: take_while->each
      tally: tally->each
      to_set: to_set->each_entry each_entry->each
      uniq: uniq->each
      zip: zip->each
    OUT
  end
end
