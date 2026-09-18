# frozen_string_literal: true

require "spec_helper"

describe "Singleton: inheritance and ancestors" do
  it "class methods are inherited by a subclass with no override" do
    result = ze0(<<~'RUBY')
      class Base
        def self.bump
          1
        end
      end
      class Sub < Base
      end
      puts Sub.bump
    RUBY

    _(result).must_answer "1\n"
  end

  it "class shift self include extends the enclosing class" do
    result = ze0(<<~'RUBY')
      # `include M` inside `class << self` == `extend M` on the enclosing class:
      # the module's instance methods become the class's class methods.

      module Greeter
        def hi(n); "hi #{n}"; end
      end
      class Widget
        class << self
          include Greeter
        end
      end
      puts Widget.hi("bob")
    RUBY

    _(result).must_answer "hi bob\n"
  end

  it "extend a bare value" do
    result = ze0(<<~'RUBY')
      # `value.extend(Mod)` on a bare heap value -- an Array, String or Hash with no
      # object wrapper. optparse's last line is `ARGV.extend(OptionParser::Arguable)`,
      # so every program that reaches rubygems' option parsing runs it.
      module Loud
        def shout = "#{inspect}!"
        def one_more = size + 1
      end

      a = [1, 2]
      p a.extend(Loud).equal?(a)
      p a.shout, a.one_more
      # ...and only THAT value gets it.
      p [3].respond_to?(:shout), a.respond_to?(:shout)

      s = +"hi"
      s.extend(Loud)
      p s.shout, s.one_more

      h = { a: 1 }
      h.extend(Loud)
      p h.one_more

      # A second module layers on top, and an own singleton method still wins.
      module Louder
        def shout = "REALLY LOUD"
      end
      b = [9]
      b.extend(Loud)
      def b.one_more = :mine
      b.extend(Louder)
      p b.shout, b.one_more

      # A native module works the same way.
      c = [3, 1, 2]
      c.extend(Enumerable)
      p c.sort

      # Immediates have no singleton storage; nil and true do.
      [1, 1.5, :sym].each do |v|
        v.extend(Loud)
      rescue TypeError => e
        p [v.class, e.message]
      end
      p nil.extend(Loud).nil?
      p true.extend(Loud)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "[1, 2]!"
      3
      false
      true
      "\"hi\"!"
      3
      2
      "REALLY LOUD"
      :mine
      [1, 2, 3]
      [Integer, "can't define singleton"]
      [Float, "can't define singleton"]
      [Symbol, "can't define singleton"]
      true
      true
    OUT
  end

  it "extend and include can be combined on the same class" do
    result = ze0(<<~'RUBY')
      module Ext
        def helper(x)
          x + 1
        end
      end
      module Inc
        def instance_helper
          "inc"
        end
      end
      class Both
        extend Ext
        include Inc
      end
      puts Both.helper(9)
      puts Both.new.instance_helper
    RUBY

    _(result).must_answer "10\ninc\n"
  end

  it "extend class and module" do
    result = ze0(<<~'RUBY')
      # `extend` works on every receiver kind -- ordinary objects, classes, AND
      # modules. Extending a class or module mixes the argument's instance methods in
      # as the receiver's own singleton (class/module) methods, running with the
      # receiver as `self`. This is what lets SecureRandom.extend(Random::Formatter)
      # and rubygems' Gem::SecureRandom work.

      # 1. Extend an ordinary object (per-object methods).
      module Introspect
        def describe; "a #{self.class}"; end
      end
      obj = Object.new
      obj.extend(Introspect)
      puts obj.describe

      # 2. Extend a CLASS: the module's methods become class methods.
      module Counter
        def bump; @count = (@count || 0) + 1; end
      end
      class Tally
        extend Counter
      end
      puts Tally.bump
      puts Tally.bump

      # 3. Extend a MODULE via a runtime call (not the in-body directive).
      module Sayer
        def say(word); "#{word}!"; end
      end
      module Announcer; end
      Announcer.extend(Sayer)
      puts Announcer.say("hello")
      puts Announcer.respond_to?(:say)

      # 4. Extend a class with a NATIVE module (Comparable) -- its methods run with
      #    the class as self and drive the class's own <=>. This "redispatch to the
      #    receiver" is exactly how SecureRandom.extend(Random::Formatter) reaches the
      #    host's own entropy leaf.
      module Bag
        def self.<=>(other); 0; end
      end
      Bag.extend(Comparable)
      puts Bag.respond_to?(:clamp)
      puts Bag.between?(Bag, Bag)

      # 5. An own singleton method outranks an extended module's method of the same
      #    name (CRuby's "closest singleton" ancestry rule).
      module Named
        def label; "mixed-in"; end
      end
      module Thing
        def self.label; "own"; end
      end
      Thing.extend(Named)
      puts Thing.label
    RUBY

    _(result).must_answer <<~'OUT'
      a Object
      1
      2
      hello!
      true
      true
      true
      own
    OUT
  end

  it "extend class with user module makes class methods" do
    result = ze0(<<~'RUBY')
      module Greeter
        def hello; "hello from #{name}"; end
      end
      class Widget
        def self.name; "Widget"; end
        extend Greeter
      end
      # And the runtime call form on a plain class:
      class Gadget; end
      module M; def tag; "tagged"; end; end
      Gadget.extend(M)
      puts Widget.hello
      puts Gadget.tag
    RUBY

    _(result).must_answer "hello from Widget\ntagged\n"
  end

  it "extend in reopened class" do
    result = ze0(<<~'RUBY')
      # `extend M` written in a REOPENING of the class: the module's methods are
      # transplanted from every body that defines the class, not only the first
      # (#3802).
      class Win
        def self.shown?
          false
        end

        module ClassMethods
          def check
            shown? ? 'yes' : 'no'
          end

          def viewport_width
            100
          end
        end
      end

      class Win
        extend ClassMethods
      end

      puts Win.check
      puts Win.viewport_width

      # the same module extended in the original body still works
      class Dlg
        def self.open?
          true
        end

        module CM
          def state
            open? ? 'open' : 'shut'
          end
        end

        extend CM
      end

      puts Dlg.state
    RUBY

    _(result).must_answer <<~'OUT'
      no
      100
      open
    OUT
  end

  it "extend is seated where it stands" do
    result = ze0(<<~'RUBY')
      # `rb_extend_object` is `rb_include_module(rb_singleton_class(obj), module)`,
      # so a class body's `extend M` seats M in the singleton chain WHERE THE
      # STATEMENT STANDS. zeo knows the edge at compile time and used to have it in
      # place from program start, which made four things visible too early.

      module MR
        def method_removed(n) = ((@removed ||= []) << n)
        def method_undefined(n) = ((@undefined ||= []) << n)
        def method_added(n) = ((@added ||= []) << n)
        def removed = @removed
        def undefined = @undefined
        def added = @added
      end

      # A hook the module supplies does not fire for a definition written above the
      # `extend`.
      class CR
        def a; end
        def b; end
        remove_method :a
        extend MR
        remove_method :b
      end
      p CR.removed

      class CU
        def a; end
        def b; end
        undef_method :a
        extend MR
        undef_method :b
      end
      p CU.undefined

      class CA
        def a; end
        extend MR
        def b; end
      end
      p CA.added

      # The singleton chain gains the module at the statement, not before.
      module MX; end
      class CX
        p singleton_class.ancestors.include?(MX)
        p is_a?(MX)
        extend MX
        p singleton_class.ancestors.include?(MX)
        p is_a?(MX)
      end
      p CX.singleton_class.ancestors.include?(MX)

      # A class method the module supplies is not callable above the `extend`.
      module MC
        def helper = :from_mc
      end
      class CC
        begin
          helper
        rescue NoMethodError, NameError => e
          p e.class
        end
        extend MC
        p helper
      end
      p CC.helper

      # A class with its OWN def keeps it, above the `extend` and below.
      class CO
        def self.helper = :own
        p helper
        extend MC
        p helper
      end

      # Two modules extended by one class: the LAST one seated wins a shared name,
      # which is where `rb_include_module` puts it.
      module M1
        def which = :one
      end
      module M2
        def which = :two
      end
      class CW
        extend M1
        extend M2
      end
      p CW.which
      p CW.singleton_class.ancestors.index(M2) < CW.singleton_class.ancestors.index(M1)

      # The `extended` hook still fires, once, at the statement.
      module MH
        def self.extended(base) = puts("extended #{base}")
      end
      class CH
        puts "before"
        extend MH
        puts "after"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:b]
      [:b]
      [:b]
      false
      false
      true
      true
      true
      NameError
      :from_mc
      :from_mc
      :own
      :own
      :two
      true
      before
      extended CH
      after
    OUT
  end

  it "extend layers its first module nearest" do
    result = ze0(<<~'RUBY')
      # `obj.extend(A, B)` layered B nearest the object, where CRuby layers A.
      #
      # CRuby's `rb_obj_extend` (`object.c`) walks its arguments BACKWARDS -- `argc-1`
      # down to `0` -- and each `extend` inserts above the one before it, so the
      # FIRST argument ends up closest. zeo's `Kernel#extend` walked forwards, which
      # reverses the chain, and with it which module wins a name both define.
      #
      # `Module#include(A, B)` has the same backwards rule and was already right;
      # only the object-side `extend` walked the wrong way.

      module A1
        def who = :a
        def only_a = :only_a
      end
      module B1
        def who = :b
        def only_b = :only_b
      end

      o = Object.new.extend(A1, B1)
      p o.singleton_class.ancestors[1, 2].map(&:to_s)
      p o.who
      p [o.only_a, o.only_b]

      class K; end
      K.extend(A1, B1)
      p K.singleton_class.ancestors[1, 2].map(&:to_s)
      p K.who

      # Two separate calls layer in call order: the LATER one wins.
      q = Object.new
      q.extend(A1)
      q.extend(B1)
      p q.singleton_class.ancestors[1, 2].map(&:to_s)
      p q.who

      # `include` was already right, and stays right.
      class M1
        include A1, B1
      end
      p M1.ancestors[1, 2].map(&:to_s)
      p M1.new.who
    RUBY

    _(result).must_answer <<~'OUT'
      ["A1", "B1"]
      :a
      [:only_a, :only_b]
      ["A1", "B1"]
      :a
      ["B1", "A1"]
      :b
      ["A1", "B1"]
      :a
    OUT
  end

  it "extend module" do
    result = ze0(<<~'RUBY')
      # Issue #721. `class C; extend M; end` should expose M's instance
      # methods as class methods on C. spinel used to silently ignore the
      # extend call; `C.<m>` would fall through to the unresolved-call
      # warning + emit 0.

      module M
        def ext_method; "extended"; end
        def hello(name); "hi " + name; end
      end

      class C
        extend M
      end

      puts C.ext_method
      puts C.hello("world")

      # `def self.X` on M stays on M and is NOT pulled into the extending
      # class (CRuby semantics).
      module N
        def self.solo; "solo-on-N"; end
        def shared; "shared"; end
      end

      class D
        extend N
      end

      puts D.shared
      puts N.solo
    RUBY

    _(result).must_answer <<~'OUT'
      extended
      hi world
      shared
      solo-on-N
    OUT
  end

  it "extend module singleton alias" do
    result = ze0(<<~'RUBY')
      class Win
        class << self
          attr_reader :shown
          attr_accessor :title
          alias_method :shown?, :shown
        end

        module ClassMethods
          def check
            shown? ? "yes" : "no"
          end

          def named
            title.nil? ? "(none)" : title
          end
        end
        extend ClassMethods
      end

      p Win.check
      p Win.named
      Win.title = "hello"
      p Win.named
      p Win.shown?
      p Win.title
    RUBY

    _(result).must_answer <<~'OUT'
      "no"
      "(none)"
      "hello"
      nil
      "hello"
    OUT
  end

  it "extend module super" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A super call from a method in an extended module skips the extending
      # object's own definition.
      #
      module Deco
        def render(text) = "[#{super}]"
      end
      module Loud
        def render(text) = super.upcase
      end
      class Plain
        def render(text) = text
      end

      o = Plain.new
      o.extend(Deco)
      p o.render("x")

      q = Plain.new
      q.extend(Loud)
      p q.render("ab")

      r = Plain.new
      p r.render("plain")

      module Adder
        def bump(n) = super + n
      end
      class Base
        def bump(n) = n * 10
      end
      b = Base.new
      b.extend(Adder)
      p b.bump(3)

      module NoSuper
        def render(text) = "<#{text}>"
      end
      s = Plain.new
      s.extend(NoSuper)
      p s.render("y")
    RUBY

    _(result).must_answer <<~'OUT'
      "[x]"
      "AB"
      "plain"
      33
      "<y>"
    OUT
  end

  it "extend module with native module installs class methods" do
    result = ze0(<<~'RUBY')
      # `SomeModule.extend(Comparable)` -- a native module's methods become the
      # receiver's own module methods, running with the module as `self`.

      module Wrapper
        def self.<=>(other); 0; end
      end
      Wrapper.extend(Comparable)
      puts Wrapper.respond_to?(:clamp)
      puts Wrapper.between?(Wrapper, Wrapper)
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "extend module with user module via runtime call" do
    result = ze0(<<~'RUBY')
      module Sayer
        def say; "said"; end
      end
      module Speaker; end
      Speaker.extend(Sayer)
      puts Speaker.say
      puts Speaker.respond_to?(:say)
    RUBY

    _(result).must_answer "said\ntrue\n"
  end

  it "extended singleton class ancestors" do
    result = ze0(<<~'RUBY')
      # The singleton class of a plain object renders as
      # #<Class:#<Object:0xADDR>>; zeo renders it as the singleton of the object's
      # CLASS (#<Class:Object>) once the object has been extended, losing the
      # per-object identity in ancestors output.
      mod = Module.new do
        def modded
          "modded"
        end
      end

      target = Object.new
      target.extend(mod)
      puts target.modded
      puts target.singleton_class.ancestors.first(2).inspect
      puts Object.new.singleton_class.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      modded
      [#<Class:#<Object:0xADDR>>, #<Module:0xADDR>]
      #<Class:#<Object:0xADDR>>
    OUT
  end

  it "include skips module class methods" do
    result = ze0(<<~'RUBY')
      # Issue #714. `class C; include M; end` should NOT drag M's
      # `def self.X` (class methods on the module) into C as instance
      # methods. Doing so co-opted M's @ivar writes into C's ivar table and
      # clobbered the hoisted `cst_M_<v>` slot, flipping its type from the
      # correct sym_str_hash back to int and breaking subsequent hash ops.

      module M
        @slots = {}
        def self.set(k, v); @slots[k] = v; nil; end
        def self.get(k); @slots.fetch(k, nil); end
      end

      class MyTest
        include M
        def run
          M.set(:title, "Hello")
          puts M.get(:title).inspect
        end
      end

      MyTest.new.run

      # `MyTest.new` should NOT respond to `set` / `get` -- those are
      # class methods on M, not instance methods. Probing via respond_to?
      # (true/false) confirms the include didn't import them.
      puts MyTest.new.respond_to?(:set)
      puts MyTest.new.respond_to?(:get)
    RUBY

    _(result).must_answer <<~'OUT'
      "Hello"
      false
      false
    OUT
  end

  it "issue object extend runtime" do
    result = ze0(<<~'RUBY')
      # Object#extend doesn't actually add the module's instance methods to the
      # receiver's singleton class -- calling the extended method afterward raises
      # NoMethodError.
      m = Module.new do
        def helper
          "ext-help"
        end
      end
      obj = Object.new
      obj.extend(m)
      p obj.helper
    RUBY

    _(result).must_answer "\"ext-help\"\n"
  end

  it "issue singleton class include after extend" do
    result = ze0(<<~'RUBY')
      # `Klass.extend M` INSTALLS M's methods as class methods rather than splicing
      # M into the class's singleton ancestry, so the singleton class does not report
      # M among its ancestors. Reflection-only: dispatch, `respond_to?` and the
      # methods' own behaviour are all correct -- see
      # `tests/runtime_extend_binds_the_class.rb`. Documented under "`extend` on a
      # class, at runtime" in `docs/COMPATIBILITY.md`.
      #
      # Found via singleton.rb's
      # `Once.singleton_class.include?(Singleton::SingletonClassMethods)`.
      module Store
        def tag = "tagged"
      end

      class Klass
      end
      Klass.extend Store

      p Klass.tag
      p Klass.singleton_class.include?(Store)
      p Klass.singleton_class.ancestors.include?(Store)
    RUBY

    _(result).must_answer <<~'OUT'
      "tagged"
      true
      true
    OUT
  end

  it "issue subclass runtime extend" do
    result = ze0(<<~'RUBY')
      # A subclass did not inherit class methods installed by a RUNTIME `extend`.
      # `runtime_extend` writes them into the extended class's own overlay
      # `class_methods`, and both the call and the reflection probed the receiver's
      # own overlay alone. In ruby a subclass's singleton class INHERITS its parent's,
      # so the call resolves through the chain.
      #
      # Only the overlay needed the walk: materialization already copies a frozen
      # `def self.x` onto every subclass's registry entry, but nothing copies
      # something installed at run time.
      #
      # The class-body form (`class Base; extend Store; end`) already worked and is
      # covered by `tests/runtime_extend_binds_the_class.rb`.

      module Store
        def tag = "tagged"
      end

      class Base; end
      Base.extend Store

      class Sub < Base; end
      class Deep < Sub; end

      p Base.tag
      p Sub.tag
      p Deep.tag

      # The reflection has to agree with what dispatch answers.
      p Sub.respond_to?(:tag)
      p Deep.respond_to?(:tag)
      p Sub.singleton_methods.include?(:tag)
      p Sub.method(:tag).call

      # A nearer OWN definition still wins -- ruby's placement rule, and the reason
      # the ancestor walk runs last.
      class Own < Base
        def self.tag = "own"
      end
      p Own.tag

      # `define_singleton_method` on a superclass travels the same way.
      class Root; end
      Root.define_singleton_method(:mark) { "marked" }
      class Leaf < Root; end
      p Root.mark
      p Leaf.mark

      # An unrelated class sees none of it.
      class Other; end
      p Other.respond_to?(:tag)
      begin
        Other.tag
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "tagged"
      "tagged"
      "tagged"
      true
      true
      true
      "tagged"
      "own"
      "marked"
      "marked"
      false
      undefined method 'tag' for class Other
    OUT
  end

  it "module copy and extend primitives" do
    result = ze0(<<~'RUBY')
      # Three things `require "delegate"` and `require "singleton"` need, none of
      # which worked -- and the first was silently destructive.
      #
      # `SomeModule.dup` handed back the ORIGINAL. The reason to dup a module is to
      # edit the copy, so every such edit hit the original: delegate.rb opens with
      # `kernel = ::Kernel.dup` and then undefines six methods on it, which stripped
      # `inspect`/`to_s`/`hash`/`===`/`<=>`/`!~` from the real `Kernel` and from
      # every object in the program. Nothing raised; reflection just started lying,
      # and `Object.instance_method(:inspect)` raised NameError.
      module Sample
        def hello = "hello"
        def bye = "bye"
      end

      copy = Sample.dup
      p copy.equal?(Sample)
      p copy.instance_methods(false).sort

      copy.send(:undef_method, :bye)
      p Sample.instance_methods(false).sort
      p copy.instance_methods(false).sort

      # The load-bearing case, verbatim from delegate.rb.
      kernel = ::Kernel.dup
      kernel.class_eval do
        [:to_s, :inspect, :!~, :===, :<=>, :hash].each { |m| undef_method m }
      end
      p Kernel.method_defined?(:inspect)
      p Object.instance_method(:inspect).class
      p Object.new.inspect.start_with?("#<Object")
      p 1.to_s

      # `Module#append_features` and `#extend_object` are the primitives `include`
      # and `Object#extend` are defined in terms of. They are private, overridable,
      # and -- as the singleton gem does -- `undef_method`-able, which needs them to
      # exist first.
      p Module.private_method_defined?(:append_features)
      p Module.private_method_defined?(:extend_object)

      module Gatekeeper
        def self.extended(c)
          c.singleton_class.send(:undef_method, :extend_object)
        end
      end

      module Guarded
        extend Gatekeeper
      end

      p Guarded.singleton_class.method_defined?(:extend_object)

      # `undef` through a singleton class retires a name the singleton INHERITS, not
      # only one the owner defined: `#<Class:Guarded>`'s ancestors run through
      # `Module`, and `rb_undef` resolves with `rb_method_entry`, which walks the
      # whole chain. zeo checked the owner's class-METHOD space alone, so the line
      # above raised NameError for a method `private_method_defined?` reported on the
      # very same receiver.
      #
      # The tombstone then has to be visible everywhere, because ruby writes it into
      # the singleton's own method table where it shadows `Module`'s definition. Each
      # of these found that definition again behind the undef:
      p Guarded.singleton_class.private_method_defined?(:extend_object)
      p (Guarded.singleton_class.instance_method(:extend_object) rescue $!.class)
      p Guarded.respond_to?(:extend_object, true)
      p (Guarded.send(:extend_object, Object.new) rescue $!.message)

      # A PUBLIC inherited name goes the same way, and the owner's own class methods
      # and every other module are left alone.
      class Klass
        def self.own = :own
      end
      Klass.singleton_class.send(:undef_method, :name)
      p Klass.singleton_class.method_defined?(:name)
      p (Klass.name rescue $!.class)
      p Klass.own
      p String.name
      p Module.private_method_defined?(:extend_object)

      # `extend_object` really is what `Object#extend` runs.
      module Marker
        def marked = "marked"
      end

      target = Object.new
      Marker.send(:extend_object, target)
      p target.marked
    RUBY

    _(result).must_answer <<~'OUT'
      false
      [:bye, :hello]
      [:bye, :hello]
      [:hello]
      true
      UnboundMethod
      true
      "1"
      true
      true
      false
      false
      NameError
      false
      "undefined method 'extend_object' for module Guarded"
      false
      NoMethodError
      :own
      "String"
      true
      "marked"
    OUT
  end

  it "object protocol singleton extend" do
    result = ze0(<<~'RUBY')
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

  it "runtime extend binds the class" do
    result = ze0(<<~'RUBY')
      # `Klass.extend M` written as a RUNTIME call, as opposed to `extend M` in the
      # class body. Zeo ran the module's compiled body against a fresh blank
      # instance of the class, one per call -- so `self` was not the class, an
      # `@ivar` write went to a throwaway object and vanished, and an implicit-self
      # call could only see instance methods. Nothing raised; the writes were simply
      # lost.
      #
      # The singleton gem is built on this: `include Singleton` fires a hook that
      # does `klass.extend SingletonClassMethods` and then
      # `klass.instance_eval { set_mutex(Thread::Mutex.new) }`, and `Singleton#instance`
      # then synchronizes on a mutex that stayed nil.
      module Store
        def set_tag(v)
          @tag = v
        end

        def tag = @tag

        def build = new

        private

        def set_secret(v)
          @secret = v
        end

        def secret = @secret
      end

      class Compiled
        extend Store
      end

      class Runtime
      end
      Runtime.extend Store

      # The class-body form already worked; the runtime form must agree with it.
      Compiled.set_tag("compiled")
      Runtime.set_tag("runtime")
      p [Compiled.tag, Runtime.tag]
      p [Compiled.instance_variable_get(:@tag), Runtime.instance_variable_get(:@tag)]

      # ...through `send`, and through `instance_eval`, which is how the singleton
      # gem reaches its private writers.
      Runtime.send(:set_secret, "hidden")
      p Runtime.send(:secret)
      Runtime.instance_eval { set_tag("via-eval") }
      p Runtime.tag

      # `self` really is the class, so an implicit-self CLASS-method call resolves.
      p Runtime.build.class
      p Compiled.build.class

      # A method taking the class as `self` through a plain call, too.
      def init(klass)
        klass.instance_eval { set_tag("initialized") }
        klass
      end
      p init(Runtime).tag
    RUBY

    _(result).must_answer <<~'OUT'
      ["compiled", "runtime"]
      ["compiled", "runtime"]
      "hidden"
      "via-eval"
      Runtime
      Compiled
      "initialized"
    OUT
  end

  it "sibling extend super chains resolve in extension order" do
    result = ze0(<<~'RUBY')
      # `extend A; extend B; extend C` builds the singleton chain most-recent
      # first (#<Class:Host> -> C -> B -> A -> ...), and `super` walks it per
      # POSITION: the flattened class-method table keeps only winners, so
      # shadowed sibling copies get their own emitted fns registered as
      # singleton super targets (the own_impls distinction, singleton side).
      # A chain also crosses from extends into a parent's `def self.x`.
      # All three outputs verbatim from ruby 4.0.6.

      module A
        def who; "A -> top"; end
      end
      module B
        def who; "B -> " + super; end
      end
      module C
        def who; "C -> " + super; end
      end
      class Host
        extend A
        extend B
        extend C
        def self.who; "Host -> " + super; end
      end
      puts Host.who
      class Host2
        extend A
        extend B
      end
      puts Host2.who
      class Parent
        def self.who; "Parent -> top"; end
      end
      class Kid < Parent
        extend B
        def self.who; "Kid -> " + super; end
      end
      puts Kid.who
    RUBY

    _(result).must_answer <<~'OUT'
      Host -> C -> B -> A -> top
      B -> A -> top
      Kid -> B -> Parent -> top
    OUT
  end

  it "singleton chain edit orders against a class body extend" do
    result = ze0(<<~'RUBY')
      # Every order a class body can put a run-time singleton edit and a
      # compile-time `extend` in. The rule is CRuby's own: `rb_include_module`
      # searches the whole chain and `rb_prepend_module` only the prepend area, so
      # whichever verb runs FIRST finds an empty scope and the other may find its
      # copy already there.
      #
      # Four of these were wrong before a class-body `extend` was given a document
      # position (see a_class_body_extend_is_applied_before_the_body_runs.rb): A, E,
      # F and I. C, D and G were already right, which is why the gap file named one
      # shape and the sweep found four.

      module M
        def hi = "m"
      end
      module N
        def bye = "n"
      end

      def chain(k) = k.singleton_class.ancestors.map(&:to_s).first(5)

      class A
        singleton_class.prepend M
        extend M
      end
      p chain(A); p A.hi; p A.is_a?(M); p A.singleton_class.include?(M)

      class B
        extend M
        singleton_class.prepend M
      end
      p chain(B); p B.hi

      class C
        singleton_class.include M
        extend M
      end
      p chain(C); p C.hi

      class D
        singleton_class.extend M
        extend M
      end
      p chain(D); p D.hi

      class E
        singleton_class.prepend M
        extend N
        extend M
      end
      p chain(E); p E.hi; p E.bye

      class F
        singleton_class.prepend M
        singleton_class.prepend N
        extend M
        extend N
      end
      p chain(F)

      module G
        singleton_class.prepend M
        extend self
        def hi = "g"
      end
      p chain(G); p G.hi

      class H
        extend M
        extend M
      end
      p chain(H)

      class Base
        singleton_class.prepend M
        extend M
      end
      class Sub < Base; end
      p chain(Sub); p Sub.hi

      class I
        singleton_class.prepend M
        include M
        extend M
      end
      p chain(I); p I.ancestors.map(&:to_s).first(3); p I.new.hi
    RUBY

    _(result).must_answer <<~'OUT'
      ["M", "#<Class:A>", "#<Class:Object>", "#<Class:BasicObject>", "Class"]
      "m"
      true
      true
      ["M", "#<Class:B>", "M", "#<Class:Object>", "#<Class:BasicObject>"]
      "m"
      ["#<Class:C>", "M", "#<Class:Object>", "#<Class:BasicObject>", "Class"]
      "m"
      ["#<Class:D>", "M", "#<Class:Object>", "#<Class:BasicObject>", "Class"]
      "m"
      ["M", "#<Class:E>", "N", "#<Class:Object>", "#<Class:BasicObject>"]
      "m"
      "n"
      ["N", "M", "#<Class:F>", "#<Class:Object>", "#<Class:BasicObject>"]
      ["M", "#<Class:G>", "G", "Module", "Object"]
      "m"
      ["#<Class:H>", "M", "#<Class:Object>", "#<Class:BasicObject>", "Class"]
      ["#<Class:Sub>", "M", "#<Class:Base>", "#<Class:Object>", "#<Class:BasicObject>"]
      "m"
      ["M", "#<Class:I>", "#<Class:Object>", "#<Class:BasicObject>", "Class"]
      ["I", "M", "Object"]
      "m"
    OUT
  end

  it "singleton dsm local" do
    result = ze0(<<~'RUBY')
      # `obj.define_singleton_method(:m) { }` compiled on a CONSTANT receiver and
      # stopped the build on a LOCAL one -- the same object, the same synthesized
      # singleton subclass, and `def obj.m` on that local works. The emitter
      # re-derived "is this a singleton receiver?" from the receiver's type, and a
      # local that also carries a `def obj.m` has widened to poly by then, so the
      # call reached the unsupported-feature diagnostic.
      class K
        def base = "base"
      end

      k = K.new
      k.define_singleton_method(:dsm) { "dsm-local" }
      p k.dsm
      p k.base

      # alongside a def on the same local: both land on one subclass
      d = K.new
      def d.plain = "plain"
      d.define_singleton_method(:also) { "also" }
      p d.plain
      p d.also

      # the constant spelling, unchanged
      CFG = K.new
      CFG.define_singleton_method(:on_const) { "const" }
      p CFG.on_const

      # and the rest of the singleton surface still resolves
      e = K.new
      def e.extra = "extra"
      p e.extra
      class << e
        def blockform = "bf"
      end
      p e.blockform
      module M
        def from_mod = "mod"
      end
      f = K.new
      f.extend(M)
      p f.from_mod
      p f.base
    RUBY

    _(result).must_answer <<~'OUT'
      "dsm-local"
      "base"
      "plain"
      "also"
      "const"
      "extra"
      "bf"
      "mod"
      "base"
    OUT
  end

  it "singleton extend timing" do
    result = ze0(<<~'RUBY')
      module Bracketed
        def render(text) = "[" + super + "]"
      end

      class Plain
        def render(text) = text
      end

      loner = Plain.new
      puts "before extend: #{loner.render("hi").inspect}"
      puts "before is_a?:  #{loner.is_a?(Bracketed)}"
      puts "before class:  #{loner.class}"
      loner.extend(Bracketed)
      puts "after extend:  #{loner.render("hi").inspect}"
      puts "after is_a?:   #{loner.is_a?(Bracketed)}"
      puts "after class:   #{loner.class}"

      puts "sibling:       #{Plain.new.render("hi").inspect}"
      puts "sibling is_a?: #{Plain.new.is_a?(Bracketed)}"

      a = Plain.new
      puts "before def: #{a.render("hi")}"
      def a.render(text) = "<" + text + ">"
      puts "after def:  #{a.render("hi")}"

      b = Plain.new
      puts "before scls: #{b.render("hi")}"
      class << b
        def render(text) = "{" + text + "}"
      end
      puts "after scls:  #{b.render("hi")}"

      c = Plain.new
      puts "before dsm: #{c.render("hi")}"
      c.define_singleton_method(:render) { |text| "(" + text + ")" }
      puts "after dsm:  #{c.render("hi")}"

      class Bare
        def shown = "plain"
      end

      def try
        yield
      rescue NoMethodError
        "NoMethodError"
      end

      d = Bare.new
      puts "before new-name: #{try { d.extra }}"
      def d.extra = "added"
      puts "after new-name:  #{d.extra}"
      puts "still shown:     #{d.shown}"

      module Loud
        def speak = "!" + super + "!"
      end

      class Quiet
        def speak = "sh"
      end

      def say(o) = o.speak

      q = Quiet.new
      puts "before: #{say(q)}"
      q.extend(Loud)
      puts "after:  #{say(q)}"

      module A1
        def tag = "a" + super
      end
      module B1
        def tag = "b" + super
      end
      class Base1
        def tag = "-"
      end

      m = Base1.new
      puts "chain none: #{m.tag}"
      m.extend(A1)
      puts "chain A1:   #{m.tag}"
      m.extend(B1)
      puts "chain B1:   #{m.tag}"
      puts "chain is_a? A1: #{m.is_a?(A1)}"
      puts "chain is_a? B1: #{m.is_a?(B1)}"
      puts "chain class:    #{m.class}"

      n = Base1.new
      n.extend(A1, B1)
      puts "both:       #{n.tag}"
      puts "both is_a?: #{n.is_a?(A1)} #{n.is_a?(B1)}"

      o = Base1.new
      o.extend(B1)
      puts "one only:   #{o.tag}"
      puts "one is_a?:  #{o.is_a?(A1)} #{o.is_a?(B1)}"

      SPK = Quiet.new
      puts "const before: #{SPK.speak}"
      puts "const is_a?:  #{SPK.is_a?(Loud)}"
      SPK.extend(Loud)
      puts "const after:  #{SPK.speak}"
      puts "const is_a?:  #{SPK.is_a?(Loud)}"

      CFGD = Quiet.new
      puts "cdef before: #{CFGD.speak}"
      def CFGD.speak = "def"
      puts "cdef after:  #{CFGD.speak}"

      CDSM = Quiet.new
      puts "cdsm before: #{CDSM.speak}"
      CDSM.define_singleton_method(:speak) { "dsm" }
      puts "cdsm after:  #{CDSM.speak}"
    RUBY

    _(result).must_answer <<~'OUT'
      before extend: "hi"
      before is_a?:  false
      before class:  Plain
      after extend:  "[hi]"
      after is_a?:   true
      after class:   Plain
      sibling:       "hi"
      sibling is_a?: false
      before def: hi
      after def:  <hi>
      before scls: hi
      after scls:  {hi}
      before dsm: hi
      after dsm:  (hi)
      before new-name: NoMethodError
      after new-name:  added
      still shown:     plain
      before: sh
      after:  !sh!
      chain none: -
      chain A1:   a-
      chain B1:   ba-
      chain is_a? A1: true
      chain is_a? B1: true
      chain class:    Base1
      both:       ab-
      both is_a?: true true
      one only:   b-
      one is_a?:  false true
      const before: sh
      const is_a?:  false
      const after:  !sh!
      const is_a?:  true
      cdef before: sh
      cdef after:  def
      cdsm before: sh
      cdsm after:  dsm
    OUT
  end

  it "singleton mixin super and override" do
    result = ze0(<<~'RUBY')
      # Two limits of zeo's per-object singleton, both reachable through plain
      # `obj.extend(M)` and therefore PRE-EXISTING -- routing `class << obj; include
      # M` to the same machinery does not create them, it just gives them a second
      # spelling.
      #
      # zeo implements a singleton as a COPIED method table
      # (`runtime_meta::extend_object_default`), where CRuby splices the module into
      # the singleton class's ancestry. Copying loses the module's POSITION, so:
      #
      #   1. `super` from a mixed-in method has nowhere to resume -- it should reach
      #      the receiver class's own definition.
      #   2. a mixed-in method does not reliably outrank the class's own for a
      #      statically-bound call site, because the compiled site resolved before
      #      the extend ran.
      #
      # Fix shape: the singleton needs real spliced ancestry the owner's dispatch
      # walks, not a copied table -- which is also what would let `include` and
      # `prepend` differ from each other, as CRuby's do.

      module Loud
        def speak
          "LOUD(" + super + ")"
        end
      end

      class Speaker
        def speak
          "plain"
        end
      end

      # (1) `super` from an extended module.
      a = Speaker.new
      a.extend(Loud)
      p a.speak

      # (2) the extended module outranking the class's own method.
      b = Speaker.new
      b.extend(Loud)
      p b.speak

      # The same two through the `class << obj` spelling.
      c = Speaker.new
      class << c
        prepend Loud
      end
      p c.speak

      # An extend that ADDS a name (rather than overriding one) already works, and is
      # what the corpus actually needs.
      module Extra
        def extra
          "extra"
        end
      end

      d = Speaker.new
      d.extend(Extra)
      p [d.extra, d.speak, Speaker.new.respond_to?(:extra)]
    RUBY

    _(result).must_answer <<~'OUT'
      "LOUD(plain)"
      "LOUD(plain)"
      "LOUD(plain)"
      ["extra", "plain", false]
    OUT
  end

  it "super from an extended module" do
    result = ze0(<<~'RUBY')
      # `super` written in a module that a class `extend`s, called on a SUBCLASS of
      # that class. Zeo materializes the module's methods onto every class in the
      # chain, so both `Base` and `Sub` carry their own copy -- and the runtime
      # resumed a class-method `super` after the DEFINING class's position in the
      # receiver's ancestry. An extended module is not in that ancestry at all, so
      # the walk restarted at the top and re-entered the copy one level down:
      # `Sub.name` answered `Base`, forever.
      #
      # minitest's Spec::DSL is written exactly this way -- `def name; defined?(@name)
      # ? @name : super; end` -- so every spec class reported its superclass's name.
      module NameDSL
        def name
          defined?(@name) ? @name : super
        end

        def inspect
          "[#{self}] #{super}"
        end
      end

      class Base
        extend NameDSL
      end

      class Sub < Base
      end

      class Deeper < Sub
      end

      p Base.name
      p Sub.name
      p Deeper.name
      p Sub.inspect
      p Deeper.inspect

      # An instance variable set on the subclass still wins over `super`.
      class Named < Base
        @name = "custom"
      end
      p Named.name
      p Named.inspect

      # A class's own `def self.x` sits BEFORE the extended module in the singleton
      # chain, so the module's `super` must skip it and reach the builtin.
      module Tagger
        def to_s
          "T(#{super})"
        end
      end

      class Host
        extend Tagger

        def self.own = "own"
      end

      class HostSub < Host
      end

      p Host.to_s
      p HostSub.to_s
      p HostSub.own

      # Two modules extended into one class chain: `super` walks them in order.
      module Outer
        def stack = "outer:#{super}"
      end

      module Inner
        def stack = "inner:#{super}"
      end

      class Stacked
        extend Inner
        extend Outer

        def self.stack = "base"
      end

      class StackedSub < Stacked
      end

      p Stacked.stack
      p StackedSub.stack
    RUBY

    _(result).must_answer <<~'OUT'
      "Base"
      "Sub"
      "Deeper"
      "[Sub] Sub"
      "[Deeper] Deeper"
      "custom"
      "[Named] Named"
      "T(Host)"
      "T(HostSub)"
      "own"
      "base"
      "base"
    OUT
  end

  it "super in a constant bearing singleton body" do
    result = ze0(<<~'RUBY')
      # A `class << self` body holding a CONSTANT registers its `def`s against a
      # singleton surrogate, so a bare `super` inside one looked for its own scope in
      # a pool that never held it and panicked codegen. faker's `Faker::Base` is this
      # shape.

      class Parent
        def self.describe(prefix)
          "#{prefix}:parent"
        end
      end

      class Child < Parent
        class << self
          NOT_GIVEN = Object.new

          def describe(prefix)
            "#{super}+child"
          end
        end
      end

      p Child.describe("x")
      p Parent.describe("x")
      p Child.singleton_class.const_get(:NOT_GIVEN).class
    RUBY

    _(result).must_answer <<~'OUT'
      "x:parent+child"
      "x:parent"
      Object
    OUT
  end

  it "toplevel extend module" do
    result = ze0(<<~'RUBY')
      module DSL
        def hello
          "hi"
        end

        def twice(x)
          x * 2
        end
      end

      module More
        def bye
          "bye"
        end
      end

      extend DSL
      extend More

      puts hello
      p twice(3)
      p bye
      p [hello, bye].join(" ")

      def wrapper
        hello
      end

      p wrapper
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      6
      "bye"
      "hi bye"
      "hi"
    OUT
  end
end
