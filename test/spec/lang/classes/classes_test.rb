# frozen_string_literal: true

require "spec_helper"

describe "Classes programs" do
  it "bare class opening fixes its parent" do
    result = ze0(<<~'RUBY')
      # The shapes around `superclass mismatch`. A `class Foo` with no clause gives
      # Foo the class Object as its parent, and that is a decision, not an absence:
      # every later reopen must agree with it or raise.
      class Parent; end
      class Other; end

      class Bare; end
      begin
        class Bare < Parent; end
      rescue TypeError => e
        p [e.class, e.message]
      end
      p Bare.superclass.to_s

      # Restating the SAME parent is fine, however many times, and a bare reopen of
      # a declared class agrees with it by saying nothing.
      class Kid < Parent
        def a = 1
      end
      class Kid < Parent
        def b = 2
      end
      class Kid
        def c = 3
      end
      k = Kid.new
      p [k.a, k.b, k.c, Kid.superclass.to_s]

      # Two DIFFERENT declared parents conflict.
      begin
        class Kid < Other; end
      rescue TypeError => e
        p [e.class, e.message]
      end

      # A module has no superclass to disagree about.
      module Mixin
        def m = :m
      end
      module Mixin
        def n = :n
      end
      class UsesMixin
        include Mixin
      end
      p [UsesMixin.new.m, UsesMixin.new.n]

      # A builtin reopen may restate its real parent, and may not invent one.
      class String < Object
        def shout = upcase + "!"
      end
      p "hi".shout
      begin
        class String < Parent; end
      rescue TypeError => e
        p [e.class, e.message]
      end

      # The KIND has to agree too, and ruby names the leaf.
      begin
        module Parent; end
      rescue TypeError => e
        p [e.class, e.message.lines.first.chomp]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "superclass mismatch for class Bare"]
      "Object"
      [1, 2, 3, "Parent"]
      [TypeError, "superclass mismatch for class Kid"]
      [:m, :n]
      "HI!"
      [TypeError, "superclass mismatch for class String"]
      [TypeError, "Parent is not a module"]
    OUT
  end

  it "bare return in initialize" do
    result = ze0(<<~'RUBY')
      # Issue #337: a bare `return` (Ruby's "exit early" form) inside an
      # `initialize` body used to lower to `return 0;` regardless of the
      # wrapping function's C return type. Two emit shapes were affected:
      #
      #  - `sp_<C>_new(...)` (sp_<C> *-returning, the heap-allocated
      #    constructor synthesis): `return 0;` silently NULLed the
      #    instance on the early-return branch — semantically wrong, no C
      #    diagnostic.
      #
      #  - `sp_<C>_initialize(...)` (void-returning, used for `super`
      #    chains): `return 0;` is a `void function should not return a
      #    value` error under strict C compile.
      #
      # Fix: pin @current_method_return per emission shape (obj_<C> for
      # the _new synthesis, "void" for the _initialize wrapper) so the
      # bare-return path picks the right C statement — `return self;` for
      # heap constructors (returns the partially-initialized instance,
      # matching the issue's expected-behavior table) and `return;` for
      # the void wrapper.

      class Box
        attr_reader :data
        def initialize(other = nil)
          @data = "ok"
          return if other.nil?
          @data = other
        end
      end

      # Default-construct: the bare `return` inside initialize fires;
      # `@data` stays at "ok".
      b1 = Box.new
      puts b1.data           # ok

      # Pass an explicit value: the early return is skipped; `@data` is
      # overwritten.
      b2 = Box.new("hi")
      puts b2.data           # hi

      # Subclass exercising the void `_initialize` super-call form: the
      # parent's bare return inside the wrapper must lower to `return;`
      # (not `return 0;`, which would be a C error in a void function).
      class TaggedBox < Box
        attr_reader :tag
        def initialize(other = nil, tag:)
          super(other)
          @tag = tag
        end
      end

      t = TaggedBox.new("payload", tag: "label")
      puts t.tag             # label

      t2 = TaggedBox.new(tag: "empty")
      puts t2.tag            # empty
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      hi
      label
      empty
    OUT
  end

  it "basicobject new" do
    result = ze0(<<~'RUBY')
      # BasicObject is instantiable (#2658): the same blank instance Object.new
      # builds, tagged with its own builtin id.
      o = BasicObject.new
      p :created
      q = Object.new
      p q.class
    RUBY

    _(result).must_answer <<~'OUT'
      :created
      Object
    OUT
  end

  it "bigint operand rooted" do
    result = ze0(<<~'RUBY')
      # A bignum operand must survive the evaluation of the other side, which can
      # run arbitrary code (and collect).
      class Run
        def initialize
          @acc = 0
        end

        def work(n)
          # allocate enough to force collections while the other operand waits
          junk = []
          n.times { |i| junk << "s#{i}" * 3 }
          v = 0
          n.times { |i| v = ((v << 2) + (i % 7)) & 0xFFFFFFFFFFFFFFFF }
          v
        end

        def step(n)
          @acc = (@acc + work(n).to_i) & 0xFFFFFFFF
        end

        def acc
          @acc
        end
      end

      r = Run.new
      5.times { r.step(3000) }
      p r.acc
      p r.acc & 0xFFFF
    RUBY

    _(result).must_answer <<~'OUT'
      3768812167
      33415
    OUT
  end

  it "call or write through writer" do
    result = ze0(<<~'RUBY')
      # `obj.attr ||= v` and `&&=` call the reader and, conditionally, the writer.
      # They were emitted as a direct instance-variable touch instead, which is a
      # valid fast path for a generated accessor pair and wrong for a hand-written
      # one: the writer never ran. Silently where the ivar happened to share the
      # method's name, and as a C error naming a struct member that does not exist
      # where it did not. `attr = v` and `attr += v` were already correct, so the
      # defect was specific to the short-circuit forms (#4148).
      $log = []

      class Box
        def initialize
          @v = nil
        end

        def v
          $log << :read
          @v
        end

        def v=(value)
          $log << :write
          @v = value * 10
        end
      end

      b = Box.new
      p (b.v ||= 7)          # assigns: the value is what was ASSIGNED, not the
      p b.v                  # writer's return and not a re-read
      p $log

      # Assigning again finds it truthy: reader once, no writer, no right-hand side.
      $log = []
      $evaluated = 0
      def side
        $evaluated += 1
        9
      end
      p (b.v ||= side)
      p [$log, $evaluated]

      # `&&=` is the mirror, including the value on the arm that does not assign.
      $log = []
      c = Box.new
      p (c.v &&= 7)
      p [c.v, $log]
      c2 = Box.new
      c2.v = 1
      $log = []
      p (c2.v &&= 7)
      p [c2.v, $log]

      # The ivar need not share the method's name -- this was the shape that failed
      # to build rather than failing silently.
      class Session
        def initialize = @raw = nil
        def last_active_at = @raw
        def last_active_at=(value)
          $log << :sw
          @raw = value
        end
        def touch = self.last_active_at ||= 7
      end
      $log = []
      s = Session.new
      p s.touch
      p [s.last_active_at, $log]

      # A receiver that is not `self`, in statement position, evaluated ONCE.
      $n = 0
      def recv(x)
        $n += 1
        x
      end
      d = Box.new
      recv(d).v ||= 5
      p [d.v, $n]

      # A generated accessor keeps the direct path and the same answers.
      class Plain
        attr_accessor :a
      end
      q = Plain.new
      p (q.a ||= 3)
      p (q.a ||= 4)
      p q.a
    RUBY

    _(result).must_answer <<~'OUT'
      7
      70
      [:read, :write, :read]
      70
      [[:read], 0]
      nil
      [nil, [:read, :read]]
      7
      [70, [:read, :write, :read]]
      7
      [7, [:sw]]
      [50, 1]
      3
      3
      3
    OUT
  end

  it "case when value type classes" do
    result = ze0(<<~'RUBY')
      # `when Rational` / `when Complex` (and Regexp, Proc, Time) have a builtin
      # cls_id but no class-table entry, so the arm used to compile to a constant
      # false and never matched; `Klass === poly` answered false the same way (#3959).
      def kind(v)
        case v
        when Integer then :int
        when Rational then :rat
        when Complex then :cpx
        when Regexp then :re
        when Proc then :pr
        else :other
        end
      end
      p kind(3)
      p kind(Rational(1, 2))
      p kind(Complex(1, 2))
      p kind(/x/)
      p kind(proc { 1 })
      p kind("s")

      def numeric?(v)
        case v
        when Numeric then :num
        else :other
        end
      end
      p numeric?(Rational(1, 2))
      p numeric?(Complex(1, 2))
      p numeric?(2**80)
      p numeric?(1.5)
      p numeric?("s")

      def flags(v)
        [v.is_a?(Rational), v.is_a?(Complex), v.is_a?(Numeric), v.is_a?(Regexp),
         Rational === v, Complex === v, Regexp === v]
      end
      p flags(Rational(1, 2))
      p flags(Complex(1, 2))
      p flags(/x/)
      p flags(3)
    RUBY

    _(result).must_answer <<~'OUT'
      :int
      :rat
      :cpx
      :re
      :pr
      :other
      :num
      :num
      :num
      :num
      :other
      [true, false, true, false, true, false, false]
      [false, true, true, false, false, true, false]
      [false, false, false, true, false, false, true]
      [false, false, true, false, false, false, false]
    OUT
  end

  it "case when with class candidates checks instance ancestry" do
    result = ze0(<<~'RUBY')
      # `Module#===` -- previously a compile-time rejection (`when Integer`
      # never worked); now real Ruby's instance-of check.

      class Widget
      end

      [5, "s", Widget.new, nil].each do |v|
        case v
        when Integer then puts "int"
        when String then puts "str"
        when Widget then puts "widget"
        else puts "other"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      int
      str
      widget
      other
    OUT
  end

  it "class allocate" do
    result = ze0(<<~'RUBY')
      class Thing
        def initialize(x) = (@x = x)
        def x = @x
      end

      # allocate takes no args even though initialize requires one: it does not run
      # initialize. The object is still a usable instance of the class.
      t = Thing.allocate
      puts t.class.name
      puts t.is_a?(Thing)

      # .new still constructs normally (initialize runs)
      n = Thing.new(5)
      puts n.x
      puts n.class.name

      # a bare instance is populated afterward: state assigned post-allocate reads
      # back normally (allocate's purpose is to build an instance you initialize by
      # hand). Reading before assignment is intentionally avoided.
      class Point
        attr_accessor :x, :y
      end
      p = Point.allocate
      p.x = 3
      p.y = 4
      puts p.x + p.y

      # a nested (ConstantPath) class receiver resolves too
      module Outer
        class Inner
          def initialize = (@v = 99)
          def v = @v
        end
      end
      i = Outer::Inner.allocate
      puts i.class.name
      puts Outer::Inner.new.v
    RUBY

    _(result).must_answer <<~'OUT'
      Thing
      true
      5
      Thing
      7
      Outer::Inner
      99
    OUT
  end

  it "class body built at runtime is still a class body" do
    result = ze0(<<~'RUBY')
      # `class Adapter < parent` with a LOCAL superclass has no compile-time class to
      # lay out, so zeo builds it with `Class.new(parent) { ... }`. A block is not a
      # class body in two ways ruby cares about, and both used to leak:
      #
      #   * a block SHARES the enclosing local scope, where a class body has its own;
      #   * a block opens no cref, so `@@v` in one raised "class variable access from
      #     toplevel".
      #
      # sidekiq's ActiveJob adapter is built exactly this way and hits both at once.

      class AbstractAdapter
        def kind = :abstract
      end

      parent = AbstractAdapter
      callback = :OUTER_UNTOUCHED

      class Adapter < parent
        @@stopping = false

        # A body local, read from two nested blocks. Sharing the enclosing scope
        # would have clobbered the `callback` above.
        callback = -> { @@stopping = true }

        [1].each { |_| [2].each { |_| callback.call } }

        def self.stopping? = @@stopping

        def self.stop! = @@stopping = true
      end

      p Adapter.stopping?
      p callback
      p [Adapter.new.kind, Adapter.superclass]

      # The body's local never reached the enclosing scope.
      p defined?(callback)
      p binding.local_variables.sort

      # The class variable is real storage on the built class, reachable from the
      # methods it defined.
      class Adapter
        def self.reset! = @@stopping = false
      end
      Adapter.reset!
      p Adapter.stopping?
      Adapter.stop!
      p [Adapter.stopping?, Adapter.class_variable_get(:@@stopping)]

      # ---------------------------------------------------------------------------
      # `rescue => target` takes any assignable target, not just a local.
      # activesupport writes `rescue => @setup_exception`.

      class Worker
        attr_reader :err

        def run
          begin
            raise ArgumentError, "boom"
          rescue => @err
          end
          @err.message
        end
      end

      w = Worker.new
      p [w.run, w.err.class]

      # ... including through a splatted exception list, which is rspec-rails' shape.
      class Matcher
        attr_reader :rescued

        def match_unless_raises(*exceptions)
          exceptions.unshift(Exception) if exceptions.empty?
          begin
            yield
            true
          rescue *exceptions => @rescued
            false
          end
        end
      end

      m = Matcher.new
      p [m.match_unless_raises(TypeError) { raise TypeError, "t" }, m.rescued.message]
      p [m.match_unless_raises(TypeError) { :fine }, m.rescued.message]

      # A global and a class variable work the same way.
      begin
        raise "to a global"
      rescue => $caught
      end
      p $caught.message

      class Holder
        def self.grab
          begin
            raise "to a cvar"
          rescue => @@last
          end
          @@last.message
        end
      end
      p Holder.grab

      # The target is assigned BEFORE the clause's own body runs.
      def order
        raise "x"
      rescue => @seen
        @seen.message.upcase
      end
      p order

      # ---------------------------------------------------------------------------
      # `define_singleton_method(:name, &callable)` hands over a proc the caller
      # already holds -- not a literal block. ddtrace, mcp and datasource all write
      # it that way.

      module Timer
        class << self
          def now_provider=(block)
            define_singleton_method(:now, &block)
          end
        end
      end

      Timer.now_provider = -> { 42 }
      p Timer.now

      o = Object.new
      blk = proc { :from_proc }
      o.define_singleton_method(:tag, &blk)
      p [o.tag, o.singleton_methods]

      # A literal block still takes the compile-time path.
      o2 = Object.new
      o2.define_singleton_method(:lit) { :from_literal }
      p o2.lit

      # The captured binding travels with the proc.
      def make(value)
        proc { value }
      end
      o3 = Object.new
      o3.define_singleton_method(:held, &make(:captured))
      p o3.held
    RUBY

    _(result).must_answer <<~'OUT'
      true
      :OUTER_UNTOUCHED
      [:abstract, AbstractAdapter]
      "local-variable"
      [:blk, :callback, :m, :o, :o2, :o3, :parent, :w]
      false
      [true, true]
      ["boom", ArgumentError]
      [false, "t"]
      [true, "t"]
      "to a global"
      "to a cvar"
      "X"
      42
      [:from_proc, [:tag]]
      :from_literal
      :captured
    OUT
  end

  it "class case eq" do
    result = ze0(<<~'RUBY')
      class Animal; end
      class Dog < Animal; end
      class Cat; end
      d = Dog.new
      p(Animal === d)
      p(Cat === d)
      p(Dog === d)
      p(Comparable === 5)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
    OUT
  end

  it "class def under runtime conditional" do
    result = ze0(<<~'RUBY')
      # A class or module body guarded by a RUNTIME condition.
      #
      # Gems that support more than one Ruby implementation define whole classes
      # behind a platform probe. concurrent-ruby does exactly this, which is why
      # `require "concurrent"` does not compile:
      #
      #   # concurrent-ruby/concurrent/executor/java_thread_pool_executor.rb:1
      #   if Concurrent.on_jruby?
      #     module Concurrent
      #       class JavaThreadPoolExecutor < RubyThreadPoolExecutor
      #   ...
      #
      # zeo resolves class shape at compile time, so it lowers a definition inside a
      # top-level `if` only when the condition is compile-time decidable (such as
      # `defined?(SomeConstant)`), or when the body only reopens an already-defined
      # class to add methods. A method call is neither, so the compile stops.
      #
      # Ruby runs the false branch and prints "native".

      def on_jruby?
        RUBY_PLATFORM == "java"
      end

      if on_jruby?
        class Backend
          def name
            "java"
          end
        end
      else
        class Backend
          def name
            "native"
          end
        end
      end

      puts Backend.new.name
    RUBY

    _(result).must_answer "native\n"
  end

  it "class defines its own new" do
    result = ze0(<<~'RUBY')
      # `def self.new` is an ordinary class method: `.new` dispatches to it, and its
      # `super` reaches `Class#new`'s allocate-then-`initialize`. rubygems'
      # `Gem::Package::TarWriter` uses the shape to offer a block form that closes.
      class Writer
        def self.new(io)
          w = super
          return w unless block_given?
          begin
            yield w
          ensure
            w.close
          end
          nil
        end

        def initialize(io) = @io = io
        attr_reader :io
        def close = @io = :closed
      end

      p Writer.new(:handle).io
      p(Writer.new(:handle) { |w| p w.io })

      # A subclass inherits the wrapper, and `super` still lands on the allocator.
      class Sub < Writer
        def initialize(io)
          super
          @extra = true
        end
        attr_reader :extra
      end
      s = Sub.new(:sub)
      p [s.class, s.io, s.extra]
      p(Sub.new(:sub) { |w| p w.class })

      # `self.new` may answer something that isn't an instance at all.
      class Maker
        def self.new(*) = :not_an_instance
      end
      p Maker.new
      p Maker.new(1, 2)

      # A block handed to a plain `.new` whose `initialize` ignores it is no error.
      class Plain
        def initialize(v) = @v = v
        attr_reader :v
      end
      p(Plain.new(7) { raise "never called" }.v)
    RUBY

    _(result).must_answer <<~'OUT'
      :handle
      :handle
      nil
      [Sub, :sub, true]
      Sub
      nil
      :not_an_instance
      :not_an_instance
      7
    OUT
  end

  it "class in collection" do
    result = ze0(<<~'RUBY')
      # A Class object stored in a Hash value or Array element must round-trip
      # through poly storage (boxed as a class), not collapse to the int slot
      # (which produced an sp_box_int / sp_IntArray_push type mismatch and,
      # once stored, printed the cls_id instead of the class name).

      str_keyed = { "a" => String, "b" => Integer }
      puts str_keyed["a"]
      puts str_keyed["b"]

      sym_keyed = { foo: String, bar: Array }
      puts sym_keyed[:foo]
      puts sym_keyed[:bar]

      int_keyed = { 1 => String, 2 => Integer }
      puts int_keyed[1]
      puts int_keyed[2]

      classes = [String, Integer, Hash]
      puts classes[0]
      puts classes[1]
      puts classes.length
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      String
      Integer
      String
      Array
      String
      Integer
      String
      Integer
      3
      done
    OUT
  end

  it "class model edges" do
    result = ze0(<<~'RUBY')
      # Three class-model behaviors that follow from Ruby's real object model.

      # 1. `super` in a CLASS method. In Ruby `def self.foo` is an ordinary instance
      #    method on the SINGLETON class, and singleton classes form a parallel
      #    chain (#<Class:C>.super == #<Class:C.superclass>), so `super` needs no
      #    special case -- including through a three-level chain and with zsuper
      #    argument forwarding.
      class Foo
        def self.base; 100; end
        def self.greet(name); "hello #{name}"; end
        def self.tag(pfx = "t"); pfx + "-foo"; end
      end
      class Bar < Foo
        def self.base; super * 10; end
        def self.greet(name); super(name.upcase) + "!"; end
        def self.tag(pfx = "t"); super; end
      end
      class Baz < Bar
        def self.base; super + 1; end
      end
      p Foo.base
      p Bar.base
      p Baz.base
      p Bar.greet("matz")
      p Bar.tag
      p Bar.tag("x")

      # 2. A BasicObject subclass is a BLANK SLATE. Kernel is mixed into Object, so
      #    it sits BELOW BasicObject in the chain and a BasicObject subclass never
      #    sees it -- the whole Object/Kernel surface is simply absent. Note `send`
      #    and `public_send` live on Kernel; only `__send__` is BasicObject's.
      class BO < BasicObject
        def initialize; @x = 1; end
        def greet; "hi"; end
        def own; @x; end
      end
      a = BO.new
      r1 = (a.class rescue $!.class); p r1
      p a.greet
      r2 = (a.inspect rescue "no-inspect"); p r2
      r3 = (a.respond_to?(:greet) rescue "no-respond_to"); p r3
      r4 = (a.send(:greet) rescue $!.class); p r4
      p a.__send__(:greet)
      p(a == a)
      p(a == BO.new)
      p a.equal?(a)
      r5 = (a.dup.own rescue $!.class); p r5
      p a.own

      # an ordinary class still has the full surface
      class Normal; end
      p Normal.new.class
      p Normal.new.respond_to?(:inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      100
      1000
      1001
      "hello MATZ!"
      "t-foo"
      "x-foo"
      NoMethodError
      "hi"
      "no-inspect"
      "no-respond_to"
      NoMethodError
      "hi"
      true
      false
      true
      NoMethodError
      1
      Normal
      true
    OUT
  end

  it "class name already taken is a type error" do
    result = ze0(<<~'RUBY')
      # Ruby raises before anything is minted. (It also warns
      # `previous definition of TOP was here`, which zeo does not track --
      # hence the stdout-only check rather than a golden.)

      TOP = 1
      src = "class TOP; end"
      begin
        eval(src)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TOP is not a class
      lang/classes/classes_test.rb:5: previous definition of TOP was here
    OUT
  end

  it "class new creates an anonymous runtime class" do
    result = ze0(<<~'RUBY')
      # `Class.new(Super) { ... }` mints a runtime class. The block body
      # runs against the new class (`define_method` and `def` both install on
      # it); a constant binding names it; is_a?/instance_of?/superclass and a
      # runtime superclass chain all resolve.

      Widget = Class.new do
        define_method(:kind) { "widget" }
        def size
          10
        end
      end
      w = Widget.new
      puts w.kind
      puts w.size
      puts w.is_a?(Widget)
      puts Widget.name
      Gadget = Class.new(Widget) do
        define_method(:extra) { "gadget" }
      end
      g = Gadget.new
      puts g.kind
      puts g.extra
      puts g.is_a?(Widget)
      puts g.instance_of?(Widget)
      puts Gadget.superclass.name
    RUBY

    _(result).must_answer <<~'OUT'
      widget
      10
      true
      Widget
      widget
      gadget
      true
      false
      Widget
    OUT
  end

  it "class new override supers into a runtime parent" do
    result = ze0(<<~'RUBY')
      # #192 feature (1): a `super` in an override installed via a `Class.new(Parent)`
      # block reaches the parent's method, when the parent is a runtime class. The
      # override forwards args and composes the parent's result.

      base = Class.new do
        def greet(n)
          "hi #{n}"
        end
      end
      sub = Class.new(base) do
        def greet(n)
          super(n) + "!"
        end
      end
      p sub.new.greet("x")
    RUBY

    _(result).must_answer "\"hi x!\"\n"
  end

  it "class of primitive" do
    result = ze0(<<~'RUBY')
      # Issue #715. `<primitive>.class` should return the builtin class for
      # each primitive, not just for obj-typed receivers. Coverage:
      # Integer/Float/String/Symbol/NilClass/TrueClass/FalseClass/Array/Hash.

      puts 42.class
      puts 3.14.class
      puts "hi".class
      puts :ok.class
      puts nil.class
      puts true.class
      puts false.class
      puts [1, 2].class
      h = {"a" => 1}
      puts h.class
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Float
      String
      Symbol
      NilClass
      TrueClass
      FalseClass
      Array
      Hash
    OUT
  end

  it "class ordering unrelated nil" do
    result = ze0(<<~'RUBY')
      class Animal; end
      class Dog < Animal; end
      class Cat < Animal; end

      p Dog < Cat
      p Dog <= Cat
      p Cat > Dog
      p Cat >= Dog
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
    OUT
  end

  it "class phase2 name eq" do
    result = ze0(<<~'RUBY')
      # Issue #404 Phase 2: `.name`, `.inspect`, `.==`, `.!=`, `.eql?`
      # on a sp_Class value. Phase 1 wired `.to_s` and the class-as-value
      # round-trip through locals / ivars / hash values. Phase 2 fills
      # in the remaining "simple" reflection surface that doesn't need
      # precomputed ancestors:
      #
      #   - `.name` / `.inspect` alias `.to_s` (sp_class_to_s lookup).
      #     CRuby's #inspect for a class is technically "Foo" too -- it's
      #     `<Class:Foo>` only via the Object#inspect fallback when the
      #     class doesn't override #inspect (which it does, returning
      #     just the name). Phase 2 keeps the bare-name shape; the
      #     "#<Class:Foo>"-ish polish is Phase 3 work if ever needed.
      #   - `.==` / `.eql?` -- sp_class_eq(a, b) (cls_id field compare).
      #   - `.!=` -- the negation thereof.
      #
      # Out of scope: `.superclass`, `.ancestors`, `< / <= / > / >=`,
      # `case <obj> when <Class>`, dynamic `is_a?(c)` against a
      # variable. Those need the precomputed ancestor table from
      # docs/CLASS-OBJECT.md.
      #
      # Coverage:
      #   - .name / .inspect on a class literal and through obj.class.
      #   - == / != / eql? between class literals, mixing with subclass,
      #     and through obj.class chains.
      #   - Subclass-of-Base still gets the subclass cls_id from .class
      #     (regression check on #419's static dispatch).

      class Row
        attr_accessor :id
        def initialize
          @id = 0
        end
      end

      class Article < Row
      end

      # Direct class literal.
      puts Row.name                 # Row
      puts Article.inspect          # Article

      # Through obj.class.
      r = Row.new
      a = Article.new
      puts r.class.name             # Row
      puts a.class.inspect          # Article

      # Equality / inequality / eql?
      puts (Row == Row).to_s        # true
      puts (Row == Article).to_s    # false
      puts (Row != Article).to_s    # true
      puts (Row != Row).to_s        # false
      puts Row.eql?(Row).to_s       # true
      puts Row.eql?(Article).to_s   # false

      # Through obj.class chains.
      puts (r.class == Row).to_s            # true
      puts (r.class == Article).to_s        # false
      puts (a.class != Row).to_s            # true
      puts (a.class == Article).to_s        # true
      puts r.class.eql?(Row).to_s           # true
    RUBY

    _(result).must_answer <<~'OUT'
      Row
      Article
      Row
      Article
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
    OUT
  end

  it "class state" do
    result = ze0(<<~'RUBY')
      # Class-level state: `self` inside a class method, and the instance
      # variables of the CLASS OBJECT itself.
      #
      # The one rule everything here follows from: in a class method (or a class
      # body), `self` is the class object. So `@x` there is that object's own ivar
      # -- a different thing from both `@@x` and an instance's `@x` -- and an
      # implicit-self call is a send to whichever class was actually called.

      # --- `self` is the class object ---------------------------------------------
      class Foo
        def self.who
          self
        end
      end
      p Foo.who
      p Foo.who == Foo
      p Foo.who.name
      p Foo.who.new.class

      # --- @x on the class object -------------------------------------------------
      # A bare `@x = ...` in a class body seeds it; `def self.x` reads it.
      class Registry
        @items = []
        @count = 0

        def self.add(x)
          @items << x
          @count += 1
          self          # so calls chain
        end

        def self.items = @items
        def self.count = @count
      end

      Registry.add("a").add("b").add("c")
      p Registry.items
      p Registry.count

      # Reading one never written is nil -- no NameError (that's `@@x`'s rule, not
      # this one).
      class Quiet
        def self.probe = @never_written
      end
      p Quiet.probe

      # --- NOT inherited (the difference from @@x) --------------------------------
      # A subclass inherits the METHOD but gets its own, empty storage. A class
      # variable, by contrast, is genuinely shared.
      class Base
        @tag = "base"
        @@shared = "shared"
        def self.tag = @tag
        def self.tag=(v)
          @tag = v
        end
        def self.shared = @@shared
      end
      class Sub < Base; end

      p [Base.tag, Sub.tag]              # Sub's slot is empty...
      p [Base.shared, Sub.shared]        # ...but the cvar is one slot, shared
      Sub.tag = "sub"
      p [Base.tag, Sub.tag]              # writes stay independent

      # --- a class @x and an instance @x are different slots ----------------------
      # `def self.x` and `def x` are two namespaces in Ruby, and their `@x`s name
      # two different objects' storage.
      class Dual
        @x = "class-level"
        def initialize
          @x = "instance-level"
        end
        def self.x = @x
        def x = @x
      end
      p [Dual.x, Dual.new.x]

      # --- `class << self` -- the idiomatic declaration ---------------------------
      # `attr_accessor` there generates `def self.handler; @handler; end`, so it is
      # class-level ivars all the way down.
      module Plugin
        class << self
          attr_accessor :handler
          attr_reader :registered

          def register(h)
            @registered ||= []
            @registered << h
            self.handler = h
          end
        end
      end

      Plugin.register("first")
      Plugin.register("second")
      p Plugin.handler
      p Plugin.registered

      # --- module-level state -----------------------------------------------------
      module Counter
        @n = 0
        def self.bump = @n += 1
        def self.n = @n
      end
      Counter.bump
      Counter.bump
      p Counter.n

      # --- an implicit-self call resolves against the RECEIVER --------------------
      # `new` and `name` below are sends to `self`, and `self` is whichever class
      # was called -- not the one whose body the method was written in.
      class Shape
        def self.build = new
        def self.label = "a #{name}"
      end
      class Circle < Shape; end

      p Shape.build.class
      p Circle.build.class               # Circle, not Shape
      p Circle.label

      module Greeter
        def greet = "hello from #{name}"
      end
      class English
        extend Greeter
      end
      p English.greet                    # names English, not Greeter

      # --- class-level @x from inside a block -------------------------------------
      # The block captures `self` as the class object, so the ivar has to resolve
      # to the same storage the direct path uses.
      class Collect
        @seen = []
        def self.run
          [1, 2, 3].each { |i| @seen << i * 10 }
          @seen
        end
      end
      p Collect.run

      # --- dispatching over a class held in a variable ----------------------------
      # The receiver isn't a literal constant here, so this can't be a direct call
      # -- it dispatches on the class value at runtime.
      class HandlerA
        def self.run(x) = "A:#{x}"
      end
      class HandlerB
        def self.run(x) = "B:#{x}"
      end

      [HandlerA, HandlerB].each { |h| puts h.run(1) }

      current = HandlerA
      puts current.run(2)
      current = HandlerB
      puts current.run(2)

      # --- full parameter shapes on a class method --------------------------------
      class Sig
        def self.m(a, b = 2, *rest, k: 9, **kw, &blk)
          [a, b, rest, k, kw, blk ? blk.call : nil]
        end
      end
      p Sig.m(1)
      p Sig.m(1, 3, 4, 5, k: 0, z: 1) { "blk" }

      # --- reflection over a class object's ivars ---------------------------------
      class Reflect
        @a = 1
      end
      p Reflect.instance_variable_get(:@a)
      p Reflect.instance_variable_get("@a")     # a String name works too
      p Reflect.instance_variable_get(:@absent) # nil, not an error
      p Reflect.instance_variable_set(:@b, 2)   # answers the VALUE
      p Reflect.instance_variables
      p Reflect.instance_variable_defined?(:@a)
      p Reflect.instance_variable_defined?(:@absent)

      begin
        Reflect.instance_variable_get(:a)       # no leading @
      rescue NameError => e
        puts "NameError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Foo
      true
      "Foo"
      Foo
      ["a", "b", "c"]
      3
      nil
      ["base", nil]
      ["shared", "shared"]
      ["base", "sub"]
      ["class-level", "instance-level"]
      "second"
      ["first", "second"]
      2
      Shape
      Circle
      "a Circle"
      "hello from English"
      [10, 20, 30]
      A:1
      B:1
      A:2
      B:2
      [1, 2, [], 9, {}, nil]
      [1, 3, [4, 5], 0, {z: 1}, "blk"]
      1
      1
      nil
      2
      [:@a, :@b]
      true
      false
      NameError: 'a' is not allowed as an instance variable name
    OUT
  end

  it "class superclass" do
    result = ze0(<<~'RUBY')
      class A
      end

      class B < A
      end

      class C
        def foo
          1
        end
      end

      puts A.superclass
      puts B.superclass
      puts C.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      Object
      A
      Object
    OUT
  end

  it "class value builtin and nested" do
    result = ze0(<<~'RUBY')
      # Followup to #404. Built-in exception classes (StandardError,
      # RuntimeError, ...) and nested user classes (M::Inner) used as
      # values must lower to sp_Class compound literals, the same way
      # flat user-class constants already did. Pre-fix the emit was a
      # bare C identifier (`StandardError`, `M_Inner`) that gcc rejected
      # with "use of undeclared identifier". Issue #637.

      # Shape A: built-in exception class as value.
      def takes_class(c)
        puts c.name
      end

      takes_class(StandardError)
      takes_class(RuntimeError)
      takes_class(ArgumentError)

      # Class object via a local — round-trip through a value slot.
      c = StandardError
      puts c.name

      # Shape B: nested user class as value. Verify the value compiles
      # and survives a round-trip through a local; the displayed
      # `c.name` between spinel and MRI may differ (spinel uses `_` as
      # the internal separator), but `c == Inner-class` confirms the
      # value emit and equality semantics hold.
      module M
        class Inner
        end
      end

      def make
        M::Inner
      end

      c2 = make
      puts c2 == M::Inner ? "round-trip ok" : "round-trip BROKEN"
    RUBY

    _(result).must_answer <<~'OUT'
      StandardError
      RuntimeError
      ArgumentError
      StandardError
      round-trip ok
    OUT
  end

  it "class var recv reflection" do
    result = ze0(<<~'RUBY')
      # A local statically holding one class constant dispatches like the constant
      # for the reflection surface too (#2717, #2721).
      class Dog; def bark; end; end
      c = Dog
      p c.method_defined?(:bark)
      p c.instance_methods(false)
      class Base; end
      class Kid1 < Base; end
      class Kid2 < Base; end
      b = Base
      p(b.subclasses.length)
      p(b.subclasses.map { |k| k.name }.sort)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [:bark]
      2
      ["Kid1", "Kid2"]
    OUT
  end

  it "class variable cref scope" do
    result = ze0(<<~'RUBY')
      # `@@x` resolves against the LEXICAL cref chain, and only `class`/`module`
      # bodies open one. Outside any of them Ruby raises rather than storing.

      class Counted
        @@count = 0
        def self.bump = @@count += 1
        def count = @@count
      end
      Counted.bump
      p Counted.new.count
      p Counted.class_variables

      # A `def` and a block both inherit the enclosing cref rather than opening one.
      class Holder
        define_method(:set) { @@via_block = :yes }
        def self.read = @@via_block
      end
      Holder.new.set
      p Holder.read

      # Reopening Object explicitly IS a cref, so this stores rather than raising.
      class Object
        @@on_object = 1
      end
      p Object.class_variables.include?(:@@on_object)

      # `class << self` is skipped when resolving, so this lands on Holder.
      class Holder
        class << self
          @@from_singleton = 7
        end
      end
      p Holder.class_variables.sort

      def raised
        yield
        "no raise"
      rescue RuntimeError => e
        e.message
      end

      p raised { @@toplevel_read }
      p raised { @@toplevel_write = 1 }
      p raised { @@toplevel_op ||= 1 }
      p raised { @@a, @@b = 1, 2 }
      p raised { Class.new { @@in_class_new = 1 } }
      p raised { Module.new { @@in_module_new = 1 } }
      p raised { Holder.class_eval { @@in_class_eval = 1 } }

      # `defined?` never evaluates its operand, so it answers nil instead.
      p defined?(@@never_assigned)

      # The right-hand side has already run by the time the raise fires.
      side_effect = nil
      p raised { @@late = (side_effect = :ran) }
      p side_effect
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [:@@count]
      :yes
      true
      [:@@from_singleton, :@@on_object, :@@via_block]
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      "class variable access from toplevel"
      nil
      "class variable access from toplevel"
      :ran
    OUT
  end

  it "class variable reflection" do
    result = ze0(<<~'RUBY')
      class C
        @@x = 5
        @@name = "hi"
      end
      p C.class_variable_get(:@@x)
      p C.class_variable_get(:@@name)
      p C.class_variable_defined?(:@@x)
      p C.class_variable_defined?(:@@nope)
      C.class_variable_set(:@@x, 99)
      p C.class_variable_get(:@@x)
      r = (C.class_variable_get(:@@missing) rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      5
      "hi"
      true
      false
      99
      NameError
    OUT
  end

  it "class variables" do
    result = ze0(<<~'RUBY')
      # A class variable (`@@x`) is shared storage owned by the class or module
      # where it's first assigned. It can be declared in a module body and read
      # and written from `def self.` methods.
      module Counter
        @@total = 0

        def self.bump
          @@total += 1
        end

        def self.total
          @@total
        end
      end

      Counter.bump
      Counter.bump
      puts Counter.total            # 2

      # `module_function` promotes methods to module methods. A bare
      # `module_function` switches a mode for every following `def`; the
      # `module_function :name` form promotes an already-defined one.
      module Text
        module_function

        def shout(s)
          s.upcase
        end
      end

      module Case
        def flip(s)
          s.swapcase
        end
        module_function :flip
      end

      puts Text.shout("hi")         # HI
      puts Case.flip("Hello")       # hELLO
    RUBY

    _(result).must_answer <<~'OUT'
      2
      HI
      hELLO
    OUT
  end

  it "cmethod self and default" do
    result = ze0(<<~'RUBY')
      # Bare `self` inside a class method is the Class object; a default-parameter
      # expression referencing self evaluates in the CALLEE's context even when
      # the default is materialized at a caller in another class.
      class Wrap
        def initialize(model)
          @model = model
        end

        def read(key)
          "#{@model}:#{key}"
        end
      end

      class Keystore
        def self.value_for(key, rel = Wrap.new(self))
          rel.read(key)
        end
      end

      class Traffic
        def self.intensity
          Keystore.value_for("k")
        end
      end

      class K
        def self.who
          self
        end
      end

      puts Traffic.intensity
      p K.who
    RUBY

    _(result).must_answer <<~'OUT'
      Keystore:k
      K
    OUT
  end

  it "constructor pushes the frames ruby pushes" do
    result = ze0(<<~'RUBY')
      # `Foo.new` pushes NO backtrace frame of its own. zeo pushed `Class#new` for
      # every construction, so a raise from any `initialize` reported one frame ruby
      # does not have.
      #
      # Two shapes DO frame, and each is a different mechanism rather than an
      # exception to one rule:
      #
      #   * `Class.new { }` / `Module.new { }` MINTING -- the receiver is `Class`
      #     itself and the block IS the body, so ruby reports `Class#initialize`
      #     then `Class#new`;
      #   * a `Data` class, whose `new` is a distinct cfunc and reports as `D.new`.
      #
      # The rule is therefore about the RECEIVER, where zeo's frame-label table is
      # keyed by the row's OWNER -- and the owner is `Class` in every case above.
      # So the row is silenced in that table and the two framing shapes push their
      # own.
      #
      # Every row below is oracle-verified against ruby 4.0.6.

      def frames(label, n = 2)
        yield
      rescue => e
        puts "#{label}:"
        puts e.backtrace.first(n).map { |l| "  " + l.sub(%r{\A.*?([^/]+):}, '\1:') }
      end

      # --- the ordinary case: no frame for `new`
      class P1
        def initialize(a)
          raise "plain"
        end
      end
      frames("plain class") { P1.new(1) }

      # --- a Struct subclass: also no frame
      S = Struct.new(:a)
      class S2 < S
        def initialize(*a)
          super
          raise "struct"
        end
      end
      frames("struct subclass") { S2.new(1) }

      # --- an exception subclass: also no frame
      class E1 < StandardError
        def initialize(m = "e")
          super
          raise "exception"
        end
      end
      frames("exception subclass") { E1.new }

      # --- a class with no `initialize` at all
      class P2; end
      frames("arity error, no initialize") { P2.new(1, 2) }

      # --- MINTING does frame, both spellings
      frames("Class.new minting", 3) { Class.new { raise "mint" } }
      frames("Module.new minting", 3) { Module.new { raise "mint" } }

      # --- a subclass whose superclass is an ordinary compiled class
      class P3 < P1
        def initialize(a)
          super
        end
      end
      frames("subclass calling super") { P3.new(1) }

      # --- `allocate` skips `initialize` entirely, so nothing to frame
      frames("allocate then raise") { P1.allocate.instance_variable_get(:@nope) || raise("after allocate") }
    RUBY

    _(result).must_answer <<~'OUT'
      plain class:
        classes_test.rb:30:in 'P1#initialize'
        classes_test.rb:33:in 'block in <main>'
      struct subclass:
        classes_test.rb:40:in 'S2#initialize'
        classes_test.rb:43:in 'block in <main>'
      exception subclass:
        classes_test.rb:49:in 'E1#initialize'
        classes_test.rb:52:in 'block in <main>'
      arity error, no initialize:
        classes_test.rb:56:in 'BasicObject#initialize'
        classes_test.rb:56:in 'block in <main>'
      Class.new minting:
        classes_test.rb:59:in 'block (2 levels) in <main>'
        classes_test.rb:59:in 'Class#initialize'
        classes_test.rb:59:in 'Class#new'
      Module.new minting:
        classes_test.rb:60:in 'block (2 levels) in <main>'
        classes_test.rb:60:in 'Module#initialize'
        classes_test.rb:60:in 'Class#new'
      subclass calling super:
        classes_test.rb:30:in 'P1#initialize'
        classes_test.rb:65:in 'P3#initialize'
      allocate then raise:
        classes_test.rb:71:in 'block in <main>'
        classes_test.rb:21:in 'Object#frames'
    OUT
  end

  it "def with class receiver" do
    result = ze0(<<~'RUBY')
      # `def Klass.name` written inside `class Klass` is the older spelling of
      # `def self.name` -- net/smtp uses it throughout, including as the target of a
      # `class << self` alias, which only resolves if it registered as a class method.
      module Net
        class SMTP
          def SMTP.default_port = 25
          def SMTP.default_tls_port = 465

          class << self
            alias default_ssl_port default_tls_port
          end

          def SMTP.start(address, port = nil)
            "start #{address}:#{port || default_port}"
          end
        end
      end

      p Net::SMTP.default_port
      p Net::SMTP.default_ssl_port
      p Net::SMTP.start("mail.example")
      p Net::SMTP.singleton_methods.sort
      p Net::SMTP.new.respond_to?(:default_port)

      # A DIFFERENT constant is a genuine per-object singleton def, not a class
      # method of the body being lowered.
      class Host
        Target = Object.new
        def Target.ping = "pong"
      end
      p Host::Target.ping
      p Host.singleton_methods
    RUBY

    _(result).must_answer <<~'OUT'
      25
      465
      "start mail.example:25"
      [:default_port, :default_ssl_port, :default_tls_port, :start]
      false
      "pong"
      []
    OUT
  end

  it "default initialize copy" do
    result = ze0(<<~'RUBY')
      class Plain
        attr_accessor :v
        def initialize(v); @v = v; end
      end
      a = Plain.new(1)
      a.send(:initialize_copy, Plain.new(5))
      p a.v
      p Plain.new(1).respond_to?(:initialize_copy, true)
      class WithIC
        attr_accessor :w
        def initialize(w); @w = w; end
        def initialize_copy(o); super; @w = o.w * 2; end
      end
      b = WithIC.new(3).dup
      p b.w
      p WithIC.new(1).respond_to?(:initialize_copy, true)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      6
      true
    OUT
  end

  it "defined classification" do
    result = ze0(<<~'RUBY')
      x = 5
      puts(defined?(x))
      puts(defined?(1 + 1))

      class Foo
        def check
          @bar = 1
          puts(defined?(@bar))
        end
      end
      Foo.new.check
    RUBY

    _(result).must_answer <<~'OUT'
      local-variable
      method
      instance-variable
    OUT
  end

  it "defined classifies syntactic form" do
    result = ze0(<<~'RUBY')
      x = 5
      puts(defined?(x))
      puts(defined?(1 + 1))

      class Foo
        def check
          @bar = 1
          puts(defined?(@bar))
        end
      end
      Foo.new.check
    RUBY

    _(result).must_answer <<~'OUT'
      local-variable
      method
      instance-variable
    OUT
  end

  it "defined on a begin expression classifies as expression" do
    result = ze0(<<~'RUBY')
      puts defined?(begin; 1; end)
    RUBY

    _(result).must_answer "expression\n"
  end

  it "definition hooks when compiled" do
    result = ze0(<<~'RUBY')
      # The same six hooks as `definition_hooks_at_runtime.rb`, but for definitions
      # written in a class body -- which zeo compiles into a method table rather than
      # running, so the report has to be put back at the definition's position.
      #
      # Two rules do most of the work here. A `def self.x` (or one in `class << self`)
      # reports through `singleton_method_added`, not `method_added`. And a hook
      # INSTALLED after a definition never saw it, so only the definitions written
      # below it report.

      puts "== top-level def, on Object"
      class Object
        def self.method_added(n) = puts("Object added #{n}")
      end
      def toplevel_one; end

      puts "== every shape a class body can write"
      class C
        # These two are written before the singleton hook below, so neither reports.
        def self.method_added(n) = puts("C added #{n}")
        def self.method_undefined(n) = puts("C undefined #{n}")
        # This one IS installed by the time it finishes, so it reports itself.
        def self.singleton_method_added(n) = puts("C s_added #{n}")

        def a; end
        puts "  (an ordinary statement between defs keeps its place)"
        def b; end
        def b; end # a redefinition reports again
        attr_accessor :acc # reader, then writer
        attr_reader :ro
        alias_method :c, :a
        alias d a
        def self.klass_method; end
        class << self
          def via_sclass; end
        end
      end

      puts "== a reopen reports too, and `undef` has its own hook"
      class C
        def reopened; end
        undef_method :a
      end

      puts "== a nested class has no hook of its own, so Object's answers"
      class Outer
        def self.method_added(n) = puts("Outer added #{n}")
        class Inner
          def inner_method; end
        end
        def outer_method; end
      end

      puts "== a subclass inherits the hook"
      class SubC < C
        def sub_method; end
      end

      puts "== a bare `private` changes visibility, not whether the def reports"
      class V
        def self.method_added(n) = puts("V added #{n}")
        private
        def hidden; end
        public
        def shown; end
      end

      puts "== bare `module_function` reports both halves"
      module MF
        def self.method_added(n) = puts("MF added #{n}")
        def self.singleton_method_added(n) = puts("MF s_added #{n}")
        module_function
        def after_modfunc; end
      end
      # Both halves are the same definition, so both name the `def`'s own line.
      p [MF.method(:after_modfunc).source_location, MF.instance_method(:after_modfunc).source_location]
    RUBY

    _(result).must_answer <<~'OUT'
      == top-level def, on Object
      Object added toplevel_one
      == every shape a class body can write
      C s_added singleton_method_added
      C added a
        (an ordinary statement between defs keeps its place)
      C added b
      C added b
      C added acc
      C added acc=
      C added ro
      C added c
      C added d
      C s_added klass_method
      C s_added via_sclass
      == a reopen reports too, and `undef` has its own hook
      C added reopened
      C undefined a
      == a nested class has no hook of its own, so Object's answers
      Object added inner_method
      Outer added outer_method
      == a subclass inherits the hook
      C added sub_method
      == a bare `private` changes visibility, not whether the def reports
      V added hidden
      V added shown
      == bare `module_function` reports both halves
      MF s_added singleton_method_added
      MF added after_modfunc
      MF s_added after_modfunc
      [["lang/classes/classes_test.rb", 72], ["lang/classes/classes_test.rb", 72]]
    OUT
  end

  it "dot class reflects every receiver kind" do
    result = ze0(<<~'RUBY')
      class Widget
      end
      module Helper
      end

      w = Widget.new
      puts w.class
      puts w.class == Widget
      puts w.class.name
      puts 5.class
      puts "s".class
      puts [].class
      puts nil.class
      puts true.class
      puts 1.5.class
      puts :sym.class
      puts (1..2).class
      puts({}.class)
      puts Helper.class
      puts Widget.class
      puts Class.class
      puts Widget.class == Class
    RUBY

    _(result).must_answer <<~'OUT'
      Widget
      true
      Widget
      Integer
      String
      Array
      NilClass
      TrueClass
      Float
      Symbol
      Range
      Hash
      Module
      Class
      Class
      true
    OUT
  end

  it "dynamic class new defaults" do
    result = ze0(<<~'RUBY')
      # `table[key].new` -- the receiver is a Class value read out of a container, so
      # the construction switches on its runtime id. The zero-argument form now also
      # reaches a constructor whose parameters are all optional, filling each with
      # its default the way a statically-known `Klass.new` does.

      class A
        def initialize(n = 3)
          @n = n
        end

        def val
          @n
        end
      end

      class B
        def initialize(n = 7)
          @n = n
        end

        def val
          @n * 2
        end
      end

      table = { "a" => A, "b" => B }
      ["a", "b"].each do |k|
        klass = table[k]
        obj = klass.new
        p obj.val
      end

      p table["a"].new.val
    RUBY

    _(result).must_answer <<~'OUT'
      3
      14
      3
    OUT
  end

  it "dynamic class new fed back" do
    result = ze0(<<~'RUBY')
      # `s.class.new(**h)` on a receiver known only at run time. The dispatch
      # switches on the class's cls_id, and the runtime helper that produces that
      # class answered -1 for every value -- it filled in the NAME only -- so the
      # switch matched no arm and the call returned nil (#4020). A statically typed
      # receiver takes a different path, which is why it worked there.
      S = Struct.new(:o, :b, :st, keyword_init: true)

      def bump(s) = s.class.new(**s.to_h.merge(b: s.b + 1))
      def rep(es, from) = es.reduce(from) { |st, _e| bump(st) }

      x = S.new(o: "a", b: 0, st: :open)
      p rep([1], x).to_h

      # feeding the result back is what the report needed; each step alone works too
      y = bump(x)
      p y.class
      p y.b
      p y.to_h
      p bump(y).to_h
      p bump(bump(x)).to_h

      # a reassigning loop is the same shape as the reduce
      z = x
      2.times { z = bump(z) }
      p z.to_h

      # the statically typed receiver keeps working
      p x.class.new(**x.to_h.merge(b: 9)).to_h

      # and a plain class, not just a Struct
      class P
        attr_reader :n
        def initialize(n)
          @n = n
        end
      end

      def grow(p) = p.class.new(p.n + 1)
      q = grow(P.new(1))
      p q.n
      p grow(q).n
    RUBY

    _(result).must_answer <<~'OUT'
      {o: "a", b: 1, st: :open}
      S(keyword_init: true)
      1
      {o: "a", b: 1, st: :open}
      {o: "a", b: 2, st: :open}
      {o: "a", b: 2, st: :open}
      {o: "a", b: 2, st: :open}
      {o: "a", b: 9, st: :open}
      2
      3
    OUT
  end

  it "elsif isa chain" do
    result = ze0(<<~'RUBY')
      # Issue #310: an `if/elsif/else` chain with `is_a?(Class)` checks
      # in the elsif branch used to emit `} else <prologue> if (...)`
      # without wrapping braces. The compile_cond_expr for a poly is_a?
      # emits prologue C statements (`sp_RbVal _t = recv; if (_t.tag ==
      # SP_TAG_OBJ) {...}`) before returning the cond flag. Those
      # prologue statements deposited between the bare `else` and the
      # inner `if` — invalid C: the bare-else's body is the next single
      # statement, and the temp decl's scope ended right there.
      #
      # Fix: wrap elsif branches in `{ }`. The cosmetic `else if` is
      # replaced by `else { if ... }` — semantically identical, scope-
      # correct.
      #
      # This test verifies the C *compiles*. Note that is_a?(UserClass)
      # on a poly receiver still has gaps elsewhere (the SP_TAG_OBJ
      # dispatch loop in compile_poly_method_call only walks user-class
      # method tables, none of which define `is_a?`, so the runtime
      # check is conservative — orthogonal to #310's brace bug). All
      # arms below return the same string so the test passes regardless
      # of which branch the runtime picks.

      class A
      end

      class B
      end

      def normalize(value)
        if value.is_a?(A)
          "ok"
        elsif value.is_a?(B)
          "ok"
        else
          "ok"
        end
      end

      puts normalize(A.new)              # ok
      puts normalize(B.new)              # ok
      puts normalize(42)                 # ok

      # Same shape but as the method's tail-position return — exercises
      # compile_if_return's elsif path (companion fix in the same patch).
      def classify(value)
        if value.is_a?(A)
          1
        elsif value.is_a?(B)
          1
        else
          1
        end
      end

      puts classify(A.new)               # 1
      puts classify(B.new)               # 1
      puts classify(99)                  # 1
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      ok
      ok
      1
      1
      1
    OUT
  end

  it "embedded var" do
    result = ze0(<<~'RUBY')
      # EmbeddedVariableNode -- `"#$gv"`, `"#@iv"`, `"#@@cv"`.
      #
      # Shorthand interpolation form that skips the braces around a
      # bare variable reference. Lowered at parser side to an
      # EmbeddedStatementsNode wrapping the matching variable read,
      # so the codegen reuses the existing interpolation path.

      $global = "global!"
      puts "got: #$global"          # got: global!

      class C
        def initialize
          @ivar = "ivar!"
        end
        def show = puts("got: #@ivar")
      end
      C.new.show                    # got: ivar!
    RUBY

    _(result).must_answer <<~'OUT'
      got: global!
      got: ivar!
    OUT
  end

  it "harness batch 2453 2456" do
    result = ze0(<<~'RUBY')
      # #2453: an array-literal aggregate in argument position (Math.log([..].max, b))
      # must wrap its builder in a statement-expression, not leak it into the call.
      class S
        def initialize(score); @score = score; end
        def order; Math.log([(@score + 1).abs + 2, 1].max, 10); end
      end
      puts S.new(5).order.round(3)

      # #2455: a user module named Random must not clash with the runtime sp_Random.
      module OpenSSL
        module Random
          def self.random_bytes(n)
            out = ""
            i = 0
            while i < n
              # 1..127 (single-byte ASCII, never 0): this test exercises module
              # reopening + dispatch, not binary strings. A 0 byte would embed a NUL
              # (spinel truncates its NUL-terminated storage there) and a 128..255
              # byte forms a multi-byte UTF-8 run that spinel's char-counting #length
              # collapses -- both made .length flaky across builds. ASCII stays one
              # byte == one char, so #length is deterministic.
              out = out + (rand(127) + 1).chr
              i += 1
            end
            out
          end
        end
      end
      puts OpenSSL::Random.random_bytes(4).length

      # #2456: Time minus a poly value (holding a Time) is a Float duration.
      class A2
        def stamp; "2020-01-01"; end
      end
      class B2
        def stamp; Time.at(0).utc; end
      end
      def time_ago(time); (Time.now.utc - time).to_i > 0; end
      def show(x); time_ago(x.stamp); end
      puts show(B2.new)
      puts (show(A2.new) rescue "raised")
    RUBY

    _(result).must_answer <<~'OUT'
      0.903
      4
      true
      raised
    OUT
  end

  it "i1027" do
    result = ze0(<<~'RUBY')
      # Issue #1027: string interpolation of a method that returns sp_String *
      # (the mutable-string type backing `String.new` + `<<`) emitted the
      # pointer cast to long long with `%lld` instead of reading the string
      # contents with `%s` + sp_String_cstr.
      #
      # The dispatch chain in compile_string_interp had arms for "int",
      # "bigint", "float", "string", "bool", "poly", "class", "encoding",
      # "symbol", "exception", "nil", and the array families — but no arm
      # for "mutable_str", so an interpolated sp_String * fell through to
      # the integer fallback and rendered as a pointer address.
      #
      # Direct `<<` on the same value already worked via sp_String_append
      # (the type info exists; only the interp format-spec dispatch missed
      # the arm). Surfaced in roundhouse view emit after a lowering coalesced
      # `io << x; io << y; io << z` runs into `io << "...#{y}..."`-style
      # string-interpolation. The other roundhouse targets interpolate cleanly
      # because their string primitives accept the mutable variant directly;
      # only spinel needed the missing arm.

      module M
        def self.make
          s = String.new
          s << "hello"
          s
        end
      end

      puts "[#{M.make}]"
    RUBY

    _(result).must_answer "[hello]\n"
  end

  it "i898" do
    result = ze0(<<~'RUBY')
      # Random uses a different RNG than CRuby, so values differ; the test
      # checks the interface (types, ranges, reproducibility), not exact
      # sequence parity. bytes#length is avoided because spinel has no
      # ASCII-8BIT encoding — String#length counts UTF-8 chars, so a random
      # byte buffer's char-count is not its byte-count.
      r = Random.new(42)
      puts r.rand(100).class
      puts r.rand.class
      puts (r.rand(100) >= 0 && r.rand(100) < 100)
      puts r.bytes(4).class

      # Same seed -> same stream.
      a = Random.new(7)
      b = Random.new(7)
      puts (a.rand(1000000) == b.rand(1000000))

      # Different seeds -> (almost surely) different draws.
      c = Random.new(1)
      d = Random.new(2)
      puts (c.rand(1000000) != d.rand(1000000))

      # Class-method rand form.
      puts Random.rand(100).class
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Float
      true
      String
      true
      true
      Integer
    OUT
  end

  it "identifier outside the ascii alphabet" do
    result = ze0(<<~'RUBY')
      # Ruby treats every byte above ASCII as an identifier byte, so this ivar is
      # legal (fastimage ships one). A generated identifier takes a narrower
      # alphabet, so such a name must be mangled rather than passed through.

      @width, @height´ = nil
      @height´ = 7
      p [@width, @height´]

      # A class-level ivar named after a compiler keyword takes an escaped
      # spelling, which then has to survive being upper-cased into a global's name.
      class Shape
        def self.type = @type
        def self.type=(v)
          @type = v
        end
      end
      Shape.type = "circle"
      p Shape.type
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, 7]
      "circle"
    OUT
  end

  it "initialize family visibility" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # initialize, initialize_copy and friends are not private by default.
      #
      class Hooked
        attr_accessor :v
        def initialize(v); @v = v; end
        def initialize_copy(src); @v = src.v; end
      end
      p Hooked.private_method_defined?(:initialize_copy)

      p Hooked.public_method_defined?(:initialize_copy)     # Ruby: false   Spinel: true
      class Plain; def initialize(v); @v = v; end; end
      p Plain.private_method_defined?(:initialize_copy)     # Ruby: true    Spinel: false

      class Plain2
        attr_accessor :v
        def initialize(v); @v = v; end
      end
      o001 = Plain2.new(1); o001.send(:initialize_copy, Plain2.new(5)); p o001.v   # => 1
      p Plain2.new(1).respond_to?(:initialize_copy, true)                          # => true
      p Hooked.new(1).respond_to?(:initialize_copy, true)                          # => true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      1
      true
      true
    OUT
  end

  it "instance class new" do
    result = ze0(<<~'RUBY')
      S = Struct.new(:a, :b)
      s = S.new(1, 2)
      t = s.class.new(3, 4)
      p [t.a, t.b]
      p t.class

      D = Data.define(:x, :y)
      d = D.new(x: 1, y: 2)
      e = d.class.new(x: 5, y: 6)
      p [e.x, e.y]

      class Plain
        def initialize(v); @v = v; end
        def v; @v; end
      end
      pl = Plain.new(1)
      p pl.class.new(9).v

      Str = Struct.new(:name)
      sn = Str.new("a")
      p sn.class.new("b").name
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      S
      [5, 6]
      9
      "b"
    OUT
  end

  it "issue class variable toplevel scope" do
    result = ze0(<<~'RUBY')
      # A class variable (`@@cv`) assigned inside a `Class.new { ... }` block
      # should raise RuntimeError ("class variable access from toplevel"): class
      # variables resolve through the LEXICAL scope, and a `do...end` block (unlike
      # a literal `class ... end`) doesn't open a new lexical scope, so `@@cv1`
      # resolves to the top-level scope instead of the new anonymous class. zeo
      # silently accepts the assignment instead of raising.
      klass = Class.new do
        @@cv1 = 1
      end
      p klass.class_variables
    RUBY

    _(result).must_answer "", stderr: "lang/classes/classes_test.rb:8:in 'block in <main>': class variable access from toplevel (RuntimeError)\n\tfrom lang/classes/classes_test.rb:7:in 'Class#initialize'\n\tfrom lang/classes/classes_test.rb:7:in 'Class#new'\n\tfrom lang/classes/classes_test.rb:7:in '<main>'\n", status: 1
  end

  it "masgn classvar target" do
    result = ze0(<<~'RUBY')
      # Class-variable multi-assignment targets (`@@a, @@b = 1, 2`). Each
      # ClassVariableTargetNode registers and initializes its slot from the
      # i-th literal of the right-hand side, mirroring a plain `@@a = 1`.
      class C
        @@a, @@b = 1, 2
        @@s, @@t = "x", "y"
        def self.show
          p [@@a, @@b]
          p [@@s, @@t]
          p @@a + @@b
        end
      end
      C.show
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      ["x", "y"]
      3
    OUT
  end

  it "nested classes reopen through both definition forms" do
    result = ze0(<<~'RUBY')
      module Store
        class Item
          def tag
            "tagged"
          end
        end
      end

      module Store
        class Item
          def more
            "reopened nested"
          end
        end
      end

      class Store::Item
        def qual
          "qualified reopen"
        end
      end

      i = Store::Item.new
      puts i.tag
      puts i.more
      puts i.qual
    RUBY

    _(result).must_answer <<~'OUT'
      tagged
      reopened nested
      qualified reopen
    OUT
  end

  it "new binds optional initialize params" do
    result = ze0(<<~'RUBY')
      # The `.new` binding fix: one `initialize(items = nil)` serving both
      # `Bag.new` and `Bag.new([1])` (oracle: 0, 1).

      class Bag
        def initialize(items = nil)
          @n = items.nil? ? 0 : 1
        end
        def n
          @n
        end
      end
      puts Bag.new.n
      puts Bag.new([1]).n
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
    OUT
  end

  it "new on a class with no initialize rejects arguments" do
    result = ze0(<<~'RUBY')
      # `Object#initialize` takes none, so passing any is an ArgumentError --
      # it was silently DROPPING them and constructing happily. Rescuable and
      # raised at runtime (plan G1), covering both the static `.new` path and
      # the dynamic one through a class-valued variable.

      class Bare; end
      begin
        Bare.new(1, 2)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
      k = Bare
      begin
        k.new(9)
      rescue ArgumentError => e
        puts "dyn: #{e.message}"
      end
      p Bare.new.class
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: wrong number of arguments (given 2, expected 0)
      dyn: wrong number of arguments (given 1, expected 0)
      Bare
    OUT
  end

  it "object new sentinel" do
    result = ze0(<<~'RUBY')
      # Issue #63: `Object.new.freeze` constants used as identity sentinels
      # generated `sp_Object *` declarations against a type that didn't exist
      # in the runtime, plus the `freeze` call fell through the dispatcher
      # and the constant was assigned `0` (NULL) instead of the new object.
      # After the fix:
      #   - lib/sp_runtime.h defines sp_Object and sp_Object_new (a fresh
      #     GC-managed allocation per call so `==` is identity)
      #   - codegen emits sp_Object_new() for `Object.new`
      #   - the receiver-passthrough `freeze` arm in compile_object_method_expr
      #     keeps the chain alive so the constant gets the actual pointer.

      NO_DIRECT_CALL = Object.new.freeze
      HASH_MISS = Object.new.freeze

      # Distinct sentinels: their addresses differ.
      puts NO_DIRECT_CALL == HASH_MISS         # false
      puts NO_DIRECT_CALL == NO_DIRECT_CALL    # true
      puts HASH_MISS == HASH_MISS              # true
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
    OUT
  end

  it "open class" do
    result = ze0(<<~'RUBY')
      # Test: open class support for built-in types
      # Extension methods on String, Integer, Float

      class String
        def shout
          upcase + "!"
        end

        def whisper
          downcase + "..."
        end
      end

      class Integer
        def double
          self * 2
        end

        def square
          self * self
        end
      end

      puts "hello".shout
      puts "HELLO WORLD".whisper
      puts 5.double
      puts 7.square
    RUBY

    _(result).must_answer <<~'OUT'
      HELLO!
      hello world...
      10
      49
    OUT
  end

  it "open class bool builtin" do
    result = ze0(<<~'RUBY')
      class TrueClass
        def flag_name
          "true:" + self.class.name
        end
      end

      class FalseClass
        def flag_name
          "false:" + self.class.name
        end
      end

      class Object
        def object_flag
          "object:" + self.class.name
        end
      end

      puts true.flag_name
      puts false.flag_name

      t = 1 == 1
      f = 1 == 2
      puts t.flag_name
      puts f.flag_name

      puts true.object_flag
      puts false.object_flag
    RUBY

    _(result).must_answer <<~'OUT'
      true:TrueClass
      false:FalseClass
      true:TrueClass
      false:FalseClass
      object:TrueClass
      object:FalseClass
    OUT
  end

  it "open class default arg" do
    result = ze0(<<~'RUBY')
      class String
        def pad(n = 3)
          self + ("x" * n)
        end

        def bang
          self + "!"
        end
      end

      class Integer
        def bump(by = 10)
          self + by
        end
      end

      class TrueClass
        def truthy(x = 7)
          x
        end
      end

      module Padder
        def wrap(s = "*")
          s + self + s
        end
      end

      class String
        include Padder
      end

      # Optional arg omitted -> default filled in.
      puts "a".pad
      # Optional arg supplied explicitly -> default ignored.
      puts "a".pad(1)
      # Zero-explicit-param reopen still works (no spurious extra arg).
      puts "hi".bang
      # Integer reopen, default omitted and supplied.
      puts 5.bump
      puts 5.bump(2)
      # Bool reopen, default omitted and supplied.
      puts true.truthy
      puts true.truthy(9)
      # Module included into a builtin, default omitted and supplied.
      puts "in".wrap
      puts "in".wrap("-")
    RUBY

    _(result).must_answer <<~'OUT'
      axxx
      ax
      hi!
      15
      7
      7
      9
      *in*
      -in-
    OUT
  end

  it "poly join value type receiver" do
    result = ze0(<<~'RUBY')
      # The poly `join` dispatch grew a user-class arm in ceaea73e (#4083's fix). That
      # arm passed the boxed receiver as a POINTER; a value-type class takes self by
      # value, and the C build stopped (#4091). The sibling arm at the default
      # dispatch has dereferenced it since #2441.
      #
      # The class has to STAY a value type for this to bite, so nothing here hands a
      # P around by reference -- an extra `show(P.new(...))` was enough to take it
      # off the value-type path and the test stopped covering the bug.

      class P
        def initialize(b)
          @b = b
        end

        def join(part)
          P.new(@b + "/" + part)
        end

        def to_s
          @b
        end
      end

      def show(v)
        v.join(", ")
      end

      puts show([1, 2])
      puts show(["a", "b"])
      puts P.new("x").join("y").to_s
    RUBY

    _(result).must_answer <<~'OUT'
      1, 2
      a, b
      x/y
    OUT
  end

  it "poly return value class" do
    result = ze0(<<~'RUBY')
      # Issue #118: a method that returns instances of two or more value-
      # type-eligible classes per branch used to crash the C compile. Both
      # A and B detected as value-type (no attr_writer / no mutator) →
      # `sp_A_new(...)` / `sp_B_new(...)` returned the struct by value →
      # `sp_box_obj(struct, ci)` tried to put a struct into `sp_RbVal.v.p`
      # (`void *`), and the unboxing dispatch passed `void *` to a method
      # taking its receiver by value.
      #
      # Fix: detect_poly_returned_types collects every class constructed
      # inside a poly-returning method and excludes those classes from the
      # value-type optimization, so they stay heap-allocated and the
      # existing poly-return / sp_RbVal plumbing handles them as pointers.

      class A
        def initialize(v); @v = v; end
        def label; "A:" + @v; end
      end

      class B
        def initialize(v); @v = v; end
        def label; "B:" + @v; end
      end

      def pick(flag)
        if flag
          A.new("yes")
        else
          B.new("no")
        end
      end

      puts pick(true).label    # A:yes
      puts pick(false).label   # B:no

      # A `case`/`when` poly return — same shape, different control flow.
      def by_kind(k)
        case k
        when 0 then A.new("zero")
        when 1 then B.new("one")
        else        A.new("many")
        end
      end

      puts by_kind(0).label    # A:zero
      puts by_kind(1).label    # B:one
      puts by_kind(9).label    # A:many

      # Method invocation that returns a different type per class — the
      # poly receiver dispatches through the cls_id table generated for
      # explicit `def`-defined methods on each class.
      class P
        def initialize(n); @n = n; end
        def double; @n * 2; end
      end

      class Q
        def initialize(n); @n = n; end
        def double; @n + 100; end
      end

      def numeric(flag)
        flag ? P.new(7) : Q.new(7)
      end

      puts numeric(true).double    # 14
      puts numeric(false).double   # 107
    RUBY

    _(result).must_answer <<~'OUT'
      A:yes
      B:no
      A:zero
      B:one
      A:many
      14
      107
    OUT
  end

  it "primitive eq user class" do
    result = ze0(<<~'RUBY')
      # Cross-type equality between a primitive and a user-class, both directions.

      # Box -- is_a? short-circuits, so only the typed-arg compile path
      # (under -Werror) and the primitive-vs-obj fold get exercised.
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
        def ==(other)
          return false unless other.is_a?(Box)
          @v == other.v
        end
      end

      b = Box.new(5)
      ms = String.new("x") # mutable_str — distinct codegen type from string literal

      # Cross-type pairs -> false (each primitive, both directions).
      puts b == 5
      puts b == 1.5
      puts b == "x"
      puts b == ms
      puts b == :foo
      puts b == true
      puts b == false
      puts b == nil
      puts 5 == b
      puts 1.5 == b
      puts "x" == b
      puts ms == b
      puts :foo == b
      puts true == b
      puts false == b
      puts nil == b

      # Same pairs negated -> true.
      puts b != 5
      puts b != 1.5
      puts b != "x"
      puts b != ms
      puts b != :foo
      puts b != true
      puts b != false
      puts b != nil
      puts 5 != b
      puts 1.5 != b
      puts "x" != b
      puts ms != b
      puts :foo != b
      puts true != b
      puts false != b
      puts nil != b

      # Wrapper -- ==(other) reads `other`, so the boxing round-trip is
      # exercised end-to-end (not just the is_a? short-circuit).
      class Wrapper
        def initialize(v); @v = v; end
        def ==(other); @v == other; end
      end

      # Same type, same value -> true.
      puts Wrapper.new(5)       == 5
      puts Wrapper.new(1.5)     == 1.5
      puts Wrapper.new("hello") == "hello"
      puts Wrapper.new(:foo)    == :foo
      puts Wrapper.new(true)    == true
      puts Wrapper.new(false)   == false
      puts Wrapper.new(nil)     == nil

      # Same type, different value -> false.
      puts Wrapper.new(5)       == 6
      puts Wrapper.new(1.5)     == 2.5
      puts Wrapper.new("hello") == "world"
      puts Wrapper.new(:foo)    == :bar
      puts Wrapper.new(true)    == false

      # Reverse direction stays primitive-strict (MRI semantics).
      puts 5       == Wrapper.new(5)
      puts "hello" == Wrapper.new("hello")

      # != synthesis through the value-flow path.
      puts Wrapper.new(5) != 5
      puts Wrapper.new(5) != 6

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
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
      false
      false
      true
      false
      false
      true
      done
    OUT
  end

  it "private initialize owners" do
    result = ze0(<<~'RUBY')
      # Two patterns behind 56 of the census's private `owner` rows, and the half of
      # them this closes.
      #
      # CRuby declares a private `initialize` on every class whose constructor takes
      # arguments `Exception`'s does not, and reflection has to say so.
      # zeo's exception tree already registered each body -- flat dispatch puts a row
      # on every id -- but marked only `Exception` as the OWNER, so all eleven
      # subclasses named `Exception` back.
      #
      # The copy hooks are the second pattern: ruby owns `initialize_copy`,
      # `initialize_dup` and `initialize_clone` on KERNEL. zeo defined the first as a
      # top-level `def` in the compiler prelude, which lands in Object's own_methods
      # -- making it the one name in `Object.private_instance_methods(false)`, where
      # ruby answers `[]`, and leaving the other two absent entirely.

      def t(label)
        v = yield
        puts "#{label} => #{v.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label} !! #{e.class}: #{e.message}"
      end

      OWNERS = [FrozenError, Interrupt, KeyError, NameError, NoMatchingPatternKeyError,
                NoMethodError, SignalException, SyntaxError, SystemCallError, SystemExit,
                UncaughtThrowError].freeze

      p OWNERS.map { |c| [c.to_s, c.private_instance_methods(false).sort] }
      p OWNERS.map { |c| c.instance_method(:initialize).owner.to_s }

      # A class that does NOT declare its own still points at Exception, which is
      # what makes the list above a real distinction rather than a blanket mark.
      p([RuntimeError, StandardError, ArgumentError].map do |c|
        [c.private_instance_methods(false), c.instance_method(:initialize).owner.to_s]
      end)

      # Each of those initializers takes the arguments that earned it the row.
      t("FrozenError") { e = FrozenError.new("f", receiver: [1]); [e.message, e.receiver] }
      t("NoMethodError") { e = NoMethodError.new("m", :nm, [1, 2]); [e.message, e.name, e.args] }
      t("SyntaxError") { e = SyntaxError.new("s"); [e.message, e.path] }
      t("NameError") { e = NameError.new("n", :nn); [e.message, e.name] }
      t("KeyError") { e = KeyError.new("k", receiver: {}, key: :z); [e.message, e.key] }
      t("SystemExit") { e = SystemExit.new(3, "bye"); [e.message, e.status] }
      t("Interrupt") { e = Interrupt.new; [e.message, e.signo] }
      t("SignalException") { e = SignalException.new("TERM"); [e.message, e.signm] }
      t("SystemCallError") { e = SystemCallError.new("s", 2); [e.class.to_s, e.errno] }

      # `Exception` keeps the two rows only IT owns.
      t("Exception private") { Exception.private_instance_methods(false).sort }

      # ---- the copy hooks --------------------------------------------------------
      t("Object private") { Object.private_instance_methods(false).sort }
      t("Kernel copy hooks") { Kernel.private_instance_methods(false).grep(/^initialize/).sort }
      t("owner copy") { Object.instance_method(:initialize_copy).owner }
      t("owner dup") { Object.instance_method(:initialize_dup).owner }
      t("owner clone") { Object.instance_method(:initialize_clone).owner }
      t("arities") do
        %i[initialize_copy initialize_dup initialize_clone].map { |m| Object.instance_method(m).arity }
      end
      t("private?") { Object.private_method_defined?(:initialize_copy) }
      t("respond_to?") { Object.new.respond_to?(:initialize_copy, true) }

      # A user override still runs, and its bare `super` still resolves -- the reason
      # the hook was in the prelude at all.
      class Box
        attr_accessor :v

        def initialize(v) = (@v = v)

        def initialize_copy(orig)
          super
          @v = orig.v.dup
        end
      end
      b = Box.new(+"hi")
      c = b.dup
      c.v << "!"
      t("override ran") { [b.v, c.v] }
      t("clone too") { d = b.clone; d.v << "?"; [b.v, d.v] }

      class Plain
        attr_accessor :v
        def initialize(v) = (@v = v)
      end
      t("shallow dup") { p1 = Plain.new([1]); p2 = p1.dup; [p1.v.equal?(p2.v), p1.equal?(p2)] }
      t("frozen clone") { o = Plain.new(1).freeze; [o.clone.frozen?, o.dup.frozen?] }
    RUBY

    _(result).must_answer <<~'OUT'
      [["FrozenError", [:initialize]], ["Interrupt", [:initialize]], ["KeyError", [:initialize]], ["NameError", [:initialize]], ["NoMatchingPatternKeyError", [:initialize]], ["NoMethodError", [:initialize]], ["SignalException", [:initialize]], ["SyntaxError", [:initialize]], ["SystemCallError", [:initialize]], ["SystemExit", [:initialize]], ["UncaughtThrowError", [:initialize]]]
      ["FrozenError", "Interrupt", "KeyError", "NameError", "NoMatchingPatternKeyError", "NoMethodError", "SignalException", "SyntaxError", "SystemCallError", "SystemExit", "UncaughtThrowError"]
      [[[], "Exception"], [[], "Exception"], [[], "Exception"]]
      FrozenError => ["f", [1]]
      NoMethodError => ["m", :nm, [1, 2]]
      SyntaxError => ["s", nil]
      NameError => ["n", :nn]
      KeyError => ["k", :z]
      SystemExit => ["bye", 3]
      Interrupt => ["Interrupt", 2]
      SignalException => ["SIGTERM", "SIGTERM"]
      SystemCallError => ["Errno::ENOENT", 2]
      Exception private => [:initialize, :method_missing, :respond_to_missing?]
      Object private => [:t]
      Kernel copy hooks => [:initialize_clone, :initialize_copy, :initialize_dup]
      owner copy => Kernel
      owner dup => Kernel
      owner clone => Kernel
      arities => [1, 1, -1]
      private? => true
      respond_to? => true
      override ran => ["hi", "hi!"]
      clone too => ["hi", "hi?"]
      shallow dup => [true, false]
      frozen clone => [true, false]
    OUT
  end

  it "protected reach in a runtime class" do
    result = ze0(<<~'RUBY')
      # A `protected` method must be reachable from another instance of the same
      # class. That works for a compiled `class` body and fails for a body written
      # inside `Class.new do ... end`.
      #
      # `protected` asks whether the CALLER's `self` is a kind of the method's owner,
      # and zeo answers it from a class baked into the call site at compile time
      # (`codegen::call::visibility`, recorded in the `CallSite`). Inside a
      # `Class.new` block the enclosing lexical class is `Object` -- the class the
      # body will belong to does not exist until the block runs -- so the site records
      # `Object`, which is not a kind of the runtime class, and the call is refused.
      #
      # `tests/gaps/protected_reach_from_instance_eval.rb` is the sibling: there
      # `self` changes at run time without changing the lexical class. Here the
      # lexical class is simply not the owner yet. Both want the same thing -- a site
      # whose caller class is unknown at compile time must ask at run time.

      class Compiled
        def cmp(o) = o.secret
        protected def secret = 7
      end
      p Compiled.new.cmp(Compiled.new)

      Runtime = Class.new do
        def cmp(o) = o.secret
        protected def secret = 8
      end
      p Runtime.new.cmp(Runtime.new)

      # The same through a separate `protected :name` statement.
      Later = Class.new do
        def cmp(o) = o.secret
        def secret = 9
        protected :secret
      end
      p Later.new.cmp(Later.new)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      8
      9
    OUT
  end

  it "reading an undefined class variable" do
    result = ze0(<<~'RUBY')
      # Reading a class variable that was never assigned raises NameError
      # ("uninitialized class variable @@missing in ..."). zeo's cvar read answers
      # nil instead.
      class CvarHost
        def self.read
          @@missing
        rescue NameError => e
          "NameError: #{e.message}"
        end
      end

      puts CvarHost.read.inspect
      puts defined?(@@top_missing).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "NameError: uninitialized class variable @@missing in CvarHost"
      nil
    OUT
  end

  it "reopened builtin answers from its own line" do
    result = ze0(<<~'RUBY')
      # The widened sweep behind `a_later_def_on_a_builtin_reaches_back`: every
      # shape a compile-time reopen of a builtin can take, called from ABOVE its own
      # `class Foo ... end` and again from below.
      #
      # A name the builtin never had raises ruby's plain `undefined method` before
      # the reopen -- there is no row to forward to, and "no superclass method"
      # would name a mechanism the program never wrote. Arguments and blocks reach
      # the forwarded row. A reopened MODULE counts too: its rows materialize onto
      # every includer, so the flag is keyed by the DEFINING class and every copy
      # shares it. A reopen inside a branch that never runs never goes live at all,
      # which is exactly right.

      def try(label)
        p [label, yield]
      rescue NoMethodError, ArgumentError, TypeError => e
        p [label, :raised, e.class.to_s, e.message]
      end

      # 1. a brand-new name the builtin never had
      try(:new_before) { [].brand_new }
      class Array
        def brand_new = :brand_new
      end
      try(:new_after)  { [].brand_new }

      # 2. args and blocks forwarded to the native row
      try(:map_before) { [1, 2].map { |x| x * 2 } }
      try(:pop_before) { a = [1, 2, 3]; [a.pop(2), a] }
      try(:push_before){ [1].push(2, 3) }
      try(:fetch_kw)   { [1].fetch(9) { |i| [:blk, i] } }
      class Array
        def map = :own_map
        def pop(*) = :own_pop
        def push(*) = :own_push
        def fetch(*) = :own_fetch
      end
      try(:map_after)  { [1, 2].map { |x| x * 2 } }

      # 3. a module reopen
      try(:mod_before) { [1, 2].each_slice(1).to_a }
      module Enumerable
        def each_slice(*) = :own_slice
      end
      try(:mod_after)  { [1, 2].each_slice(1) }

      # 4. a reopen inside a conditional that never runs
      try(:cond_before) { "x".upcase }
      if false
        class String
          def upcase = :never
        end
      end
      try(:cond_after)  { "x".upcase }

      # 5. a reopen with super where a real super target exists
      class Hash
        def keys = [:own, super]
      end
      try(:hash_keys)   { { a: 1 }.keys }
    RUBY

    _(result).must_answer <<~'OUT'
      [:new_before, :raised, "NoMethodError", "undefined method 'brand_new' for an instance of Array"]
      [:new_after, :brand_new]
      [:map_before, [2, 4]]
      [:pop_before, [[2, 3], [1]]]
      [:push_before, [1, 2, 3]]
      [:fetch_kw, [:blk, 9]]
      [:map_after, :own_map]
      [:mod_before, [[1], [2]]]
      [:mod_after, :own_slice]
      [:cond_before, "X"]
      [:cond_after, "X"]
      [:hash_keys, :raised, "NoMethodError", "super: no superclass method 'keys' for an instance of Hash"]
    OUT
  end

  it "returned class needs no name" do
    result = ze0(<<~'RUBY')
      # Every line here reaches a builtin class this program NAMES NOWHERE.
      #
      # The compiler decides which builtin method tables the binary carries
      # (`analyze::class_reach`), and a class it drops that the program does reach
      # aborts at the first dispatch. Constants are the easy channel; this is the
      # hard one -- a row RETURNS an instance of a class no scan of the source can
      # see. Keep it name-free: writing the class name here would test nothing.

      def frame = caller_locations(1, 1)
      p frame.first.class

      p binding.class
      p method(:p).class
      p 1.quo(3)
      p 1.quo(3).class
      p "x".encoding.class
      p [1, 2].lazy.first(1)
      p [1, 2].lazy.class
      p [1, 2, 3].chunk_while { |a, b| b == a + 1 }.to_a
      p [1, 2].each_slice(1).class
      p (1..10).step(3).class
      p 2.to_c.class

      srand(7)
      p rand(2).class

      module Louder
        refine String do
          def shout = upcase
        end
      end
      using Louder
      p "hi".shout

      p __dir__.class
    RUBY

    _(result).must_answer <<~'OUT'
      Thread::Backtrace::Location
      Binding
      Method
      (1/3)
      Rational
      Encoding
      [1]
      Enumerator::Lazy
      [[1, 2, 3]]
      Enumerator
      Enumerator::ArithmeticSequence
      Complex
      Integer
      "HI"
      String
    OUT
  end

  it "runtime class body directives" do
    result = ze0(<<~'RUBY')
      # A class built at runtime runs its body as an ordinary block, so every
      # class-body directive has to be rewritten into the equivalent self-send.
      module Greeting
        def greet = "hello from #{self.class.name}"
      end

      module Loud
        def greet = super.upcase
      end

      Speaker = Class.new do
        include Greeting
        prepend Loud

        def secret = "shh"
        private :secret

        def spoken = greet
        alias_method :say, :spoken
      end

      p Speaker.new.greet
      p Speaker.new.say
      p Speaker.private_instance_methods(false).include?(:secret)
      p Speaker.ancestors.first(3).map(&:to_s)

      module Shout
        def shout(word) = "#{word}!"
      end

      Helpers = Module.new do
        include Shout
        module_function :shout
      end

      p Helpers.shout("go")
      p Helpers.singleton_methods.sort
      p Helpers.private_instance_methods(false)

      Trimmed = Class.new(Speaker) do
        undef_method :spoken
      end
      p Trimmed.new.respond_to?(:spoken)

      # A nested class inside a runtime body becomes a runtime class of its own --
      # and lands at TOP level, since a block opens no lexical scope for constants.
      Outer = Class.new do
        Inner = Class.new do
          def label = "inner"
        end
        def label = "outer"
      end
      p Outer.new.label
      p Inner.new.label
    RUBY

    _(result).must_answer <<~'OUT'
      "HELLO FROM SPEAKER"
      "HELLO FROM SPEAKER"
      true
      ["Loud", "Speaker", "Greeting"]
      "go!"
      [:shout]
      [:shout]
      false
      "outer"
      "inner"
    OUT
  end

  it "runtime class names its own frames" do
    result = ze0(<<~'RUBY')
      # A method of a RUNTIME-minted class names its frame after that class.
      #
      # A `def` inside such a body is lifted to a top-level method and installed on
      # the class afterwards, so the emitter bakes `Object#name` -- the only owner it
      # can see. Ruby names the frame from the class's name AT RAISE TIME, and that
      # is not a compile-time fact: the same anonymous class reports a bare method
      # name while held in a local, and `K#m` once a constant assignment names it.
      #
      # So the installer hands the label to the next frame push. The handover is
      # ONE-SHOT and replaces only the `Object#` fallback, and both narrowings are
      # load-bearing -- see the last two sections.

      def frames(label, n = 1)
        yield
      rescue => e
        puts "#{label}:"
        puts e.backtrace.first(n).map { |l| "  " + l.sub(%r{\A.*?([^/]+):}, '\1:') }
      end

      # --- named by a constant assignment
      K = Class.new do
        def m
          raise "k"
        end
      end
      frames("constant-named") { K.new.m }

      # --- anonymous: ruby prints the bare method name, not an invented owner
      anon = Class.new do
        def m
          raise "anon"
        end
      end
      frames("anonymous") { anon.new.m }

      # --- a `class X < RuntimeValue` body, which takes the same lift
      class Sub < K
        def n
          raise "sub"
        end
      end
      frames("subclass of a runtime class") { Sub.new.n }

      # --- a module minted the same way
      M = Module.new do
        def mm
          raise "mod"
        end
      end
      class UsesM
        include M
      end
      frames("runtime module method") { UsesM.new.mm }

      # --- a nested runtime class under a runtime namespace
      NS = Class.new
      class NS::Inner < K
        def deep
          raise "deep"
        end
      end
      frames("nested under a runtime namespace") { NS::Inner.new.deep }

      # --- THE ONE-SHOT MUST NOT LEAK. A top-level `def` called from inside a
      # runtime class's method keeps its own `Object#` label; matching on the name
      # alone would have renamed it after the calling class.
      def helper
        raise "helper"
      end
      Caller = Class.new do
        def outer
          helper
        end
      end
      frames("top-level def called from a runtime method", 2) { Caller.new.outer }

      # --- A GENUINE `define_method` BLOCK keeps its block label. The same install
      # path carries both, so overriding unconditionally renamed every one of these.
      Blocky = Class.new do
        define_method(:dm) { raise "dm" }
      end
      frames("define_method block") { Blocky.new.dm }

      # --- an ordinary compiled class is untouched
      class Plain
        def p1
          raise "plain"
        end
      end
      frames("ordinary compiled class") { Plain.new.p1 }
    RUBY

    _(result).must_answer <<~'OUT'
      constant-named:
        classes_test.rb:23:in 'K#m'
      anonymous:
        classes_test.rb:31:in 'm'
      subclass of a runtime class:
        classes_test.rb:39:in 'Sub#n'
      runtime module method:
        classes_test.rb:47:in 'M#mm'
      nested under a runtime namespace:
        classes_test.rb:59:in 'NS::Inner#deep'
      top-level def called from a runtime method:
        classes_test.rb:68:in 'Object#helper'
        classes_test.rb:72:in 'Caller#outer'
      define_method block:
        classes_test.rb:80:in 'block (2 levels) in <main>'
      ordinary compiled class:
        classes_test.rb:87:in 'Plain#p1'
    OUT
  end

  it "same leaf class name in two namespaces stays distinct" do
    result = ze0(<<~'RUBY')
      module A1
        class Widget
          def tag
            "a"
          end
        end
      end

      module B1
        class Widget
          def tag
            "b"
          end
        end
      end

      puts A1::Widget.new.tag
      puts B1::Widget.new.tag
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
    OUT
  end

  it "scoped builtin class values" do
    result = ze0(<<~'RUBY')
      # ::-scoped builtin class constants as first-class values (#2840), and
      # stat handles reporting File::Stat (#2841).
      p Math::DomainError
      p Math::DomainError.superclass
      p Process::Status
      p Process::Status.superclass
      begin; raise Math::DomainError, "d"; rescue Math::DomainError => e; p e.class; end
      q = "/tmp/sp_stat_probe"
      File.write(q, "hi")
      p File.stat(q).class
      File.open(q) { |f| p f.stat.class }
      p File.stat(q).size
      File.delete(q)
    RUBY

    _(result).must_answer <<~'OUT'
      Math::DomainError
      StandardError
      Process::Status
      Object
      Math::DomainError
      File::Stat
      File::Stat
      2
    OUT
  end

  it "self class new construction" do
    result = ze0(<<~'RUBY')
      # `self.class.new(args)` in an instance method of a leaf class (no
      # subclasses) constructs the enclosing class statically — the
      # idiomatic functional-update pattern (e.g. AST::Node#updated).
      class Node
        attr_reader :children
        def initialize(children = [])
          @children = children.to_a.freeze
        end
        def with(more)
          self.class.new(@children + more)
        end
      end
      n = Node.new([Node.new, Node.new])
      m = n.with([Node.new])
      puts m.children.size
      puts n.children.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
    OUT
  end

  it "superclass must be a plain class" do
    result = ze0(<<~'RUBY')
      # Superclass validation: a Module raises TypeError "superclass must be an
      # instance of Class (given an instance of Module)" (zeo: NoMethodError on
      # 'inherited'); a non-class names the given class the same way (zeo's
      # message is the older "must be a Class"); and `Class.new(Class)` is
      # refused outright ("can't make subclass of Class") where zeo mints one.
      # (Found by the 2026-08-24 probe sweep.)
      def show
        yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { Class.new(Comparable) }
      show { Class.new(1) }
      show { Class.new(Class) && puts("subclass of Class minted") }
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: superclass must be an instance of Class (given an instance of Module)
      TypeError: superclass must be an instance of Class (given an instance of Integer)
      TypeError: can't make subclass of Class
    OUT
  end

  it "user negation methods" do
    result = ze0(<<~'RUBY')
      class Neg
        def initialize(b); @b = b; end
        def !; !@b; end
        def !=(o); "custom-ne"; end
      end
      p(!Neg.new(false))
      p(Neg.new(true) != Neg.new(true))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "custom-ne"
    OUT
  end

  it "void value begin writer tail" do
    result = ze0(<<~'RUBY')
      # A value-position `begin` whose tail is a writer call (or nil) is
      # void/nil-typed: the begin result temp -- and the ivar slot it flows into --
      # must widen to poly instead of C `void` (error: incomplete type 'void').
      class Boot
        def name=(v)
          @n = v
          nil
        end

        def n
          @n
        end

        def init_a(v)
          @a = begin
            self.name = v
            nil
          end
        end

        def a
          @a
        end

        def init_b(v)
          @b = begin
            self.name = v
          end
        end
      end

      b = Boot.new
      b.init_a(7)
      p b.a
      p b.n

      b2 = Boot.new
      b2.init_b(9)
      p b2.n
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      7
      9
    OUT
  end

  it "void value case writer arm" do
    result = ze0(<<~'RUBY')
      # A value-position `case` whose arms are writer calls (or nil) is
      # void/nil-typed: the case result temp must widen to poly instead of being
      # declared `void _crN` (error: incomplete type 'void'). Unmatched reads nil.
      class Conf
        def name=(v)
          @n = v
          nil
        end

        def n
          @n
        end

        def set(k, v)
          @x = case k
               when 1 then self.name = v
               when 2 then self.name = v * 2
               end
        end

        def x
          @x
        end

        def nil_arm(k)
          case k
          when 1 then nil
          end
        end
      end

      c = Conf.new
      c.set(3, 5)
      p c.x
      p c.n
      c.set(1, 5)
      p c.n
      c.set(2, 5)
      p c.n
      p c.nil_arm(1)
      p c.nil_arm(2)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      5
      10
      nil
      nil
    OUT
  end

  it "void value if writer arm" do
    result = ze0(<<~'RUBY')
      # A value-position `if`/ternary whose arm is a writer call (doom's
      # `self.fullscreen = value if respond_to?(...)` used as an expression) is
      # void-typed: the result temp must widen to poly instead of being declared
      # `void _tN` (error: incomplete type 'void'). The untaken branch reads nil.
      class Win
        def fullscreen=(v)
          @fs = v
          nil
        end

        def fs
          @fs
        end

        def apply(v, cond)
          @last = (self.fullscreen = v if cond)
        end

        def last
          @last
        end

        def tern(v, cond)
          y = (cond ? (self.fullscreen = v) : nil)
          y
        end

        def local_if(v, cond)
          y = (self.fullscreen = v if cond)
          y
        end
      end

      w = Win.new
      w.apply(true, true)
      p w.fs

      w2 = Win.new
      w2.apply(true, false)
      p w2.last
      p w2.fs

      w3 = Win.new
      p w3.tern(5, false)
      p w3.fs
      w3.tern(5, true)
      p w3.fs

      w4 = Win.new
      p w4.local_if(9, false)
      w4.local_if(9, true)
      p w4.fs
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      nil
      nil
      nil
      5
      nil
      9
    OUT
  end
end
