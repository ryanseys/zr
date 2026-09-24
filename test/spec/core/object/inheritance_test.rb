# frozen_string_literal: true

require "spec_helper"

describe "Object: inheritance and ancestors" do
  it "basic object subclass is a blank slate" do
    result = zr(<<~'RUBY')
      # Kernel is mixed into Object, so it sits BELOW BasicObject in the chain
      # (object.c:4550 -> class.c:1853) and a BasicObject subclass never sees
      # it -- the blank slate is pure chain position, not a special case.
      # `send`/`public_send` are Kernel's; only `__send__` is BasicObject's
      # (vm_eval.c:2960). An absent method must raise even when its result is
      # immediately used as a receiver (`a.dup.own`).

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
      class Normal; end
      p Normal.new.class
      p Normal.new.respond_to?(:inspect)
    RUBY

    _(result).must_answer <<~'OUT'
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

  it "class body extend is applied before the body runs" do
    result = zr(<<~'RUBY')
      # A class-body `extend M` runs where it is WRITTEN, not at class registration.
      #
      # `extend M` is a compile-time ancestry edit, so it used to be applied before
      # the body's first statement. Ruby applies it in document order, and the
      # difference is observable the moment the same body also edits the singleton
      # chain at run time: `rb_include_module` searches the WHOLE chain
      # (`search_super = TRUE`) and `rb_prepend_module` only the PREPEND AREA, so
      # whichever verb runs FIRST is the one that finds an empty scope. `prepend M`
      # then `extend M` gives the module one singleton position, because the extend
      # finds the prepended copy; the other order gives it two.
      #
      # The fix is the shape [[zeo-positional-runtime-flags]] keeps finding, and it
      # needed no new mechanism. Both RUNTIME spellings were already right in either
      # order, and `defer_runtime_mixin_in_body` already turns a class-body mixin
      # into a send at its own position -- for a module that defines methods
      # dynamically, and for one that overrides `extend_object`. A body that edits
      # its own singleton chain at run time is a third reason, and that is the whole
      # change.
      #
      # The narrowing matters: only a body that performs a run-time singleton edit
      # defers. Every other class-body `extend` stays a compile-time edit, so the
      # static singleton chain and class-method dispatch are untouched.
      #
      # The sweep found three shapes past the two below -- an `extend` of a DIFFERENT
      # module after a prepend, two prepends against two extends, and an `include`
      # between them -- and they are in
      # tests/a_singleton_chain_edit_orders_against_a_class_body_extend.rb.

      module M
        def hi = "m"
      end

      class Reversed
        singleton_class.prepend M
        extend M
      end
      p Reversed.singleton_class.ancestors.map(&:to_s).first(3)

      # The same two verbs written the other way round agree, and so do both
      # runtime spellings.
      class Ordered
        extend M
        singleton_class.prepend M
      end
      p Ordered.singleton_class.ancestors.map(&:to_s).first(4)
    RUBY

    _(result).must_answer <<~'OUT'
      ["M", "#<Class:Reversed>", "#<Class:Object>"]
      ["M", "#<Class:Ordered>", "M", "#<Class:Object>"]
    OUT
  end

  it "class level ivars are per class and not inherited" do
    result = zr(<<~'RUBY')
      # The defining property of class-level `@x`, and the whole reason it
      # can't share `@@x`'s storage: a subclass gets its OWN slot, starting
      # empty, even though it inherits the method that reads it. Contrast the
      # `@@cv` line, which IS shared. Oracle-verified (ruby 4.0.6).

      class Base
        @reg = "base-ivar"
        @@cv = "base-cvar"
        def self.reg; @reg; end
        def self.reg=(v); @reg = v; end
        def self.cv; @@cv; end
        def self.unset; @never_written; end
      end
      class Sub < Base; end
      p Base.reg
      p Sub.reg
      p Sub.cv
      p Base.unset
      Sub.reg = "sub-only"
      p [Base.reg, Sub.reg]
    RUBY

    _(result).must_answer <<~'OUT'
      "base-ivar"
      nil
      "base-cvar"
      nil
      ["base-ivar", "sub-only"]
    OUT
  end

  it "clone runs user initialize copy hook with super" do
    result = zr(<<~'RUBY')
      # clone/dup dispatch the user's initialize_copy (deep-copying a
      # shared member), and its bare `super` resolves Object's default no-op
      # hook instead of panicking.

      class Board
        def initialize
          @table = [[1], [2]]
        end
        def initialize_copy(orig)
          super
          @table = @table.clone
        end
        def push_row
          @table.push([9])
        end
        def size
          @table.length
        end
      end
      b = Board.new
      c = b.clone
      c.push_row
      puts c.size
      puts b.size
    RUBY

    _(result).must_answer "3\n2\n"
  end

  it "default arg ivar module subclass" do
    result = zr(<<~'RUBY')
      # A default-argument @ivar read, where the method is mixed in via a module and
      # called on a subclass, requires the subclass struct to inherit the ivar field
      # (the parent only gained it from the transplanted module method).
      module M
        def set_it
          @__r = "v"
        end
        def get_it(r = @__r)
          r
        end
      end
      class Base2
        include M
      end
      class Child < Base2
      end
      c = Child.new
      c.set_it
      puts c.get_it
    RUBY

    _(result).must_answer "v\n"
  end

  it "dynamic is a" do
    result = zr(<<~'RUBY')
      # Issue #404 Phase 3 Tier 3. Dynamic is_a?(klass) where the
      # klass argument is a sp_Class value (variable or parameter)
      # rather than a ConstantReadNode. Pre-Tier-3 the codegen
      # read @nd_name on the arg as the bare class name and so
      # couldn't resolve a Class-typed local. Tier 3 routes through
      # sp_class_le at runtime so the hierarchy check happens
      # against whichever class the variable carries.
      #
      # Coverage:
      #   - Typed recv (obj_Dog) with dynamic klass parameter.
      #     Routes through compile_introspection_expr's new dynamic
      #     arg arm; sp_class_le over the precomputed ancestors.
      #   - Typed recv with concrete vs unrelated klass.
      #   - Same recv with a module-typed klass (Tier 2 +
      #     ancestors-table glue).

      module Trainable
      end

      class Animal
      end

      class Dog < Animal
        include Trainable
      end

      class Cat < Animal
      end

      d = Dog.new
      animal_klass = Animal
      cat_klass = Cat
      trainable_klass = Trainable

      puts d.is_a?(animal_klass)     ? "dog-is-animal" : "dog-not-animal"
      puts d.is_a?(cat_klass)        ? "dog-is-cat"    : "dog-not-cat"
      puts d.is_a?(trainable_klass)  ? "dog-trainable" : "dog-not-trainable"

      c = Cat.new
      puts c.is_a?(animal_klass)     ? "cat-is-animal" : "cat-not-animal"
      puts c.is_a?(trainable_klass)  ? "cat-trainable" : "cat-not-trainable"
    RUBY

    _(result).must_answer <<~'OUT'
      dog-is-animal
      dog-not-cat
      dog-trainable
      cat-is-animal
      cat-not-trainable
    OUT
  end

  it "an extended object answers is_a? for the module, and its class does not" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      puts a.greet
      p a.is_a?(Greet)
      p b.is_a?(Greet)
      p a.kind_of?(Greet)
      p Greet === a
      p Greet === b
      p a.instance_of?(Greet)
      p a.class
      p a.class.ancestors.include?(Greet)
      p a.singleton_class.ancestors.include?(Greet)
      p Person.new("c").is_a?(Greet)

    RUBY

    _(result).must_answer <<~'OUT'
      hey a
      true
      false
      true
      true
      false
      false
      Person
      false
      true
      false
    OUT
  end

  it "is_a? answers the same through a call, where the receiver is not statically known" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # Through a call, so the receiver is not statically known at the call site.
      def greetable?(x) = x.is_a?(Greet)
      p greetable?(a)
      p greetable?(b)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
    OUT
  end

  it "case/when and a pattern-match in reach the same answer" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # `case`/`when` and a pattern-match `in` reach the same answer.
      [a, b].each do |x|
        case x
        when Greet then puts "when: yes"
        else puts "when: no"
        end
      end
      [a, b].each do |x|
        case x
        in Greet then puts "in: yes"
        else puts "in: no"
        end
      end
      p [a, b].grep(Greet).size

    RUBY

    _(result).must_answer <<~'OUT'
      when: yes
      when: no
      in: yes
      in: no
      1
    OUT
  end

  it "an extended module carries its own includes with it" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # An extended module carries its own includes.
      n = Person.new("n")
      n.extend(Nested)
      p n.is_a?(Nested)
      p n.is_a?(Tagged)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "a bare collection, a String and nil each take an extend, where an Integer refuses" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # Non-Object receivers: a bare collection, a string, and nil all take one.
      p [1, 2].extend(Tagged).is_a?(Tagged)
      p "s".extend(Tagged).is_a?(Tagged)
      p nil.extend(Tagged).is_a?(Tagged)
      begin
        5.extend(Tagged)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      TypeError: can't define singleton
    OUT
  end

  it "a class takes an extend in its body and after it, and both reach its singleton" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # A CLASS receiver, both spellings. `extend` in the body and a later
      # `.extend` call put the module on the class's singleton chain -- an
      # INSTANCE of the class is unaffected either way.
      module Registry
        def registered = "registered #{self}"
      end

      class Widget
        extend Registry
      end

      class Gadget; end
      Gadget.extend(Registry)

      puts Widget.registered
      puts Gadget.registered
      p Widget.is_a?(Registry)
      p Gadget.is_a?(Registry)
      p Widget.singleton_class.ancestors.include?(Registry)
      p Gadget.singleton_class.ancestors.include?(Registry)
      p Widget.new.is_a?(Registry)
      p Gadget.new.is_a?(Registry)

    RUBY

    _(result).must_answer <<~'OUT'
      registered Widget
      registered Gadget
      true
      true
      true
      true
      false
      false
    OUT
  end

  it "extend self makes a module's instance methods its own module functions" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # `extend self` -- the module-function idiom, whose whole point is that the
      # module becomes an instance of itself.
      module Util
        extend self
        def double(n) = n * 2
      end
      p Util.double(21)
      p Util.is_a?(Util)

    RUBY

    _(result).must_answer <<~'OUT'
      42
      true
    OUT
  end

  it "two extends layer newest closest, and a repeat is a no-op" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # Two extends layer, newest closest to the singleton, and a repeat is a no-op.
      module First
        def which = "first"
      end
      module Second
        def which = "second"
      end
      layered = Person.new("l")
      layered.extend(First)
      layered.extend(Second)
      layered.extend(First)
      puts layered.which
      p layered.is_a?(First)
      p layered.is_a?(Second)
      p layered.singleton_class.ancestors.take(3).drop(1)

    RUBY

    _(result).must_answer <<~'OUT'
      second
      true
      true
      [Second, First]
    OUT
  end

  it "a singleton class asked for before the extend reports the same chain after it" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # A singleton class asked for BEFORE the extend reports the same chain as one
      # asked for after -- it is one class, not two.
      late = Person.new("late")
      sc = late.singleton_class
      late.extend(Greet)
      p sc.equal?(late.singleton_class)
      p sc.ancestors.include?(Greet)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "dup drops the extension, as it drops every singleton" do
    result = zr(<<~'RUBY')
      # `extend` changes what a receiver IS, not only what it answers: the module
      # joins that ONE object's singleton chain, so `is_a?`, `===`, `case`/`when`,
      # a `ClassCheck` pattern and `singleton_class.ancestors` all see it while the
      # receiver's class -- and every other instance of it -- stay untouched.

      module Greet
        def greet = "hey #{name}"
      end

      module Tagged; end

      module Nested
        include Tagged
      end

      class Person
        def initialize(name) = @name = name
        def name = @name
      end

      a = Person.new("a")
      b = Person.new("b")
      a.extend(Greet)

      # `dup` drops the extension, as it drops every singleton.
      p a.dup.is_a?(Greet)
    RUBY

    _(result).must_answer <<~'OUT'
      false
    OUT
  end

  it "extend module is a" do
    result = zr(<<~'RUBY')
      # `obj.extend(Mod)` transplants the module's methods onto a synthesized
      # singleton subclass, but recorded no membership -- so the extended object
      # answered `is_a?(Mod)` with false while already running the module's method.
      # The two halves of the same fact disagreed (#4080).
      module Loud
        def speak = "LOUD"
      end

      module Soft
        def whisper = "soft"
      end

      class Base
        def speak = "base"
      end

      a = Base.new
      a.extend(Loud)
      p a.speak
      p a.is_a?(Loud)
      p a.is_a?(Base)
      p a.is_a?(Soft)

      # a sibling instance is untouched
      p Base.new.is_a?(Loud)
      p Base.new.speak

      # two modules on one object
      b = Base.new
      b.extend(Loud)
      b.extend(Soft)
      p b.is_a?(Loud)
      p b.is_a?(Soft)
      p b.whisper

      # and a plain include still answers the same way
      class C
        include Loud
      end

      p C.new.is_a?(Loud)
      p C.new.speak
    RUBY

    _(result).must_answer <<~'OUT'
      "LOUD"
      true
      true
      false
      false
      "base"
      true
      true
      "soft"
      true
      "LOUD"
    OUT
  end

  it "extend module ivar" do
    result = zr(<<~'RUBY')
      module ClassMethods
        def label
          @label
        end

        def label=(v)
          @label = v
        end

        def described
          "<#{@label.inspect}>"
        end
      end

      class Win
        extend ClassMethods
      end

      class Other
        extend ClassMethods
      end

      p Win.label
      Win.label = "main"
      p Win.label
      p Win.described
      p Other.label
      Other.label = "second"
      p [Win.label, Other.label]
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "main"
      "<\"main\">"
      nil
      ["main", "second"]
    OUT
  end

  it "module reopen after include ivar" do
    result = zr(<<~'RUBY')
      # #572 follow-up to #573 (Sam Ruby). After 8ca93b4 wired late-
      # reopened module methods into namespaced including classes, the
      # struct-layout side missed: an ivar written by a late-reopened
      # method (`@session ||= ...` in `Dispatch#post`, then included by
      # `NS::IntegrationTest`) wasn't added to the host class's
      # @cls_ivar_names. The C emit referenced `self->iv_session` against
      # a struct that didn't declare the field; C compile failed.
      #
      # Fix: reconcile_class_includes re-runs collect_ivars on any class
      # whose method count grew, so the now-attached method bodies get
      # scanned for InstanceVariable*Write nodes.

      module Dispatch
      end

      class Base
      end

      module NS
        class IntegrationTest < Base
          include Dispatch
        end
      end

      module Dispatch
        def post(path)
          @session ||= "session-obj"
          puts @session
          puts path
        end
      end

      NS::IntegrationTest.new.post("/foo")
    RUBY

    _(result).must_answer "session-obj\n/foo\n"
  end

  it "remove_instance_variable, singleton_class, singleton_method and extend each reach the object's own table" do
    result = zr(<<~'RUBY')
      # Object/Kernel protocol: remove_instance_variable (value + NameError),
      # singleton_class (on an object and a builtin value), singleton_method, and
      # extend across every module kind -- a user compile-time module and a builtin
      # module (Comparable) -- reaching the object's singleton table.

      class Box
        def initialize; @v = 1; @s = "hi"; end
        def drop; remove_instance_variable(:@v); end
      end
      b = Box.new
      p b.drop
      p(begin; b.remove_instance_variable(:@nope); rescue NameError => e; e.message; end)
      p "x".singleton_class.class
      p Object.new.singleton_class.superclass
      o = Object.new
      def o.greet; "hey"; end
      p o.singleton_method(:greet).call
      sc = Object.new
      sc.singleton_class.define_method(:doubled) { 21 * 2 }
      p sc.doubled
      module Greet; def hi(n); "hi #{n}"; end; end
      u = Object.new
      u.extend(Greet)
      p u.hi("ada")
      n = Object.new
      n.extend(Comparable)
      p n.respond_to?(:clamp)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "instance variable @nope not defined"
      Class
      Object
      "hey"
      42
      "hi ada"
      true
    OUT
  end

  it "own singleton method outranks an extended module" do
    result = zr(<<~'RUBY')
      # CRuby ancestry: a receiver's own `def self.x` beats a module it extends.

      module Mixin
        def label; "from mixin"; end
      end
      module Host
        def self.label; "from host"; end
      end
      Host.extend(Mixin)
      puts Host.label
    RUBY

    _(result).must_answer "from host\n"
  end

  it "runtime include propagates to subclasses" do
    result = zr(<<~'RUBY')
      # A runtime `include` into a superclass must be visible to subclasses minted
      # EARLIER (CRuby ancestry is shared structure; zeo chains are flat snapshots
      # that the splice now revisits). rspec's runner does exactly this: `describe`
      # mints ExampleGroup subclasses, then configure_mock_framework includes the
      # mock adapter into ExampleGroup.
      class Base
      end

      module Adapter
        def adapter_says
          "adapter on #{self.class.name || "anon"}"
        end
      end

      k = Class.new(Base)
      Base.include(Adapter)
      p k.new.adapter_says
      p k.new.is_a?(Adapter)

      # Ruby >= 3.0: include into a module ALREADY mixed in elsewhere reaches its
      # hosts too.
      module Layer
      end

      class Host
        include Layer
      end

      module LateAddition
        def late
          "late reached #{self.class}"
        end
      end

      Layer.include(LateAddition)
      p Host.new.late
      p Host.ancestors.include?(LateAddition)

      # The prepend placement propagates the same way, and shadows the host's own
      # definition through a subclass instance.
      class PBase
        def who
          "base"
        end
      end

      sub = Class.new(PBase)
      module Shadow
        def who
          "shadow over #{super}"
        end
      end
      PBase.prepend(Shadow)
      p sub.new.who
    RUBY

    _(result).must_answer <<~'OUT'
      "adapter on anon"
      true
      "late reached Host"
      true
      "shadow over base"
    OUT
  end

  it "singleton methods inherit flag" do
    result = zr(<<~'RUBY')
      # The optional `inherit` argument on the singleton-listing family.
      #
      # Narrowing has to reach all three places a class method can live: the
      # compile-time registry (where materialization copies every inherited
      # `def self.x` onto each subclass), the runtime overlay (which an `extend`
      # writes onto the extended class alone), and the builtin class-method table.
      #
      # `methods(false)` is the trap: CRuby answers `singleton_methods(false)` from
      # it, dropping the class's instance methods entirely rather than narrowing
      # them, so it cannot share `public_methods`' body.

      class FBase
        def self.frozen_tag = "ft"
        def inst = "i"
      end
      class FSub < FBase
        def self.sub_tag = "st"
      end

      p FSub.frozen_tag
      p FSub.singleton_methods.include?(:frozen_tag)
      p FBase.singleton_methods(false)
      p FSub.singleton_methods(false)

      # `false` and `nil` both narrow; every other argument, and none at all, does not.
      p FSub.singleton_methods(nil)
      p FSub.singleton_methods(true).sort
      p FSub.singleton_methods.sort

      # `methods(false)` IS the singleton list -- no instance methods at all.
      p FSub.methods(false)
      p FSub.new.methods(false)
      p FBase.new.methods(false)

      module Store
        def tag = "tagged"
      end
      class RBase; end
      RBase.extend Store
      class RSub < RBase; end

      p RSub.tag
      p RSub.singleton_methods.include?(:tag)
      p RSub.singleton_methods(false)
      p RBase.singleton_methods(false)
      p RSub.methods(false)

      # A `define_singleton_method` lands on the receiver alone, the same way.
      class DBase; end
      DBase.define_singleton_method(:minted) { "m" }
      class DSub < DBase; end
      p DSub.minted
      p DBase.singleton_methods(false)
      p DSub.singleton_methods(false)

      # `private_class_method` keeps a name off both widths.
      class PBase
        def self.hidden = "h"
        private_class_method :hidden
      end
      p PBase.singleton_methods(false)
      p PBase.methods(false)

      # The instance-side flags are unaffected: they narrow, they do not empty.
      p FSub.new.private_methods(false).include?(:puts)
      p FSub.instance_methods(false)
      p FSub.new.public_methods(false).include?(:inst)
    RUBY

    _(result).must_answer <<~'OUT'
      "ft"
      true
      [:frozen_tag]
      [:sub_tag]
      [:sub_tag]
      [:frozen_tag, :sub_tag]
      [:frozen_tag, :sub_tag]
      [:sub_tag]
      []
      []
      "tagged"
      true
      []
      []
      []
      "m"
      [:minted]
      []
      []
      []
      false
      []
      false
    OUT
  end

  it "super in a singleton def on a value is a block" do
    result = zr(<<~'RUBY')
      # `super` inside a `def` in a `class << SOME_VALUE` body raises
      # "super called outside of method". The method itself installs and dispatches
      # correctly -- only `super` is wrong -- so the body is reaching the runtime as
      # a BLOCK rather than as a method.
      #
      # `desugar_singleton_items` rebinds a `class << obj` body onto a synthesized
      # `obj.singleton_class`, which is the per-object path (the `class << self`
      # path is `map_class_self_items`, and a plain `def` on either works -- see
      # `an_alias_of_a_builtin_binds_the_body.rb` and this file's own second case).
      # What the rebind does not carry is the frame kind, so `super` has no method
      # entry to walk up from.
      #
      # Found while running `extconf.rb` under zeo for the C extension work.
      # `lib/mkmf.rb` opens with
      #
      #     STRING_OR_FAILED_FORMAT = "%s"
      #     class << STRING_OR_FAILED_FORMAT
      #       def %(x) = x ? super : "failed"
      #     end
      #
      # which is the shape below, and it is the first thing that stops mkmf from
      # loading. So this gap blocks the whole C-extension build pipeline, not just
      # a corner of reflection.

      module M
        FMT = "%s"
        class << FMT
          def %(other)
            other ? super : "failed"
          end
        end
      end

      p M::FMT % "ok"
      p M::FMT % nil

      # The control: the same singleton def with no `super` already works, which is
      # what narrows this to the frame kind rather than the rebind.
      module N
        TAG = "tag"
        class << TAG
          def shout = upcase
        end
      end
      p N::TAG.shout
    RUBY

    _(result).must_answer <<~'OUT'
      "ok"
      "failed"
      "TAG"
    OUT
  end

  it "super reaches the default inspect" do
    result = zr(<<~'RUBY')
      # `Kernel#inspect` and `Kernel#to_s` AS METHOD BODIES describe the object
      # -- CRuby's `rb_obj_inspect` and `rb_any_to_s`. They must not ask the
      # receiver, or a `super` from an override re-enters the override.
      #
      # The generic renderer behind `p`, interpolation and container elements
      # DOES ask, which is why the two have to be separate: the rows below pin
      # both halves at once.

      class Widget
        def inspect = "W:" + super
      end
      puts Widget.new.inspect.start_with?("W:#<Widget:0x")

      class Gadget
        def to_s = "G:" + super
      end
      puts Gadget.new.to_s.start_with?("G:#<Gadget:0x")

      # The default inspect still lists the ivars, through super as well.
      class Boxed
        def initialize = @n = 7
        def inspect = "B" + super
      end
      puts Boxed.new.inspect.include?("@n=7")

      # The generic side: `p` and interpolation ask the override, and a
      # container asks it per element.
      class Loud
        def inspect = "LOUD"
        def to_s = "loud"
      end
      p Loud.new
      puts "#{Loud.new}"
      p [Loud.new]

      # A Struct's members survive the same path.
      S = Struct.new(:a)
      class S
        def inspect = "S:" + super
      end
      puts S.new(1).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      LOUD
      loud
      [LOUD]
      S:#<struct S a=1>
    OUT
  end
end
