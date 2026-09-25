# frozen_string_literal: true

require "spec_helper"

describe "Modules: inheritance and ancestors" do
  it "builtin ancestors are cruby exact" do
    result = zr(<<~'RUBY')
      # THE keystone parity test: `.ancestors` for every core class, byte-
      # identical to real ruby. (Mutex/Queue excluded: real Ruby names them
      # `Thread::Mutex`/`Thread::Queue` -- a documented naming divergence.)

      [BasicObject, Object, Kernel, Comparable, Enumerable,
       Numeric, Integer, Float, Rational, Complex,
       String, Symbol, Array, Hash, Range,
       NilClass, TrueClass, FalseClass,
       Proc, Regexp, MatchData, Struct, Enumerator,
       Class, Module, Math, Fiber, Thread, Ractor].each do |c|
        puts "#{c}: #{c.ancestors.inspect}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      BasicObject: [BasicObject]
      Object: [Object, Kernel, BasicObject]
      Kernel: [Kernel]
      Comparable: [Comparable]
      Enumerable: [Enumerable]
      Numeric: [Numeric, Comparable, Object, Kernel, BasicObject]
      Integer: [Integer, Numeric, Comparable, Object, Kernel, BasicObject]
      Float: [Float, Numeric, Comparable, Object, Kernel, BasicObject]
      Rational: [Rational, Numeric, Comparable, Object, Kernel, BasicObject]
      Complex: [Complex, Numeric, Comparable, Object, Kernel, BasicObject]
      String: [String, Comparable, Object, Kernel, BasicObject]
      Symbol: [Symbol, Comparable, Object, Kernel, BasicObject]
      Array: [Array, Enumerable, Object, Kernel, BasicObject]
      Hash: [Hash, Enumerable, Object, Kernel, BasicObject]
      Range: [Range, Enumerable, Object, Kernel, BasicObject]
      NilClass: [NilClass, Object, Kernel, BasicObject]
      TrueClass: [TrueClass, Object, Kernel, BasicObject]
      FalseClass: [FalseClass, Object, Kernel, BasicObject]
      Proc: [Proc, Object, Kernel, BasicObject]
      Regexp: [Regexp, Object, Kernel, BasicObject]
      MatchData: [MatchData, Object, Kernel, BasicObject]
      Struct: [Struct, Enumerable, Object, Kernel, BasicObject]
      Enumerator: [Enumerator, Enumerable, Object, Kernel, BasicObject]
      Class: [Class, Module, Object, Kernel, BasicObject]
      Module: [Module, Object, Kernel, BasicObject]
      Math: [Math]
      Fiber: [Fiber, Object, Kernel, BasicObject]
      Thread: [Thread, Object, Kernel, BasicObject]
      Ractor: [Ractor, Object, Kernel, BasicObject]
    OUT
  end

  it "class ancestors superclass" do
    result = zr(<<~'RUBY')
      # Class#ancestors and Class#superclass over the full chain (user + builtin),
      # and Class values rendering through inspect/p. (CLASS-OBJECT.md Phase 3)
      class Animal; end
      class Dog < Animal; end

      p Dog.ancestors
      p Animal.ancestors
      p Dog.superclass
      p Integer.superclass
      p Float.superclass
      p Integer.ancestors
      p String.ancestors
      p Dog
      p Integer
      # nested in an array (poly inspect of a Class element)
      p [Dog, Animal, Integer]
      # superclass chaining
      puts Dog.superclass.superclass     # Object
      puts Integer.superclass.superclass # Object
      # <= / ancestors-driven comparisons still hold
      puts(Dog <= Animal)                # true
      puts(Dog <= Object)                # true
      puts(Integer <= Numeric)           # true
    RUBY

    _(result).must_answer <<~'OUT'
      [Dog, Animal, Object, Kernel, BasicObject]
      [Animal, Object, Kernel, BasicObject]
      Animal
      Numeric
      Numeric
      [Integer, Numeric, Comparable, Object, Kernel, BasicObject]
      [String, Comparable, Object, Kernel, BasicObject]
      Dog
      Integer
      [Dog, Animal, Integer]
      Object
      Object
      true
      true
      true
    OUT
  end

  it "include chain const lookup" do
    result = zr(<<~'RUBY')
      # Constants defined in a late-reopened module body resolve from
      # instance methods on a class that included the module. This is the
      # forward-decl + include + late-reopen pattern, for constants.
      #
      # A bare `CONST` reference from a method body attached via
      # `include M` resolves M::CONST.

      module M
      end

      class C
        include M
      end

      module M
        CONST = { a: 1, b: 2 }
        OTHER = "hello"

        def check
          puts "len=" + CONST.length.to_s
          puts "other=" + OTHER
        end
      end

      C.new.check

      # Same pattern with nested namespace -- the host class is still
      # the search target.
      module M2
      end

      class D
        include M2
      end

      module M2
        ITEMS = [10, 20, 30]

        def total
          ITEMS.length
        end
      end

      puts D.new.total                # 3
    RUBY

    _(result).must_answer <<~'OUT'
      len=2
      other=hello
      3
    OUT
  end

  it "include chain module nested const" do
    result = zr(<<~'RUBY')
      # `include A` brings A's nested constants/modules into the includer's
      # constant lookup chain. This holds also when a module itself does
      # `include X`: a class that includes that module can read a bare
      # nested constant from X in a method body. The lookup recurses into
      # modules as well as classes.

      module ActionView
        module ViewHelpers
          def self.reset_slots!
            42
          end
        end
      end

      module RequestDispatch
        include ActionView

        def call
          ViewHelpers.reset_slots!
        end
      end

      class Test
        include RequestDispatch
      end

      puts Test.new.call

      # Multi-level chain: include of an include. Top-level constant lookup
      # still finds the deeply nested module's class method.
      module Outer
        module DeepHelpers
          def self.label
            "deep"
          end
        end
      end

      module MiddleMixin
        include Outer
      end

      module OuterMixin
        include MiddleMixin

        def fetch_label
          DeepHelpers.label
        end
      end

      class Consumer
        include OuterMixin
      end

      puts Consumer.new.fetch_label
    RUBY

    _(result).must_answer "42\ndeep\n"
  end

  it "include constant path" do
    result = zr(<<~'RUBY')
      # `include` with a ConstantPathNode argument
      # (`include A::B`, not just bare `include B`).
      #
      # A qualified path like `Foo::Bar::Baz` gives the class the
      # methods of that module, for a fresh class and for a reopen.
      # Cross-namespace and nested-class includes both resolve.

      module A
        module B
          def foo
            "foo-from-AB"
          end

          def greet(name)
            "hello, " + name + "!"
          end
        end
      end

      class Host
        include A::B
      end

      puts Host.new.foo
      puts Host.new.greet("world")

      # Three-deep path: `X::Y::Z` -> `X_Y_Z`.
      module X
        module Y
          module Z
            def deep
              "deep-from-XYZ"
            end
          end
        end
      end

      class DeepHost
        include X::Y::Z
      end

      puts DeepHost.new.deep

      # Including via a path also from a class nested under a module.
      # No `Nested::A::B` exists, so the lookup finds the top-level
      # `A::B`.
      module Nested
        class Sub
          include A::B

          def via_nested
            foo + " (via nested)"
          end
        end
      end

      puts Nested::Sub.new.via_nested

      # Absolute-path include (`::Top`). Inside `module Outer` a bare
      # `Helper` names `Outer::Helper`, because such a module exists; the
      # absolute path `::Helper` resolves to the top-level `Helper`.
      module Helper
        def from_top
          "top-helper"
        end
      end

      module Outer
        module Helper
          def from_top
            "outer-helper"
          end
        end

        class Inside
          include ::Helper
        end
      end

      puts Outer::Inside.new.from_top

    RUBY

    _(result).must_answer <<~'OUT'
      foo-from-AB
      hello, world!
      deep-from-XYZ
      foo-from-AB (via nested)
      top-helper
    OUT
  end

  it "include nested module" do
    result = zr(<<~'RUBY')
      # A bare-receiver call to a method defined on an `include`d
      # module works when the including class is nested inside a
      # module namespace:
      #
      #   module Ns
      #     module Helper
      #       def helped; "helped"; end
      #     end
      #     class Base
      #       include Helper
      #       def call; helped; end
      #     end
      #   end
      #
      # The include arg `Helper` resolves to `Ns::Helper` first, and
      # to a top-level module when the namespace has none.
      #
      # Coverage:
      #   - Canonical Rails-style shape: module namespace, included
      #     module also in the namespace.
      #   - Cross-namespace include: top-level module included into a
      #     nested class.  The qualified lookup misses, falls back to
      #     the bare name, still resolves.
      #   - Multiple levels of nesting via class reopening are not
      #     covered here.

      module Ns
        module Helper
          def helped
            "helped-from-Ns"
          end
        end

        class Base
          include Helper

          def call
            helped
          end
        end
      end

      puts Ns::Base.new.call            # helped-from-Ns

      # Cross-namespace fallback: top-level module included into a
      # nested class. The qualified `Ns2_Helper2` doesn't exist, so the
      # resolver falls back to the bare `Helper2` which DOES exist at
      # top-level.
      module Helper2
        def helped2
          "helped-from-top"
        end
      end

      module Ns2
        class Base2
          include Helper2

          def call2
            helped2
          end
        end
      end

      puts Ns2::Base2.new.call2          # helped-from-top

      # Same shape with no nesting.
      module BareHelper
        def hi
          "hi"
        end
      end

      class BareBase
        include BareHelper

        def go
          hi
        end
      end

      puts BareBase.new.go               # hi
    RUBY

    _(result).must_answer <<~'OUT'
      helped-from-Ns
      helped-from-top
      hi
    OUT
  end

  it "including a nested module materializes its methods" do
    result = zr(<<~'RUBY')
      module Util
        module Greet
          def hello
            "hello from nested module"
          end
        end
      end

      class Greeter2
        include Util::Greet
      end

      puts Greeter2.new.hello
    RUBY

    _(result).must_answer "hello from nested module\n"
  end

  it "later include reaches back" do
    result = zr(<<~'RUBY')
      module Extra
        def tag = :from_module
      end

      class Thing
      end

      p Thing.new.respond_to?(:tag)
      p Thing.instance_methods.include?(:tag)

      class Thing
        include Extra
      end

      p Thing.new.respond_to?(:tag)
      p Thing.new.tag
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      :from_module
    OUT
  end

  it "module include p" do
    result = zr(<<~'RUBY')
      module Walks; end
      module Swims; end
      class Animal; end
      class Dog < Animal; include Walks; end
      p Dog.include?(Walks)
      p Dog.include?(Swims)
      p Animal.include?(Walks)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
    OUT
  end

  it "module include predicate" do
    result = zr(<<~'RUBY')
      module Greetable; end
      class Person; include Greetable; end
      p Person.include?(Greetable)
      p Person.include?(Comparable)
      begin
        Person.include?(Object)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      wrong argument type Class (expected Module)
    OUT
  end

  it "module initialize no ctor" do
    result = zr(<<~'RUBY')
      # A module's `def initialize` runs when an includer is constructed, and the
      # module itself has no `new`: `M.new` is a NoMethodError in Ruby.
      module Outer
        module Buffering
          def initialize
            @eof = false
            @rbuffer = "".dup
            @sync = false
          end

          def eof?
            @eof
          end

          def buf
            @rbuffer
          end
        end
      end

      class Sock
        include Outer::Buffering

        def initialize
          super
          @extra = 1
        end

        def extra
          @extra
        end
      end

      class Plain
        include Outer::Buffering
      end

      s = Sock.new
      p s.eof?
      p s.buf
      p s.extra

      q = Plain.new
      p q.eof?
      p q.buf

      begin
        Outer::Buffering.new
      rescue NoMethodError
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      ""
      1
      false
      ""
      NoMethodError
    OUT
  end

  it "module ordering operators and subclasses" do
    result = zr(<<~'RUBY')
      class Animal; end
      class Dog < Animal; end
      class Cat < Animal; end
      p(Dog < Animal)
      p(Animal < Dog)
      p(Dog < Cat)
      p(Dog <= Dog)
      p(Animal > Dog)
      p(Dog <=> Animal)
      p(Dog <=> Cat)
      p(Dog <=> 5)
      p(Integer < Numeric)
      begin
        Dog < 5
      rescue TypeError => e
        puts e.message
      end
      class Base; end
      class Kid1 < Base; end
      class Kid2 < Base; end
      class GKid < Kid1; end
      p Base.subclasses.length
      p Base.subclasses.map { |c| c.to_s }.sort
      p Kid1.subclasses.map(&:to_s)
      p Base.singleton_class?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      nil
      true
      true
      -1
      nil
      nil
      true
      compared with non class/module
      2
      ["Kid1", "Kid2"]
      ["GKid"]
      false
    OUT
  end

  it "module reopen after include namespaced" do
    result = zr(<<~'RUBY')
      # A module is forward-declared empty, included by a class nested
      # inside another module, and then reopened with method
      # definitions. The class sees the late-defined methods, as a
      # top-level class does. A reopen later in source order than the
      # include still counts.

      class TestBase
      end

      module RequestDispatch
      end

      module ActionDispatch
        class IntegrationTest < TestBase
          include RequestDispatch
        end
      end

      module RequestDispatch
        def post(path); "post:" + path; end
      end

      puts ActionDispatch::IntegrationTest.new.post("/x")
    RUBY

    _(result).must_answer "post:/x\n"
  end

  it "module super into a value builtin" do
    result = zr(<<~'RUBY')
      # A module mixed into a subclass of a VALUE builtin, whose method calls
      # `super`, must reach the builtin's own method correctly. The same
      # `super` written directly in the subclass works (the second pair
      # below), so this checks reaching the builtin THROUGH a module in the
      # ancestry, not just the value-super channel itself. `DoubledArray`
      # reaches `Array#size` where `DoubledPlain` reaches a user body.

      module Doubled
        def size = super * 2
      end

      class DoubledArray < Array
        include Doubled
      end

      class Base
        def size = 5
      end

      class DoubledPlain < Base
        include Doubled
      end

      p DoubledArray.new(3).size
      p DoubledPlain.new.size

      # Written directly in the subclass, with no module in between, the same `super`
      # is fine today.
      class DirectArray < Array
        def size = super * 2
      end

      p DirectArray.new(3).size
    RUBY

    _(result).must_answer <<~'OUT'
      6
      10
      6
    OUT
  end

  it "multiple modules in one include statement resolve in given order" do
    result = zr(<<~'RUBY')
      module A
        def a
          "a"
        end
      end
      module B
        def b
          "b"
        end
      end
      class C
        include A, B
      end
      c = C.new
      puts c.a
      puts c.b
    RUBY

    _(result).must_answer "a\nb\n"
  end

  it "param include body widen" do
    result = zr(<<~'RUBY')
      # `.include?` is an "ambiguous receiver" method: it exists on
      # String / Array / Hash / Range but NOT on Integer. Thus
      # `cols.include?(:updated_at)` on an int/nil-defaulted param
      # widens the param to "any type".
      #
      # The call works for each Array and Hash kind (Hash#include?
      # aliases has_key?), and for a String receiver it does a
      # substring search, per CRuby's String#include? semantics.

      # The blank lines keep the line numbers that the expected output names.




      def consume(coll)
        coll.include?(:x)
      end

      class Box
        attr_accessor :v
      end

      b = Box.new
      puts consume(b.v)
      b.v = [:y, :x, :z]
      puts consume(b.v)
      b.v = [:a, :b]
      puts consume(b.v)
      b.v = {x: 1, y: 2}
      puts consume(b.v)
      b.v = "abc"
      puts consume(b.v)
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      lang/modules/inheritance_test.rb:16:in 'Object#consume': undefined method 'include?' for nil (NoMethodError)

        coll.include?(:x)
            ^^^^^^^^^
      	from lang/modules/inheritance_test.rb:24:in '<main>'
    ERR
  end

  it "subclass inherits module parent" do
    result = zr(<<~'RUBY')
      # `class Sub < Base` inside `module M` has `M::Base` as its parent,
      # so Sub keeps every field it inherits from Base.

      module M
        class Base
          def initialize(x)
            @x = x
          end
        end

        class Sub < Base
          def double
            @x * 2
          end
          def x_plus(n)
            @x + n
          end
        end

        class Plain
          def initialize
            @y = 99
          end
        end

        class PlainSub < Plain
          def boost
            @y + 1
          end
        end
      end

      s = M::Sub.new(7)
      puts s.double
      puts s.x_plus(100)

      ps = M::PlainSub.new
      puts ps.boost
    RUBY

    _(result).must_answer <<~'OUT'
      14
      107
      100
    OUT
  end

  it "super into included module" do
    result = zr(<<~'RUBY')
      module Greet
        def hi = "hi"
        def shout(x) = x.upcase
      end

      class C
        include Greet
        def hi = "[" + super + "]"          # bare super into the module method
        def shout(x) = "<" + super + ">"    # forwards x up to the module method
      end

      puts C.new.hi
      puts C.new.shout("yo")

      # a class that includes the module but does NOT override stays on the normal
      # transplant path (the module method is callable directly)
      class D
        include Greet
      end
      puts D.new.hi

      # multiple modules defining the same method: a later include takes precedence,
      # and super chains through them in MRO order (C -> M2 -> M1)
      module M1
        def tag = "M1"
      end
      module M2
        def tag = "M2(" + super + ")"
      end
      class F
        include M1
        include M2
        def tag = "F[" + super + "]"
      end
      puts F.new.tag

      # super with no superclass method anywhere raises NoMethodError at runtime
      # (CRuby raises when the method is called, not at definition)
      class E
        def orphan = super
      end
      begin
        E.new.orphan
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [hi]
      <YO>
      hi
      F[M2(M1)]
      NoMethodError: super: no superclass method 'orphan' for an instance of E
    OUT
  end

  it "super resolves into an included module" do
    result = zr(<<~'RUBY')
      # A compile-time scan of the SUPERCLASS chain alone misses a method that
      # only an included module defines; the runtime walk covers the real
      # ancestry, so both a class->module and a module->module `super` land.

      module Greet
        def hi
          "[hi]"
        end
      end
      class C
        include Greet
        def hi
          super
        end
      end
      module M1
        def tag
          "M1"
        end
      end
      module M2
        include M1
        def tag
          "M2(#{super})"
        end
      end
      class F
        include M2
        def tag
          "F[#{super}]"
        end
      end
      puts C.new.hi
      puts F.new.tag
    RUBY

    _(result).must_answer "[hi]\nF[M2(M1)]\n"
  end

  it "three level super chain crosses a module boundary" do
    result = zr(<<~'RUBY')
      # `Parent#greet` calls `super`, reaching `Middle#greet` (an included
      # module), which itself calls `super`, reaching `GrandParent#greet` --
      # a chain of 3. The ancestors-based search of `super` works across
      # more than one hop and a mixed class/module boundary.

      class GrandParent
        def greet
          "grandparent"
        end
      end
      module Middle
        def greet
          "middle(#{super})"
        end
      end
      class Parent < GrandParent
        include Middle
        def greet
          "parent(#{super})"
        end
      end
      puts Parent.new.greet
    RUBY

    _(result).must_answer "parent(middle(grandparent))\n"
  end

  it "top level include" do
    result = zr(<<~'RUBY')
      # A top-level `include` mixes a module into Object (the main object's class),
      # so its methods and constants become available bare, program-wide.

      # Math's module functions and constants after `include Math`.
      include Math
      p sqrt(16)
      p cos(0)
      p log(E).round(4)
      p PI.round(4)
      p hypot(3, 4)

      # A user module's instance methods mix in the same way.
      module Greeter
        GREETING = "hello"
        def greet(who) = "#{GREETING}, #{who}"
      end
      include Greeter
      p greet("world")
      p GREETING

      # The mixed-in methods are visible from inside other objects too (Object is
      # everyone's ancestor).
      class Widget
        def describe = "area #{sqrt(144).to_i}, #{greet('widget')}"
      end
      p Widget.new.describe
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      1.0
      1.0
      3.1416
      5.0
      "hello, world"
      "hello"
      "area 12, hello, widget"
    OUT
  end

  it "a top-level include brings a module's methods to main" do
    result = zr(<<~'RUBY')
      # Top-level `include <Mod>` mixes the module's module_function
      # methods into the main scope so bare `<m>` calls dispatch to
      # them. CRuby installs them on Object.

      module Greeter
        module_function

        def hello(name)
          "hello, " + name + "!"
        end

        def bye
          "bye"
        end
      end

      include Greeter

      puts hello("world")
      puts bye

    RUBY

    _(result).must_answer <<~'OUT'
      hello, world!
      bye
    OUT
  end

  it "a nested module's methods arrive under the name their namespace gives them" do
    result = zr(<<~'RUBY')
      # Top-level `include <Mod>` mixes the module's module_function
      # methods into the main scope so bare `<m>` calls dispatch to
      # them. CRuby installs them on Object.

      module Greeter
        module_function

        def hello(name)
          "hello, " + name + "!"
        end

        def bye
          "bye"
        end
      end

      include Greeter

      # ---
      # `include Outer::Inner` (ConstantPathNode arg) at top level.

      module Outer
        module Inner
          module_function

          def greet
            "hi-from-Outer-Inner"
          end
        end
      end

      include Outer::Inner

      puts greet

    RUBY

    _(result).must_answer <<~'OUT'
      hi-from-Outer-Inner
    OUT
  end

  it "two included modules resolve a shared name to the later one, and keep each one's own" do
    result = zr(<<~'RUBY')
      # Top-level `include <Mod>` mixes the module's module_function
      # methods into the main scope so bare `<m>` calls dispatch to
      # them. CRuby installs them on Object.

      module Greeter
        module_function

        def hello(name)
          "hello, " + name + "!"
        end

        def bye
          "bye"
        end
      end

      include Greeter

      # ---
      # Multi-include with overlap: a later include shadows the earlier
      # alias for the same bare name (CRuby: last-include wins via the
      # linearised ancestor chain). Non-overlapping methods from both
      # modules stay available.

      module First
        module_function

        def shared
          "shared-from-First"
        end

        def only_in_first
          "only-First"
        end
      end

      module Second
        module_function

        def shared
          "shared-from-Second"
        end

        def only_in_second
          "only-Second"
        end
      end

      include First
      include Second

      puts shared           # Second wins
      puts only_in_first    # still resolvable via First
      puts only_in_second   # newly available via Second

    RUBY

    _(result).must_answer <<~'OUT'
      shared-from-Second
      only-First
      only-Second
    OUT
  end

  it "a user-defined method wins over an included module's of the same name" do
    result = zr(<<~'RUBY')
      # Top-level `include <Mod>` mixes the module's module_function
      # methods into the main scope so bare `<m>` calls dispatch to
      # them. CRuby installs them on Object.

      module Greeter
        module_function

        def hello(name)
          "hello, " + name + "!"
        end

        def bye
          "bye"
        end
      end

      include Greeter

      # ---
      # A user-defined top-level `def` is not shadowed by a later
      # `include` of a module with the same method name. CRuby's
      # method-lookup places user defs above the include chain.

      module Tail
        module_function

        def kept_for_user
          "from-Tail"
        end

        def tail_only
          "tail-only"
        end
      end

      def kept_for_user
        "user-defined"
      end

      include Tail

      puts kept_for_user   # user-defined wins
      puts tail_only       # still resolvable
    RUBY

    _(result).must_answer <<~'OUT'
      user-defined
      tail-only
    OUT
  end
end
