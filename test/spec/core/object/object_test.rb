# frozen_string_literal: true

require "spec_helper"

describe "Object programs" do
  it "binding copy keeps the scope and its own new locals" do
    result = ze0(<<~'RUBY')
      # Binding#dup and #clone name the same scope, but a local set on the copy
      # is its own, as binding_copy makes it. A Binding inspects as Kernel does.

      x = 1
      b = binding
      c = b.dup
      d = b.clone
      c.local_variable_set(:x, 2)
      p x, b.local_variable_get(:x), d.local_variable_get(:x)
      c.local_variable_set(:y, 3)
      p b.local_variable_defined?(:y), c.local_variable_defined?(:y), d.local_variable_defined?(:y)
      p b.inspect.match?(/\A#<Binding:0x\h{16}>\z/), b.to_s == b.inspect
      b.freeze
      p b.clone.frozen?, b.dup.frozen?
      p Binding.constants, Binding.instance_method(:dup).owner, Binding.instance_method(:clone).arity

    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      2
      false
      true
      false
      true
      true
      true
      false
      []
      Binding
      0
    OUT
  end

  it "bool is a true false" do
    result = ze0(<<~'RUBY')
      p(true.is_a?(Object))
      p(true.is_a?(TrueClass))
      p(true.is_a?(FalseClass))
      p(false.is_a?(FalseClass))
      p(false.is_a?(TrueClass))
      p(true.kind_of?(Object))
      b = 1 == 1
      p(b.is_a?(TrueClass))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
      true
      true
    OUT
  end

  it "boolean and or return the operand not a bool" do
    result = ze0(<<~'RUBY')
      # Ruby's `&&`/`||` return the actual operand, not a coerced bool --
      # `false && x` is `false`, but `5 && x` is `x`, not `true`.

      x = 5
      y = 3
      puts((x > y) && :yes)
      puts((x < y) && :yes)
      puts((x < y) || :fallback)
      puts((x > y) || :fallback)
      puts(!(x > y))
      puts(!(x < y))
    RUBY

    _(result).must_answer <<~'OUT'
      yes
      false
      fallback
      true
      false
      true
    OUT
  end

  it "break from a block passed to a singleton method returns from it" do
    _(ze0(<<~'RUBY')).must_answer "\"stop2\"\n"
      # `break` in the block yields the method's return value -- the method-body
      # lambda's terminal arm folds `Signal::Break` into an `Ok` return, exactly
      # as an ordinary method does.

      obj = Object.new
      def obj.count
        yield 1
        yield 2
        yield 3
        "finished"
      end
      p(obj.count { |n| break "stop#{n}" if n == 2 })
    RUBY
  end

  it "can write an ivar on self" do
    _(ze0(<<~'RUBY')).must_answer "42\n"
      class Foo
        def initialize
          eval("@x = 42")
        end
        def x
          @x
        end
      end
      puts Foo.new.x
    RUBY
  end

  it "class method prepend is invisible to singleton ancestors" do
    result = ze0(<<~'RUBY')
      # `prepend M` inside `class << self` DISPATCHES correctly -- M's instance
      # methods shadow the class's own `def self.x`, and `super` reaches the
      # original. Only reflection disagrees: the module is absent from
      # `singleton_class.ancestors`.
      #
      # It was expected to fall out of the singleton-surrogate work, and it did not.
      # `class_method_prepends` is a compile-time MRO input (see analyze/mro.rs) that
      # nothing carries into the runtime registry, and this body mints no surrogate
      # for the registry to carry it ON -- the surrogate exists only where the body
      # needs a compile-time class. Making the ancestry right means minting one for a
      # mixin too, and registering the module in its ancestors.
      module Loud
        def greet = "LOUD " + super
      end
      class Speaker
        class << self
          prepend Loud
        end
        def self.greet = "hi"
      end

      # Dispatch: right.
      p Speaker.greet

      # Reflection: wrong.
      p Speaker.singleton_class.ancestors.include?(Loud)
      p Speaker.singleton_class.ancestors.first
      p Speaker.singleton_class.include?(Loud)
    RUBY

    _(result).must_answer <<~'OUT'
      "LOUD hi"
      true
      Loud
      true
    OUT
  end

  it "class shift self at top level defines singleton methods on main" do
    result = ze0(<<~'RUBY')
      # `class << self` at the top level reopens `main`'s singleton:
      # it desugars to `self.define_singleton_method(...)`, `self` being `main`,
      # so each inner `def` installs on `main` and is callable via implicit self.

      class << self
        def shout; "MAIN"; end
        def echo(x); "<#{x}>"; end
      end
      puts shout
      puts echo("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      MAIN
      <hi>
    OUT
  end

  it "collection display" do
    result = ze0(<<~'RUBY')
      # Array and Hash rendering: `to_s`/`print`/interpolation all use the bracketed
      # inspect form; only `puts` flattens an array onto separate lines.

      arr = [1, [2, "x"]]
      p arr.to_s                    # "[1, [2, \"x\"]]"
      puts arr.to_s                 # [1, [2, "x"]]
      print arr                     # [1, [2, "x"]]
      puts
      puts "interp: #{arr}"         # interp: [1, [2, "x"]]

      # `puts` (and only `puts`) flattens an array, one element per line.
      puts [1, 2, 3]                # 1 / 2 / 3

      # Hash to_s / interpolation inspect keys and values (a String value keeps its
      # quotes).
      h = { a: "x", 3 => [1] }
      p h.to_s                      # "{a: \"x\", 3 => [1]}"
      puts "h: #{h}"                # h: {a: "x", 3 => [1]}
      puts h                        # {a: "x", 3 => [1]}

      # A Range's to_s uses the plain (to_s) form of its bounds.
      p (1..3).to_s                 # "1..3"
    RUBY

    _(result).must_answer <<~'OUT'
      "[1, [2, \"x\"]]"
      [1, [2, "x"]]
      [1, [2, "x"]]
      interp: [1, [2, "x"]]
      1
      2
      3
      "{a: \"x\", 3 => [1]}"
      h: {a: "x", 3 => [1]}
      {a: "x", 3 => [1]}
      "1..3"
    OUT
  end

  it "constant announces itself to const added" do
    result = ze0(<<~'RUBY')
      # Ruby announces a constant the moment it becomes readable: after the
      # write, on the module it was set on, once per assignment -- and a class
      # or module declaration announces its own name the same way.
      module Watched
        def self.const_added(n)
          puts "added #{n}"
        end
        X = 1
        Y = 2
        class Inner; end
        module Nested; end
        Z = X + Y
      end
      p Watched::X
      p Watched::Z

      module Late
        A = 1
        def self.const_added(n) = puts("late #{n}")
        B = 2
      end
    RUBY

    _(result).must_answer <<~'OUT'
      added X
      added Y
      added Inner
      added Nested
      added Z
      1
      3
      late B
    OUT
  end

  it "constant inside class of an object resolves in its singleton methods" do
    _(ze0(<<~'RUBY')).must_answer "42\n"
      # `class << obj; MAX = ...; def m; MAX; end; end` -- a constant on an
      # object's singleton class (tmpdir's `class << RANDOM`). zeo hoists the
      # constant to the enclosing lexical scope, where the singleton method
      # resolves it.

      module Holder
        GEN = Object.new
        class << GEN
          STEP = 6
          def emit = STEP * 7
        end
      end
      puts Holder::GEN.emit
    RUBY
  end

  it "define singleton method" do
    result = ze0(<<~'RUBY')
      # `define_singleton_method` adds a method to a single class's own singleton --
      # in practice, a class method. It works from inside the class body and from
      # outside on a class constant, including a namespaced one.
      class Greeter
        define_singleton_method(:hello) { "hi" }
        self.define_singleton_method(:hey) { "hey there" }
      end

      # From outside, on the class constant -- with parameters, too.
      Greeter.define_singleton_method(:shout) { |name| "HELLO, #{name.upcase}" }

      module Outer
        class Inner
        end
      end
      Outer::Inner.define_singleton_method(:whoami) { "Outer::Inner" }

      puts Greeter.hello                    # hi
      puts Greeter.hey                      # hey there
      puts Greeter.shout("ada")             # HELLO, ADA
      puts Outer::Inner.whoami              # Outer::Inner
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hey there
      HELLO, ADA
      Outer::Inner
    OUT
  end

  it "define singleton method forms" do
    result = ze0(<<~'RUBY')
      # In-body (bare and self), external constant receiver (with a param),
      # and a namespaced receiver all define a class method.

      class C
        define_singleton_method(:a) { "a" }
        self.define_singleton_method(:b) { "b" }
      end
      C.define_singleton_method(:c) { |n| n + 1 }
      module M
        class D; end
      end
      M::D.define_singleton_method(:d) { "nested" }
      puts C.a
      puts C.b
      puts C.c(41)
      puts M::D.d
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      42
      nested
    OUT
  end

  it "define singleton method literal" do
    result = ze0(<<~'RUBY')
      class C
        define_singleton_method(:hello) { "hi" }                 # no receiver: the enclosing class
        self.define_singleton_method(:hello_self) { "hi self" }  # self receiver
      end

      C.define_singleton_method(:world) { "earth" }              # class-constant receiver
      C.define_singleton_method(:double) { |x| x * 2 }           # parameterized

      module M
        class D
        end
      end
      M::D.define_singleton_method(:nested) { "nested" }         # namespaced (ConstantPath) receiver

      puts C.hello
      puts C.hello_self
      puts C.world
      puts C.double(21)
      puts M::D.nested
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      hi self
      earth
      42
      nested
    OUT
  end

  it "define singleton method on a class does not reach back" do
    result = ze0(<<~'RUBY')
      # `Later.define_singleton_method(:mode)` must replace the compiled
      # `def self.mode` only from the point it RUNS. zeo answers `:runtime` for the
      # call written before it, so the redefinition reaches backwards in time.
      #
      # Pre-existing, and unrelated to class-method call-site caching: the same two
      # lines diverge identically with every `Target.name` site uncached. The
      # `overlay_class_method` probe in `send_value_in_reason` is gated on
      # `is_live()`, which is a WHOLE-PROGRAM flag -- once anything is defined at
      # runtime it is on for every call, including ones that already happened in
      # source order. The instance side has the same shape.
      #
      # The sibling shape that DOES work is `def Counter.tick = 2`, a top-level
      # singleton def, which is registered where it is written -- see
      # `tests/a_class_method_site_stays_correct_when_the_class_changes.rb`.
      class Later
        def self.mode = :compiled
      end
      p Later.mode
      Later.define_singleton_method(:mode) { :runtime }
      p Later.mode
    RUBY

    _(result).must_answer <<~'OUT'
      :compiled
      :runtime
    OUT
  end

  it "definition in expression position sends to self" do
    result = ze0(<<~'RUBY')
      # A `def` / `define_method` / `define_singleton_method` written where a VALUE
      # is expected (inside a method body, a block, an argument list) compiles to a
      # runtime install. Codegen used to name the ENCLOSING CLASS as the target for
      # all three, which is only ruby's rule for one of them.
      #
      #   A plain `def` installs on the CREF's default definee -- the enclosing
      #   class, `Object` at the top level. That one was right.
      #
      #   `def self.x` and a literal `define_method` are ordinary SENDS TO SELF, and
      #   `self` is NOT the definee outside a class body. Inside an instance method
      #   `self` is the INSTANCE, so `def self.x` there lands on that object's
      #   singleton and `define_method` raises NoMethodError -- an instance is no
      #   Module. Naming the enclosing class answered both the other way round: the
      #   method appeared on the class, and `define_method` quietly succeeded.
      #
      # `boxed_implicit_self` is already the "self here, as a RubyValue" rule and is
      # total, so the receiver is read from it rather than re-derived.

      class C
        def install_singleton
          def self.only_mine = :only_mine
        end

        def install_instance_method
          define_method(:never_reached) { :never_reached }
        end
      end

      c = C.new
      c.install_singleton
      p c.only_mine
      p C.respond_to?(:only_mine)
      p C.new.respond_to?(:only_mine)

      begin
        c.install_instance_method
      rescue NoMethodError => e
        p e.class
      end

      # In a CLASS body, and in a `def self.x`, `self` IS the class -- these were
      # always right and must stay right.
      class D
        p(def self.from_class_body = :from_class_body)

        def self.install
          def self.from_class_method = :from_class_method
        end
      end
      D.install
      p D.from_class_body
      p D.from_class_method

      # A plain `def` in expression position still resolves against the CREF, not
      # against `self`: at the top level that is `Object`, and the `def` evaluates
      # to its own name.
      p(def top_level_def = :top_level_def)
      p top_level_def
      p Object.instance_method(:top_level_def).owner
    RUBY

    _(result).must_answer <<~'OUT'
      :only_mine
      false
      false
      NoMethodError
      :from_class_body
      :from_class_body
      :from_class_method
      :top_level_def
      :top_level_def
      Object
    OUT
  end

  it "enum with object" do
    result = ze0(<<~'RUBY')
      # Enumerator#with_object with no block -> an Enumerator (#2540)
      e = [1, 2, 3].each.with_object([])
      p(e.class)
      p(e.to_a)                                   # [[elem, memo], ...]
      r = [1, 2, 3].each.with_object([]) { |x, m| m << x * 2 }
      p(r)                                        # block form still returns the memo
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [[1, []], [2, []], [3, []]]
      [2, 4, 6]
    OUT
  end

  it "exc is a constant path" do
    result = ze0(<<~'RUBY')
      module PG
        class Error < StandardError; end
        class UndefinedTable < Error; end
      end
      begin
        raise PG::UndefinedTable, "x"
      rescue PG::UndefinedTable => e
        puts(e.is_a?(PG::Error) ? "yes" : "no")          # yes
        puts(e.is_a?(PG::UndefinedTable) ? "yes" : "no") # yes
        puts(e.is_a?(StandardError) ? "yes" : "no")      # yes
        puts(e.is_a?(::StandardError) ? "yes" : "no")    # yes
      end
      x = PG::UndefinedTable.new
      puts(x.is_a?(PG::Error) ? "yes" : "no")            # yes
      # is_a? with a namespaced constant-path class argument compares the fully
      # qualified exception class name (#3260).
    RUBY

    _(result).must_answer <<~'OUT'
      yes
      yes
      yes
      yes
      yes
    OUT
  end

  it "failed iteration propagates then restarts" do
    result = ze0(<<~'RUBY')
      # A mid-iteration exception propagates out of `next`; the NEXT `next`
      # re-inits the dead fiber and RESTARTS the iteration (CRuby's
      # get_next_values rule, oracle-verified).

      e = Enumerator.new do |y|
        y << 1
        raise ArgumentError, "mid"
      end
      p e.next
      begin
        e.next
      rescue ArgumentError => ex
        puts "propagated: #{ex.message}"
      end
      p e.next
    RUBY

    _(result).must_answer <<~'OUT'
      1
      propagated: mid
      1
    OUT
  end

  it "flat map identity" do
    result = ze0(<<~'RUBY')
      # `flat_map { |x| x }` over an array of arrays is a one-level flatten (it is
      # exactly `flatten(1)`): each sub-array is concatenated and scalars pass through.
      # Distinct per-type helpers keep each nested element type monomorphic; receivers
      # route through a method param to defeat constant folding.
      def nii(x) = x
      def nss(x) = x
      def nff(x) = x
      def nmix(x) = x
      def npass(x) = x
      def ints(x) = x

      p nii([[1, 2], [3, 4], [5]]).flat_map { |a| a }      # [1, 2, 3, 4, 5]
      p nss([["a", "b"], ["c"]]).flat_map { |b| b }         # ["a", "b", "c"]
      p nff([[1.5, 2.5], [3.5]]).flat_map { |c| c }         # [1.5, 2.5, 3.5]
      p npass([[1, 2], 3, [4]]).flat_map { |d| d }          # [1, 2, 3, 4] (scalar passthrough)
      p nmix([[1, "a"], [2, "b"]]).flat_map { |e| e }       # [1, "a", 2, "b"]

      # one level only: a deeper sub-array is left intact (matches flatten(1))
      p nmix([[1, [2]], [3]]).flat_map { |f| f }            # [1, [2], 3]

      # assigned result and a chained method
      r = nii([[10], [20, 30]]).flat_map { |g| g }
      p r                                                  # [10, 20, 30]
      p nii([[1, 2], [3, 4]]).flat_map { |h| h }.length     # 4

      # a non-identity (array-returning) flat_map is unchanged
      p ints([1, 2, 3]).flat_map { |i| [i, i * 10] }        # [1, 10, 2, 20, 3, 30]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5]
      ["a", "b", "c"]
      [1.5, 2.5, 3.5]
      [1, 2, 3, 4]
      [1, "a", 2, "b"]
      [1, [2], 3]
      [10, 20, 30]
      4
      [1, 10, 2, 20, 3, 30]
    OUT
  end

  it "initialize dup and clone hooks" do
    result = ze0(<<~'RUBY')
      class WithHooks
        def initialize_copy(o) = (super; @copied = :copy)
        def initialize_dup(o) = (super; @dup = :dup)
        def initialize_clone(o, freeze: nil) = (super; @clone = :clone)
        def state = instance_variables.sort
      end

      a = WithHooks.new
      p a.dup.state
      p a.clone.state
    RUBY

    _(result).must_answer <<~'OUT'
      [:@copied, :@dup]
      [:@clone, :@copied]
    OUT
  end

  it "is a builtin classes" do
    result = ze0(<<~'RUBY')
      t = Time.now
      p t.is_a?(Time)
      p t.is_a?(Comparable)
      p t.is_a?(Object)
      p t.is_a?(String)
      p t.instance_of?(Time)
      p t.kind_of?(Time)
      p 5.is_a?(Numeric)
      p Rational(1, 2).is_a?(Numeric)
      p Rational(1, 2).is_a?(Comparable)
      p Complex(1, 2).is_a?(Numeric)
      p (/a/).is_a?(Regexp)
      p "s".is_a?(Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
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
    OUT
  end

  it "is a for nil true and false against their own singleton classes" do
    result = ze0(<<~'RUBY')
      puts nil.is_a?(NilClass)
      puts true.is_a?(TrueClass)
      puts false.is_a?(FalseClass)
      puts true.is_a?(Object)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "is a toplevel scoped const" do
    result = ze0(<<~'RUBY')
      p 5.is_a?(::Integer)
      p "x".is_a?(::String)
      p [1].is_a?(::Array)
      class Foo; end
      p Foo.new.is_a?(::Foo)
      p 3.14.kind_of?(::Numeric)
      p nil.is_a?(::NilClass)
      p 5.is_a?(::Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "issue 3227 ivar shared" do
    result = ze0(<<~'RUBY')
      # Shared-mutable strings, ivar slots (P4): an in-place-mutated ivar string
      # shares its handle with local aliases and containers; multiple instances
      # stay independent; external attr reads are safe copies.
      class Doc
        attr_reader :title
        def initialize(t)
          @title = t
          a = @title
          @title << "!"
          p a
          p a.equal?(@title)
        end
        def bump = @title << "+"
        def shout = @title.upcase!
      end
      d1 = Doc.new(+"aaa")
      d2 = Doc.new(+"bbb")
      d1.bump
      p d1.title
      p d2.title
      d1.shout
      p d1.title
      p d1.title.length

      # Toplevel ivar
      @log = +"start"
      snap = @log
      @log << "-x"
      p snap
      p snap.equal?(@log)
      box = [@log]
      @log.upcase!
      p box[0]

      # hand-written reader over a promoted ivar
      class Memo
        def initialize
          @body = +"b"
          keep = @body
          @body << "1"
          p keep
        end
        def body = @body
      end
      m = Memo.new
      p m.body
      p "#{m.body}?"
    RUBY

    _(result).must_answer <<~'OUT'
      "aaa!"
      true
      "bbb!"
      true
      "aaa!+"
      "bbb!"
      "AAA!+"
      5
      "start-x"
      true
      "START-X"
      "b1"
      "b1"
      "b1?"
    OUT
  end

  it "ivar append accumulator" do
    result = ze0(<<~'RUBY')
      class Doc
        attr_reader :out

        def initialize
          @out = String.new
          @tail = String.new
        end

        def build(n)
          @out = String.new
          n.times { |i| @out << i.to_s << "," }
          @out
        end

        def mixed(v, n)
          @tail = v.upcase
          n.times { @tail << "!" }
          @tail
        end
      end

      d = Doc.new
      p d.build(5)
      p d.out
      p d.out.length
      p d.build(3)
      p d.mixed("ab", 3)
      p d.out == "0,1,2,"

      # the accumulator is still an ordinary String to everyone else
      p d.build(2)
      p d.out.reverse
      p d.out.sub("0", "X")
    RUBY

    _(result).must_answer <<~'OUT'
      "0,1,2,3,4,"
      "0,1,2,3,4,"
      10
      "0,1,2,"
      "AB!!!"
      true
      "0,1,"
      ",1,0"
      "X,1,"
    OUT
  end

  it "map to value type objects" do
    result = ze0(<<~'RUBY')
      # `arr.map { Obj.new }` where Obj is a value-type-candidate class (no
      # subclass, immutable scalar ivars) used to build-fail: detect_value_types
      # never saw the map result as a ptr_array store, so Obj stayed value-typed
      # and `sp_Obj_new(...)` returned a struct by value that couldn't be pushed
      # into the object accumulator. detect_ptr_array_stored_types now forces a
      # `map`-collected class heap. Covers both typed-array and range receivers
      # (the range path previously bailed to a silent "0").
      class Node
        attr_reader :tag
        def initialize(t = 0); @tag = t; end
      end

      ks = [1, 2, 3].map { |t| Node.new(t) }
      puts ks.size
      puts ks[0].tag
      puts ks[2].tag
      total = 0
      ks.each { |n| total += n.tag }
      puts total

      rs = (1..3).map { |t| Node.new(t * 10) }
      puts rs.size
      puts rs.map(&:tag).inspect

      es = (1...4).map { |t| Node.new(t) }
      puts es.map(&:tag).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      3
      6
      3
      [10, 20, 30]
      [1, 2, 3]
    OUT
  end

  it "module metaprogramming" do
    result = ze0(<<~'RUBY')
      class C001
        attr :x
        def initialize; @x = 5; end
      end
      p C001.new.x

      class Box
        def initialize(v); @v = v; end
      end
      class BoxPlus < Box; end
      Box.class_eval do
        def doubled; @v * 2; end
        define_method(:tripled) { @v * 3 }
        def labelled; @label = "n=#{@v}"; @label; end
      end
      b = Box.new(21)
      p [b.doubled, b.tripled, b.labelled]
      p BoxPlus.new(5).doubled

      module M; end
      M.module_exec { def mm; "mm"; end }
      class D; include M; end
      p D.new.mm

      o = Object.new
      o.instance_exec { @invented = 99 }
      p o.instance_variable_get(:@invented)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      [42, 63, "n=21"]
      10
      "mm"
      99
    OUT
  end

  it "next from a block passed to a singleton method is its yield value" do
    _(ze0(<<~'RUBY')).must_answer "[10, 20]\n"
      obj = Object.new
      def obj.run
        a = yield 1
        b = yield 2
        [a, b]
      end
      p(obj.run { |n| next n * 10 })
    RUBY
  end

  it "nil predicate works universally" do
    result = ze0(<<~'RUBY')
      # `.nil?` on Poly, builtin, and Object receivers, with a user override
      # winning.

      puts nil.nil?
      puts 1.nil?
      class Once
        def check(x)
          x.nil?
        end
      end
      puts Once.new.check(nil)
      puts Once.new.check(5)
      puts Once.new.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      false
    OUT
  end

  it "object default display" do
    result = ze0(<<~'RUBY')
      # Default Object#to_s / #inspect for user objects, and raising a
      # non-exception object. puts obj was an unsupported argument, obj.inspect
      # answered the "[]" last-resort, and `raise obj` smuggled the pointer into
      # the message slot (a C warning + garbage). Addresses are normalized here;
      # the format matches CRuby's #<Name:0x...> / ivar dump.
      class Cell
        def initialize(x, y)
          @x = x
          @y = y
          @alive = false
          @tag = nil
          @list = []
          @name = "c1"
        end
      end
      class Inner
        def initialize; @k = 7; end
      end
      class Outer
        def initialize; @inner = Inner.new; end
      end
      class Named
        def initialize; @n = 1; end
        def to_s; "custom"; end
        def inspect; "<custom>"; end
      end

      norm = ->(s) { s.gsub(/0x[0-9a-f]+/, "0xADDR") }
      c = Cell.new(0, 1)
      puts norm.call(c.to_s)
      puts norm.call(c.inspect)
      puts norm.call("interp: #{c}")
      puts norm.call(Outer.new.inspect)   # nested object recurses
      puts Named.new
      p Named.new
      # an object read back out of a container is poly-boxed: its .inspect goes
      # through sp_poly_inspect's user-object hook, not the typed path (#1875)
      cells = {}
      cells["0-0"] = Cell.new(2, 3)
      puts norm.call(cells["0-0"].inspect)
      mixed = [Cell.new(4, 5), "s"]
      puts norm.call(mixed[0].inspect)
      begin
        raise c
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      #<Cell:0xADDR>
      #<Cell:0xADDR @x=0, @y=1, @alive=false, @tag=nil, @list=[], @name="c1">
      interp: #<Cell:0xADDR>
      #<Outer:0xADDR @inner=#<Inner:0xADDR @k=7>>
      custom
      <custom>
      #<Cell:0xADDR @x=2, @y=3, @alive=false, @tag=nil, @list=[], @name="c1">
      #<Cell:0xADDR @x=4, @y=5, @alive=false, @tag=nil, @list=[], @name="c1">
      TypeError: exception class/object expected
    OUT
  end

  it "object id basic" do
    result = ze0(<<~'RUBY')
      # Object#object_id — unique stable id per object value.
      # Int uses the MRI tagged formula (2*n+1), string uses the pointer
      # bit pattern, symbol uses its interned id scaled to avoid collision.
      # The exact numbers aren't part of the contract; spinel just needs
      # values that are stable and unique-ish.

      puts 42.object_id == 42.object_id   # true (same value, same id)
      puts 1.object_id != 2.object_id     # true (different value)

      s = "hello"
      puts s.object_id == s.object_id     # true (same object)

      puts :foo.object_id == :foo.object_id  # true (interned)
      puts :foo.object_id != :bar.object_id  # true (different sym)

      # Returns Integer
      puts 42.object_id.class
      puts "x".object_id.class
      puts :s.object_id.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      Integer
      Integer
      Integer
    OUT
  end

  it "object id nil true" do
    result = ze0(<<~'RUBY')
      # The immediate values nil, false and true have fixed, distinct object_ids.
      p nil.object_id
      p false.object_id
      p true.object_id
      p [nil.object_id, true.object_id]
      p(nil.object_id == false.object_id)
      p(false.object_id == true.object_id)
      p(nil.object_id == true.object_id)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      0
      20
      [4, 20]
      false
      false
      false
    OUT
  end

  it "object method gaps callee clone itself" do
    result = ze0(<<~'RUBY')
      # Small built-in method gaps (#1222): __callee__ (resolves like
      # __method__ to the current method name), String#clone (like dup), and
      # NilClass#itself (returns nil).

      def who
        __callee__
      end
      puts who                  # who

      def same?
        __method__ == __callee__
      end
      puts same?                # true

      s = "abc".clone
      puts s                    # abc
      puts s.length             # 3

      m = String.new("mut").clone
      puts m                    # mut

      p nil.itself              # nil
      p nil.itself.nil?         # true
    RUBY

    _(result).must_answer <<~'OUT'
      who
      true
      abc
      3
      mut
      nil
      true
    OUT
  end

  it "objectspace each object is declined" do
    result = ze0(<<~'RUBY')
      # ObjectSpace.each_object is DECLINED: zeo has no heap enumeration (objects
      # are native values with no global registry), and the row raises a
      # NotImplementedError saying so. The divergence is stepped around here -- the
      # row exists and reflects on both sides; only CALLING it differs, and this
      # test documents that without doing so.
      puts ObjectSpace.respond_to?(:each_object).inspect
      puts defined?(ObjectSpace.each_object).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "method"
    OUT
  end

  it "p of immediates" do
    result = ze0(<<~'RUBY')
      p nil
      p true
      p false
      p 0
      p -1
      p 1.5
      p "s"
      p 1, 2
      puts nil
      puts true
      puts
      puts "a", "b"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      false
      0
      -1
      1.5
      "s"
      1
      2

      true

      a
      b
    OUT
  end

  it "qualified class paths work in patterns and is a" do
    result = ze0(<<~'RUBY')
      module Store
        class Item
          def initialize(n)
            @n = n
          end

          def deconstruct_keys(keys)
            { n: @n }
          end
        end
      end

      case Store::Item.new(5)
      in Store::Item
        puts "matched class pattern"
      end

      case Store::Item.new(7)
      in Store::Item(n:)
        puts "matched with capture #{n}"
      end

      puts Store::Item.new(1).is_a?(Store::Item)
    RUBY

    _(result).must_answer <<~'OUT'
      matched class pattern
      matched with capture 7
      true
    OUT
  end

  it "safe navigation on a non nil receiver" do
    _(ze0(<<~'RUBY')).must_answer "present\n"
      # Only proves `&.` doesn't regress a normal, statically-typed dispatch --
      # a receiver that's *actually* nil at runtime needs a nilable/union type
      # the compiler's `TyKind` doesn't have yet (every `New` is unconditionally
      # a concrete `Object(ClassId)`, never possibly-nil), so that half of
      # `&.`'s behavior isn't testable end to end until then.

      class Box
        def initialize(value)
          @value = value
        end
        def value
          @value
        end
      end

      b = Box.new(:present)
      puts(b&.value)
    RUBY
  end

  it "singleton method object" do
    result = ze0(<<~'RUBY')
      # Singleton methods on a constant/local that statically holds one object:
      # synthesized as an anonymous subclass that masquerades as its parent.
      class Config
        def initialize
          @base = 10
        end
        def base
          @base
        end
      end

      CONFIG = Config.new
      def CONFIG.reload
        "reloaded-#{base}"
      end
      def CONFIG.scale(n)
        base * n
      end

      p CONFIG.base
      p CONFIG.reload
      p CONFIG.scale(3)
      p CONFIG.class
      p CONFIG.class.name
      p CONFIG.is_a?(Config)
      p CONFIG.instance_of?(Config)

      # override a parent method + super
      class Widget
        def initialize(n)
          @n = n
        end
        def label
          "widget-#{@n}"
        end
      end
      W1 = Widget.new(1)
      def W1.label
        "custom-#{super}"
      end
      def W1.tag
        @tag = "T"
        @tag
      end
      p W1.label
      p W1.tag
      # poly dispatch alongside a plain instance
      [W1, Widget.new(2)].each { |w| puts w.label }

      # local receiver
      class Thing
        def base
          "b"
        end
      end
      x = Thing.new
      def x.special
        "s-#{base}"
      end
      p x.special
      p x.class

      # define_singleton_method
      class Box
        def v
          1
        end
      end
      B = Box.new
      B.define_singleton_method(:doubled) { v * 2 }
      p B.doubled

      # obj.extend(Mod): transplant module methods onto the singleton subclass
      module Loud
        def shout
          label.upcase
        end
      end
      module Soft
        def whisper
          label.downcase
        end
      end
      class Speaker
        def initialize(s)
          @s = s
        end
        def label
          @s
        end
      end
      SPK = Speaker.new("Hi")
      SPK.extend(Loud)
      SPK.extend(Soft)
      def SPK.both
        "#{shout}/#{whisper}"
      end
      p SPK.shout
      p SPK.whisper
      p SPK.both
      p SPK.class
    RUBY

    _(result).must_answer <<~'OUT'
      10
      "reloaded-10"
      30
      Config
      "Config"
      true
      true
      "custom-widget-1"
      "T"
      custom-widget-1
      widget-2
      "s-b"
      Thing
      2
      "HI"
      "hi"
      "HI/hi"
      Speaker
    OUT
  end

  it "singleton methods" do
    result = ze0(<<~'RUBY')
      # Per-object singleton methods (#97): `def obj.foo`, `class << obj`,
      # `define_singleton_method`, and the immediate-receiver TypeError.

      obj = Object.new
      obj.instance_variable_set(:@tag, "A")

      def obj.describe
        "object #{@tag}"
      end

      class << obj
        def shout(word)
          word.upcase
        end
      end

      obj.define_singleton_method(:twice) { |x| x * 2 }

      puts obj.describe
      puts obj.shout("hi")
      puts obj.twice(21)
      puts obj.respond_to?(:describe)
      puts obj.respond_to?(:shout)
      puts Object.new.respond_to?(:describe)

      # A singleton on an immediate is a TypeError.
      begin
        5.define_singleton_method(:nope) { 0 }
      rescue TypeError => e
        puts "TypeError caught"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      object A
      HI
      42
      true
      true
      false
      TypeError caught
    OUT
  end

  it "singleton methods on objects constants and modules" do
    result = ze0(<<~'RUBY')
      # Singleton methods on an ordinary object. Three things that were broken
      # together: `super` inside a `class << obj` body (it panicked the compiler with
      # "`super` outside a method", since a per-object singleton has no compile-time
      # class to splice an ancestor chain against); a block passed to a runtime
      # singleton method on a class/module (`M.wrap { }` -- dispatch dropped it and
      # `yield` raised LocalJumpError); and `define_singleton_method` on a constant
      # that holds an OBJECT rather than naming a class (it was desugared into a
      # class reopen, minting a phantom class, so `B.class` answered `Class`).

      class Widget
        def initialize(n); @n = n; end
        def label; "w#{@n}"; end
      end
      W = Widget.new(1)
      class << W
        def label; "custom-#{super}"; end
      end
      p W.label
      p W.class

      module M; end
      def M.wrap; "[" + yield + "]"; end
      puts M.wrap { "hi" }

      class Box
        def v; 1; end
      end
      B = Box.new
      B.define_singleton_method(:doubled) { v * 2 }
      p B.class
      p B.doubled

      class Named; end
      Named.define_singleton_method(:greet) { "hello" }
      p Named.greet
    RUBY

    _(result).must_answer <<~'OUT'
      "custom-w1"
      Widget
      [hi]
      Box
      2
      "hello"
    OUT
  end

  it "tap param unread slot" do
    result = ze0(<<~'RUBY')
      r = {1 => []}.each_with_index.map do |(k, v), _i|
        v.tap { |_| }
      end
      p r

      pairs = {"a" => 1, "b" => 2}.each_with_index.map do |(k, v), i|
        k.tap { |unused| }
        [k, v, i]
      end
      p pairs

      n = {1 => 2}.each_with_index.map do |(k, v), _i|
        v.then { |ignored| k }
      end
      p n

      acc = [].tap { |a| a << 1 }
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      [[]]
      [["a", 1, 0], ["b", 2, 1]]
      [1]
      [1]
    OUT
  end

  it "tap then expr" do
    result = ze0(<<~'RUBY')
      # Object#tap and Object#then/#yield_self in expression position. tap runs the
      # block for a side effect and yields the (unchanged) receiver; then yields the
      # block's value. Both work across receiver types, not just a bare statement.
      p(5.tap { |x| puts x })             # int receiver, returns 5
      p("hi".tap { |s| puts s.upcase })   # string receiver, returns "hi"
      p([1, 2, 3].tap { |a| a.push(4) })  # array literal, mutated then returned

      p(5.then { |x| x * 2 })             # then yields the block value
      p("hi".then { |s| s.upcase })
      p([1, 2, 3].then { |a| a.sum })

      # chained into another call
      doubled = [1, 2, 3].map { |x| x * 2 }.tap { |a| a.push(99) }
      p doubled

      # tap as a statement still works (mutates in place)
      nums = [3, 1, 2]
      nums.tap { |a| a.sort! }
      p nums
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      HI
      "hi"
      [1, 2, 3, 4]
      10
      "HI"
      6
      [2, 4, 6, 99]
      [1, 2, 3]
    OUT
  end

  it "top level def is a private method of object" do
    result = ze0(<<~'RUBY')
      # Callable by implicit self everywhere, invisible to `respond_to?`,
      # reachable via `send`, and a NoMethodError with an explicit receiver.

      def greet(name)
        "Hello, #{name}!"
      end
      class Speaker
        def speak
          greet("instance")
        end
      end
      puts greet("top")
      puts Speaker.new.speak
      p self.respond_to?(:greet)
      p self.respond_to?(:greet, true)
      p Speaker.new.respond_to?(:greet)
      p send(:greet, "send")
      p Speaker.new.send(:greet, "on-instance")
      begin
        Speaker.new.greet("explicit")
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Hello, top!
      Hello, instance!
      false
      true
      false
      "Hello, send!"
      "Hello, on-instance!"
      NoMethodError
    OUT
  end

  it "weakmap full api and identity keying" do
    result = ze0(<<~'RUBY')
      m = ObjectSpace::WeakMap.new
      p m.class
      k1 = "a"; k2 = "b"
      v1 = Object.new; v2 = Object.new
      m[k1] = v1
      m[k2] = v2
      p m[k1].equal?(v1)
      p m.key?(k1)
      p m.include?(k2)
      p m.member?("absent")
      p m.length
      p m.size
      p m.keys.length
      p m.values.length
      # identity keying: an equal-but-different key string misses
      p m["a"].nil?
      # overwrite in place, not a second entry
      m[k1] = v2
      p m.length
      p m[k1].equal?(v2)
      # delete returns the value, then the key is gone
      p m.delete(k1).equal?(v2)
      p m[k1].nil?
      p m.length
    RUBY

    _(result).must_answer <<~'OUT'
      ObjectSpace::WeakMap
      true
      true
      true
      false
      2
      2
      2
      2
      true
      2
      true
      true
      true
      1
    OUT
  end

  it "weakmap iteration and inspect" do
    result = ze0(<<~'RUBY')
      m = ObjectSpace::WeakMap.new
      a = Object.new; b = Object.new
      m[a] = 1
      m[b] = 2
      vals = []
      m.each { |k, v| vals << v }
      p vals.sort
      keys_seen = 0
      m.each_key { |k| keys_seen += 1 }
      p keys_seen
      vs = []
      m.each_value { |v| vs << v }
      p vs.sort
      pairs = 0
      m.each_pair { |k, v| pairs += 1 }
      p pairs
      # empty map inspect starts with the byte-exact CRuby prefix
      empty = ObjectSpace::WeakMap.new
      p(empty.inspect.start_with?("#<ObjectSpace::WeakMap:0x"))
      p empty.inspect.end_with?(">")
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      2
      [1, 2]
      2
      true
      true
    OUT
  end
end
