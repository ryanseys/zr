# frozen_string_literal: true

require "spec_helper"

describe "Modules: inheritance and ancestors" do
  it "boxs include is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # `include` from inside a box reaches the class's ancestry rather than its
      # own tables, and stays the box's.



      b = Ruby::Box.new
      b.eval("module BoxMix; def mixed = 'm'; end; class Array; include BoxMix; end")
      p [].respond_to?(:mixed)
      p b.eval("[].mixed")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      "m"
    OUT
  end

  it "builtin ancestors are cruby exact" do
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # Constants defined in a late-reopened module body resolve from
      # instance methods on a class that included the module. Sibling to
      # #573 (`b034816 reconcile_class_includes`) which handled the same
      # forward-decl + include + late-reopen pattern for methods but not
      # for constants.
      #
      # The fix walks `@cls_includes[@current_class_idx]` in
      # `resolve_const_read_name` (both analyzer and codegen sides) so a
      # bare `CONST` reference from a method body attached via `include M`
      # resolves M::CONST. Issue #591.

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
    result = ze0(<<~'RUBY')
      # `include A` brings A's nested constants/modules into the includer's
      # constant lookup chain. The bug: spinel tracked `include` on
      # `@cls_includes` only when it appeared in a class body, so a module
      # that itself does `include X` never had X recorded anywhere. When a
      # downstream class then included that module and a method body
      # referenced a bare nested constant from X, the lookup walked the
      # class's direct includes once and bailed (`X` wasn't a class in
      # `@cls_names`, so the recursion couldn't continue).
      #
      # The fix tracks module-to-module includes in a parallel
      # `@module_includes` array and routes const lookup through a shared
      # walker that recurses into modules as well as classes.

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

    _(result).must_answer <<~'OUT'
      42
      deep
    OUT
  end

  it "include constant path" do
    result = ze0(<<~'RUBY')
      # `include` with a ConstantPathNode argument
      # (`include A::B`, not just bare `include B`).
      #
      # Root cause: `collect_class_with_prefix`'s two include handlers
      # (the reopen branch and the fresh-class branch) gated module
      # extraction on `@nd_type[arg] == "ConstantReadNode"` only. A
      # qualified path like `Foo::Bar::Baz` parses as a
      # ConstantPathNode and silently fell through, so the included
      # module's methods never landed on the class's method table and
      # the analyzer warned `cannot resolve call to '<m>' on obj_<C>`
      # at every call site.
      #
      # Fix: both sites also accept ConstantPathNode and flatten the
      # path via `const_ref_flat_name` (`A::B` -> `A_B`) before passing
      # through the existing prefix-aware resolver. The resolver
      # already tries `<prefix>_<name>` first and falls back to the
      # flat name, so cross-namespace and nested-class includes both
      # stay correct.

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
      # The lexical-prefix probe misses (`Nested_A_B` isn't registered),
      # so the resolver falls back to the flat name `A_B` and finds the
      # top-level module.
      module Nested
        class Sub
          include A::B

          def via_nested
            foo + " (via nested)"
          end
        end
      end

      puts Nested::Sub.new.via_nested

      # Absolute-path include (`::Top`). Inside `module Outer` the lexical-
      # prefix probe would otherwise pick `Outer_Helper` because such a
      # module is registered; an absolute path must bypass that and
      # resolve to the top-level `Helper`. const_ref_is_relative returns 0
      # for ConstantPathNode whose receiver chain bottoms out at another
      # ConstantPathNode (no ConstantReadNode root) -- that's the AST
      # shape for `::Helper`.
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
    result = ze0(<<~'RUBY')
      # Issue #425. A bare-receiver call to a method defined on an
      # `include`d module failed when the including class was nested
      # inside a module namespace:
      #
      #   module Ns
      #     module Helper
      #       def helped; "helped"; end
      #     end
      #     class Base
      #       include Helper
      #       def call; helped; end          # warning: cannot resolve
      #     end
      #   end
      #
      # Top-level usage (no `module Ns` wrapper) worked, so the
      # include-resolution + bare-receiver dispatch machinery was
      # intact -- the gap was just the include arg's name lookup.
      #
      # Root cause: `collect_class_with_prefix`'s include handlers
      # (both the class-reopening branch and the fresh-class branch)
      # passed the unqualified ConstantReadNode name (`Helper`) to
      # `collect_module_methods_into_class`, but the module's
      # registered name post-`collect_module_with_prefix` is
      # `<prefix>_<name>` -- `Ns_Helper` in this case. The bare-name
      # lookup walked @module_names and missed every qualified entry.
      #
      # Fix: new helper `resolve_include_module_name(mod_name,
      # module_prefix)` tries the `<prefix>_<name>` form against
      # @module_names first; falls back to the bare name for
      # top-level modules so the existing top-level path stays valid.
      # Both include-handler call sites in collect_class_with_prefix
      # now route through it.
      #
      # Coverage:
      #   - Canonical Rails-style shape (the repro from #425): module
      #     namespace, included module also in the namespace.
      #   - Cross-namespace include: top-level module included into a
      #     nested class.  The qualified lookup misses, falls back to
      #     the bare name, still resolves.
      #   - Multiple levels of nesting via class reopening would be a
      #     further extension; not covered here to keep the fix
      #     minimal.

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

      # Regression check: same shape with no nesting still works.
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # A module's `def initialize` runs when an includer is constructed, and the
      # module itself has no `new`. Spinel emitted a constructor for the module all
      # the same, whose body called an sp_<Module>_initialize that nothing defines --
      # a module's methods are emitted into each includer, not under the module's own
      # name -- so a compiler that rejects implicit declarations stopped the build.
      # `M.new` used to build one quietly; it is a NoMethodError in Ruby (#4167).
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # #573 (Sam Ruby). When a module is forward-declared empty,
      # included by a class nested inside another module, and then
      # reopened with method definitions, the included class's
      # dispatch needs to see the late-defined methods. The bug
      # required the namespaced-class shape: top-level classes
      # resolved the late additions because they're collected in
      # Pass 1 (after Pass 0 has already processed every top-level
      # `module M; ... end` reopen), but nested-in-module classes
      # get collected inside Pass 0's recursion and resolve their
      # `include` against whatever module entries exist at that
      # moment -- which excluded any reopen later in source order.
      #
      # Fix: reconcile_class_includes runs once after Pass 1.6,
      # re-iterating every (class, included-module) pair so reopens
      # registered after the include site finally show up.

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
    result = ze0(<<~'RUBY')
      # A module mixed into a subclass of a VALUE builtin, whose method calls
      # `super`, crashes the generated program:
      #
      #   thread 'ruby-main' panicked at crates/zeo-rt/src/builtins/array.rs:144:
      #   internal error: entered unreachable code: Array table row dispatched on a
      #   non-Array receiver
      #
      # The same `super` written directly in the subclass works (the second pair
      # below), so this is about reaching the builtin THROUGH a module in the
      # ancestry rather than about the value-super channel itself.
      #
      # Not a sharing bug: `ZEO_SHARE=0` panics identically. Found while building
      # divergence shapes for `codegen::class_query`, whose `ValueSuper` question
      # exists precisely because this channel is per-receiver -- `DoubledArray`
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
    result = ze0(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      a
      b
    OUT
  end

  it "param include body widen" do
    result = ze0(<<~'RUBY', path: "lang/modules/param_include_body_widen.rb")
      # #558 (rubys / Sam Ruby). Sibling of #552 for `.include?`,
      # the other "ambiguous receiver" method that exists on
      # String / Array / Hash / Range but NOT on Integer.
      # Pre-fix: `cols.include?(:updated_at)` on an
      # int/nil-defaulted param surfaced as "cannot resolve call to
      # 'include?' on int" and silently returned 0.
      #
      # Post-fix: is_collection_query_method also matches `include?`,
      # so the param widens to flat `poly`. emit_poly_builtin_dispatch
      # emits include? arms across the relevant Array / Hash variants
      # keyed by the arg type (Hash#include? aliases has_key?).
      # SP_TAG_STR include? fires when the arg is a string (substring
      # search per CRuby's String#include? semantics).

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

    _(result).must_answer "", stderr: "lang/modules/param_include_body_widen.rb:16:in 'Object#consume': undefined method 'include?' for nil (NoMethodError)\n\n  coll.include?(:x)\n      ^^^^^^^^^\n\tfrom lang/modules/param_include_body_widen.rb:24:in '<main>'\n", status: 1
  end

  it "subclass inherits module parent" do
    result = ze0(<<~'RUBY')
      # `class Sub < Base` inside `module M` used to record `cls_parents`
      # as bare "Base" rather than "M_Base", so emit_class_fields' lookup
      # of the parent missed and Sub came out as an empty struct — every
      # field inherited from Base was dropped on the C side.

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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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

    _(result).must_answer <<~'OUT'
      [hi]
      F[M2(M1)]
    OUT
  end

  it "three level super chain crosses a module boundary" do
    result = ze0(<<~'RUBY')
      # `Parent#greet` calls `super`, reaching `Middle#greet` (an included
      # module), which itself calls `super`, reaching `GrandParent#greet` --
      # a chain of 3, verifying `emit_super_inline`'s ancestors-based search
      # composes correctly across more than one hop and a mixed
      # class/module boundary.

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
    result = ze0(<<~'RUBY')
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

  it "toplevel include module function" do
    result = ze0(<<~'RUBY')
      # Top-level `include <Mod>` mixes the module's module_function
      # methods into the main scope so bare `<m>` calls dispatch to
      # them. CRuby installs them on Object; Spinel registers parallel
      # bare-name entries in @meth_* pointing at the same body_id.

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
      hello, world!
      bye
      hi-from-Outer-Inner
      shared-from-Second
      only-First
      only-Second
      user-defined
      tail-only
    OUT
  end
end
