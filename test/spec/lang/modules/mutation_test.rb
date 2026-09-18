# frozen_string_literal: true

require "spec_helper"

describe "Modules: changing in place" do
  it "boxs prepend is invisible to main" do
    result = ze0(<<~'RUBY', env: {"RUBY_BOX" => "1"}, ruby: ["-W:no-experimental"])
      # `prepend`, which has to beat the builtin row for the box and leave main's
      # alone.
      #
      # Deliberately its OWN box, not the one above. An `include` FOLLOWED BY a
      # prepend in the same box loses the prepend -- a real divergence, filed as
      # `tests/gaps/a_box_prepend_after_an_include_is_lost.rb`. Main gets that
      # pair right, so it is the box path specifically.



      b = Ruby::Box.new
      b.eval("module BoxPre; def size = 99; end; class Array; prepend BoxPre; end")
      p [1, 2].size
      p b.eval("[1, 2].size")
    RUBY

    _(result).must_answer "2\n99\n"
  end

  it "class prepend ancestors" do
    result = ze0(<<~'RUBY')
      # A prepended module precedes the class in #ancestors (#2702). Dispatch already
      # honoured prepend; only the ancestor listing was missing it.
      module M; def hi; "M"; end; end
      class C; prepend M; def hi; "C"; end; end
      p C.ancestors
      p C.ancestors.include?(M)
      p C.new.hi

      # last prepend lands closest to the front; includes still follow the class
      module A; end
      module B; end
      module I; end
      class Multi
        prepend A
        prepend B
        include I
      end
      p Multi.ancestors
      p(Multi <= A)
      p(Multi < B)

      # a class with no prepend is unchanged
      class Plain; include I; end
      p Plain.ancestors

      # prepend is visible through inheritance
      module P2; end
      class Base2; prepend P2; end
      class Sub2 < Base2; end
      p Sub2.ancestors
    RUBY

    _(result).must_answer <<~'OUT'
      [M, C, Object, Kernel, BasicObject]
      true
      "M"
      [B, A, Multi, I, Object, Kernel, BasicObject]
      true
      true
      [Plain, I, Object, Kernel, BasicObject]
      [Sub2, P2, Base2, Object, Kernel, BasicObject]
    OUT
  end

  it "issue prepend dynamic class body" do
    result = ze0(<<~'RUBY')
      # `prepend` called inside a `Class.new { ... }` block raises NoMethodError
      # instead of prepending the module -- it only works in a literal `class ...
      # end` body.
      m = Module.new do
        def foo
          "prepended-" + super
        end
      end
      klass = Class.new do
        prepend m
        def foo
          "base"
        end
      end
      p klass.new.foo
    RUBY

    _(result).must_answer "\"prepended-base\"\n"
  end

  it "later prepend reaches back" do
    result = ze0(<<~'RUBY')
      module Loud
        def speak = "!" + super + "!"
      end

      module Also
        def speak = "[" + super + "]"
      end

      class Animal
        def speak = "raw"
      end

      class Dog < Animal
        prepend Loud

        def speak = "woof(" + super + ")"
      end

      p Dog.new.speak
      p Dog.ancestors.take(4).map(&:to_s)

      class Dog
        prepend Also
      end

      p Dog.new.speak
      p Dog.ancestors.take(5).map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      "!woof(raw)!"
      ["Loud", "Dog", "Animal", "Object"]
      "[!woof(raw)!]"
      ["Also", "Loud", "Dog", "Animal", "Object"]
    OUT
  end

  it "module both prepended and included" do
    result = ze0(<<~'RUBY')
      # A module PREPENDED and INCLUDED on the same class appears TWICE in CRuby's
      # ancestry -- once ahead of the class, once behind it -- and its body runs
      # once per position.
      #
      # THE EXACT CRUBY RULE, measured against the oracle. It is asymmetric, and the
      # asymmetry is the whole of the behaviour:
      #
      #   include A; prepend A   ->  [A, K, A]   the module appears TWICE
      #   prepend A; include A   ->  [A, K]      the include is a no-op
      #   include A; include A   ->  [K, A]
      #   prepend A; prepend A   ->  [A, K]
      #
      # `rb_include_module` calls `include_modules_at(klass, ORIGIN(klass), module,
      # search_super = TRUE)`, so `include` searches the WHOLE chain and skips a
      # module already anywhere in it. `rb_prepend_module` passes
      # `search_super = FALSE`, so `prepend` searches only the prepend area and adds
      # a module that is merely included below. DOCUMENT ORDER therefore decides:
      # whichever verb runs first is the one that finds an empty chain.
      #
      # The duplicate is what makes `super` interesting. zeo's ancestry is a flat
      # `Vec<ClassId>` and every walk positions by the FIRST match, so a `super`
      # written in the doubled module resumed past the first copy forever and
      # re-found itself. The baked `defining_class` a compiled body hands `super`
      # names the module, which cannot say which copy is running; CRuby has the
      # answer on the control frame (`cfp->cme->defined_class` is the ICLASS).
      # `dispatch::MRO_RESUME` is that fact, published by the walk that enters the
      # body and gated on a chain anywhere in the process holding a repeat.
      #
      # `Method#super_method` needs the same occurrence, or the re-seat finds the
      # first copy again and the chain never ends.

      module MX
        def hi = "mx(#{defined?(super) ? super : 'top'})"
      end

      class Both
        include MX
        prepend MX
        def hi = "Both"
      end

      p Both.ancestors.map(&:to_s)
      p Both.new.hi

      class Runtime
        def hi = "Runtime"
      end
      Runtime.include MX
      Runtime.prepend MX
      p Runtime.ancestors.map(&:to_s)

      # `super` runs the doubled module ONCE PER POSITION, with the class's own
      # body between the two.
      $ran = 0
      module MW
        def go = ($ran += 1; "mw(#{defined?(super) ? super : 'top'})")
      end

      class Sandwich
        include MW
        prepend MW
        def go = "own(#{defined?(super) ? super : 'top'})"
      end

      p Sandwich.ancestors.map(&:to_s)
      p Sandwich.new.go
      p $ran

      # A fresh dispatch from INSIDE the second copy starts over at the first.
      $seen = []
      module MV
        def hop(d)
          $seen << "mv(#{d})"
          Nested.new.hop(2) if d == 1
          defined?(super) ? super : "top"
        end
      end
      class Nested
        include MV
        prepend MV
      end
      p Nested.new.hop(1)
      p $seen

      # `Method`/`UnboundMethod` walk both copies and then stop.
      def owners(m)
        out = []
        while m
          out << m.owner.to_s
          m = m.super_method
        end
        out
      end
      p owners(Sandwich.new.method(:go))
      p owners(Sandwich.instance_method(:go))
    RUBY

    _(result).must_answer <<~'OUT'
      ["MX", "Both", "MX", "Object", "Kernel", "BasicObject"]
      "mx(Both)"
      ["MX", "Runtime", "MX", "Object", "Kernel", "BasicObject"]
      ["MW", "Sandwich", "MW", "Object", "Kernel", "BasicObject"]
      "mw(own(mw(top)))"
      2
      "top"
      ["mv(1)", "mv(2)", "mv(2)", "mv(1)", "mv(2)", "mv(2)"]
      ["MW", "Sandwich", "MW"]
      ["MW", "Sandwich", "MW"]
    OUT
  end

  it "mro" do
    result = ze0(<<~'RUBY')
      class Animal
        def speak
          "generic"
        end
      end

      class Dog < Animal
      end
      puts Dog.new.speak

      module Greetable
        def greet
          "hi"
        end
      end

      class Person
        include Greetable
        def greet
          "overridden"
        end
      end

      class Robot
        include Greetable
      end

      puts Person.new.greet
      puts Robot.new.greet

      module Tagged
        def tag
          "base(#{super})"
        end
      end

      class Widget
        include Tagged
        def tag
          "widget"
        end
      end
      puts Widget.new.tag

      module M1
        def label
          "m1"
        end
      end
      module M2
        def label
          "m2"
        end
      end

      class Stacked
        prepend M1
        prepend M2
        def label
          "own"
        end
      end
      puts Stacked.new.label

      module D
        def who
          "D"
        end
      end
      module B
        include D
      end
      module C
        include D
      end
      class A
        include B
        include C
      end
      puts A.new.who
      puts A.new.is_a?(D)

      module MathHelpers
        def double(x)
          x * 2
        end
      end

      class Calc
        extend MathHelpers
      end
      puts Calc.double(21)

      module Utility
        def self.triple(x)
          x * 3
        end
      end
      puts Utility.triple(4)

      class Base
        @@count = 0
        def bump
          @@count += 1
        end
        def count
          @@count
        end
      end

      class Sub < Base
        def bump_twice
          @@count += 1
          @@count += 1
        end
      end

      b = Base.new
      s = Sub.new
      b.bump
      s.bump_twice
      puts b.count
      puts s.count

      class MyError < StandardError
      end

      class Risky
        def check(n)
          raise MyError, "bad value: #{n}" if n < 0
          n * 2
        end
      end

      r = Risky.new
      puts r.check(5)
    RUBY

    _(result).must_answer <<~'OUT'
      generic
      overridden
      hi
      widget
      m2
      D
      true
      42
      12
      3
      3
      10
    OUT
  end

  it "prepend and include together resolve in correct precedence order" do
    result = ze0(<<~'RUBY')
      # MRO here is `Pre, Own, Inc, Object` -- `Own`'s own `label` calls
      # `super` and reaches `Inc` (the next ancestor after `Own`); `Pre`'s
      # `label` calls `super` and reaches `Own`.

      module Pre
        def label
          "pre(#{super})"
        end
      end
      module Inc
        def label
          "inc"
        end
      end
      class Own
        prepend Pre
        include Inc
        def label
          "own(#{super})"
        end
      end
      puts Own.new.label
    RUBY

    _(result).must_answer "pre(own(inc))\n"
  end

  it "prepend call form" do
    result = ze0(<<~'RUBY')
      # A `C.prepend(M)` CALL (explicit receiver, not the class-body `prepend M` form)
      # is a static structural fact about the class ancestry for a whole-program AOT
      # target -- recognized at analyze time and recorded as the same compile-time
      # `prepends` edit the class-body form makes, so dispatch and `super` see the
      # prepended module through the ordinary flattened MRO. No runtime metaprogramming.

      module Wrap
        def greet
          "[" + super + "]"
        end
      end

      class Bar
        def greet
          "hi"
        end
      end
      Bar.prepend(Wrap)

      puts Bar.ancestors.inspect
      puts Bar.new.greet

      # A prepend that fully overrides (no `super`).
      module Loud
        def shout
          "LOUD"
        end
      end
      class Speaker
        def shout
          "quiet"
        end
      end
      Speaker.prepend(Loud)
      puts Speaker.new.shout

      # A qualified module name, and a prepend onto a class that already has a
      # subclass -- the subclass sees the prepend through its inherited ancestry.
      module Outer
        module Trace
          def run
            "trace:" + super
          end
        end
      end
      class Job
        def run
          "job"
        end
      end
      class SubJob < Job
      end
      Job.prepend(Outer::Trace)
      puts SubJob.new.run
      puts SubJob.ancestors.first(4).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [Wrap, Bar, Object, Kernel, BasicObject]
      [hi]
      LOUD
      trace:job
      [SubJob, Outer::Trace, Job, Object]
    OUT
  end

  it "prepend call form behavior" do
    result = ze0(<<~'RUBY')
      # Comprehensive behavior of the `C.prepend(M)` call-form desugar: reflection
      # (is_a?/kind_of?/ancestors/include?), diamond expansion (a prepended module
      # that itself includes another), multiple separate prepend calls, interaction
      # with a class-body `prepend` on the same class, and `super` from a prepended
      # module reaching an INCLUDED module's method -- all resolved through the
      # ordinary compile-time-flattened MRO, matching ruby.

      # reflection after a prepend call
      module Track
        def step
          "T:" + super
        end
      end
      class Flow
        def step
          "flow"
        end
      end
      Flow.prepend(Track)
      f = Flow.new
      puts f.is_a?(Track)
      puts f.kind_of?(Flow)
      puts Flow.ancestors.inspect
      puts Flow.include?(Track)
      puts f.step

      # a prepended module that itself includes another (diamond expansion)
      module Base
        def label
          "base"
        end
      end
      module Deco
        include Base
        def label
          "deco(" + super + ")"
        end
      end
      class Card
        def label
          "card"
        end
      end
      Card.prepend(Deco)
      puts Card.ancestors.inspect
      puts Card.new.label

      # multiple SEPARATE prepend calls: the later one is closer
      module P
        def tag
          "P" + super
        end
      end
      module Q
        def tag
          "Q" + super
        end
      end
      class Item
        def tag
          "item"
        end
      end
      Item.prepend(P)
      Item.prepend(Q)
      puts Item.ancestors.first(4).inspect
      puts Item.new.tag

      # a prepend call interacting with a class-body prepend on the same class
      module Early
        def val
          "E" + super
        end
      end
      module Late
        def val
          "L" + super
        end
      end
      class Mix
        prepend Early
        def val
          "mix"
        end
      end
      Mix.prepend(Late)
      puts Mix.ancestors.first(4).inspect
      puts Mix.new.val

      # super from a prepended module reaching an INCLUDED module's method
      module Common
        def go
          "common"
        end
      end
      class Runner
        include Common
      end
      module Hook
        def go
          "hook(" + super + ")"
        end
      end
      Runner.prepend(Hook)
      puts Runner.new.go
      puts Runner.ancestors.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      [Track, Flow, Object, Kernel, BasicObject]
      true
      T:flow
      [Deco, Base, Card, Object, Kernel, BasicObject]
      deco(base)
      [Q, P, Item, Object]
      QPitem
      [Late, Early, Mix, Object]
      LEmix
      hook(common)
      [Hook, Runner, Common, Object, Kernel, BasicObject]
    OUT
  end

  it "prepend keeps a subclass own def over a parent overlay" do
    result = ze0(<<~'RUBY')
      module Marker
        def tag = :marker
      end

      class Parent
        def label
          raise NotImplementedError
        end
        [:x].each { |n| define_method(:"dyn_#{n}") { n } }
      end

      class Child < Parent
        def label = :child
      end

      Child.prepend(Marker)
      c = Child.new
      p c.label
      p c.tag
      p Child.ancestors.first(3)
      p Child.instance_method(:label).owner
    RUBY

    _(result).must_answer <<~'OUT'
      :child
      :marker
      [Marker, Child, Parent]
      Child
    OUT
  end

  it "prepend on a builtin class" do
    result = ze0(<<~'RUBY')
      # `C.prepend(M)` on a BUILTIN is a compile-time ancestry edit, and `super` from
      # M's body must resume at C's NATIVE row. Two things were missing: a reopened
      # builtin registers its whole FLATTENED table as value methods, so the `super`
      # probe found M's own copy sitting on C and recursed forever; and a BOOTSTRAP
      # exception class registers once in the runtime, so its chain never learned
      # about the prepend at all.

      module Loud
        def upcase = "<" + super + ">"
      end
      String.prepend(Loud)
      p "ab".upcase
      p String.ancestors.first(2).map(&:to_s)
      p "ab".method(:upcase).owner.to_s
      # Everything else on String is untouched.
      p "ab".downcase
      p "AB".swapcase

      module Twice
        def size = super * 2
      end
      # Two prepends layer, most recent closest. Both written before the first read:
      # WHEN an edit takes effect is the separate question `a_later_prepend_reaches_back`
      # pins.
      module Thrice
        def size = super + 1
      end
      Array.prepend(Twice)
      Array.prepend(Thrice)
      p [1, 2, 3].size
      p [1, 2, 3].length
      p Array.ancestors.first(3).map(&:to_s)

      # A prepend on a BOOTSTRAP exception class.
      module Wrap
        def message = "[" + super + "]"
      end
      StandardError.prepend(Wrap)
      p StandardError.ancestors.first(2).map(&:to_s)
      p StandardError.new("boom").message
      # ... and it reaches every descendant, built-in and user alike.
      p ArgumentError.new("bad").message
      class MyErr < StandardError; end
      p MyErr.ancestors.first(3).map(&:to_s)
      p MyErr.new("mine").message
      p MyErr.new("mine").to_s

      # `include` on a builtin still loses to the class's own rows.
      module Quiet
        def upcase = :quiet
      end
      class Symbol
        include Quiet
      end
      p :ab.upcase
      p Symbol.ancestors.include?(Quiet)
    RUBY

    _(result).must_answer <<~'OUT'
      "<AB>"
      ["Loud", "String"]
      "Loud"
      "ab"
      "ab"
      7
      3
      ["Thrice", "Twice", "Array"]
      ["Wrap", "StandardError"]
      "[boom]"
      "[bad]"
      ["MyErr", "Wrap", "StandardError"]
      "[mine]"
      "mine"
      :AB
      true
    OUT
  end

  it "prepend on builtin super recurses" do
    result = ze0(<<~'RUBY')
      module Loud
        def upcase = "<" + super + ">"
      end

      String.prepend(Loud)
      p "ab".upcase
    RUBY

    _(result).must_answer "\"<AB>\"\n"
  end

  it "prepend super basic" do
    result = ze0(<<~'RUBY')
      # Issue #720 follow-up: `super` inside a prepended method now
      # routes back to the original (overridden) method body via the
      # synthetic shadow registered at prepend time. Before the fix the
      # super call hit the unresolved-call fallback and returned "".
      module M
        def hi
          "prepend-" + super
        end
      end

      class C
        def hi
          "base"
        end
        prepend M
      end

      puts C.new.hi
    RUBY

    _(result).must_answer "prepend-base\n"
  end

  it "prepend super chain" do
    result = ze0(<<~'RUBY')
      # Issue #720 follow-up: prepended super walks through C's own body
      # down to the parent class. MRO is M -> C -> P; M's super -> C's
      # body; C's body's super -> P's body.
      module M
        def hi
          "M(" + super + ")"
        end
      end

      class P
        def hi
          "p"
        end
      end

      class C < P
        def hi
          "c(" + super + ")"
        end
        prepend M
      end

      puts C.new.hi
    RUBY

    _(result).must_answer "M(c(p))\n"
  end

  it "prepend super forward" do
    result = ze0(<<~'RUBY')
      # Issue #720 follow-up: bare `super` (ForwardingSuperNode) inside
      # a prepended method forwards every formal parameter to the
      # shadow, same as the explicit form.
      module M
        def add(a, b)
          super + 100
        end
      end

      class C
        def add(a, b)
          a + b
        end
        prepend M
      end

      puts C.new.add(2, 3)
    RUBY

    _(result).must_answer "105\n"
  end

  it "prepend super multi" do
    result = ze0(<<~'RUBY')
      # Issue #720 follow-up: multiple `prepend` calls stack — each
      # prepend's super walks back through the previous prepend's body
      # and eventually to C's own. MRO is M2 -> M1 -> C; M2's super ->
      # M1; M1's super -> C.
      module M1
        def hi
          "M1(" + super + ")"
        end
      end

      module M2
        def hi
          "M2(" + super + ")"
        end
      end

      class C
        def hi
          "C"
        end
        prepend M1
        prepend M2
      end

      puts C.new.hi
    RUBY

    _(result).must_answer "M2(M1(C))\n"
  end

  it "prepend super subclass" do
    result = ze0(<<~'RUBY')
      # Issue #720 follow-up: a subclass inherits a prepended method
      # correctly. D inherits hi from C; D.new.hi dispatches to C's
      # prepended hi (M's body) and super walks back to C's original
      # body through the shadow chain.
      module M
        def hi
          "M(" + super + ")"
        end
      end

      class C
        def hi
          "c"
        end
        prepend M
      end

      class D < C
      end

      puts D.new.hi
    RUBY

    _(result).must_answer "M(c)\n"
  end

  it "prepend two classes" do
    result = ze0(<<~'RUBY')
      # The prepend transplant MOVED the module's method scope into the prepending
      # class (`sc->class_id = ci`) rather than copying it. The same module prepended
      # by more than one class then gave the first prepender the scope and left every
      # later one with nothing to transplant: its prepend did nothing, silently, and
      # the call fell through to the included chain (#4039). The include path clones
      # for this reason among others.
      module Shouted
        def render(text) = super.upcase
      end
      module Plain
        def render(text) = text
      end

      class A
        include Plain
        prepend Shouted
      end
      class B
        include Plain
        prepend Shouted
      end
      class C
        include Plain
        prepend Shouted
      end
      p [A.new.render("hi"), B.new.render("hi"), C.new.render("hi")]

      # the reported shape: one class prepends alone, another prepends alongside a
      # stack of includes
      module Renderable
        def render(text) = text
      end
      module Trimmed
        def render(text) = super(text.strip)
      end
      module Bracketed
        def render(text) = "[#{super}]"
      end
      module Numbered
        def initialize(*args)
          super()
          @counter = 0
        end
        def render(text)
          @counter += 1
          "#{@counter}. #{super}"
        end
      end

      class Loud
        include Renderable
        include Trimmed
        prepend Shouted
      end

      class Everything
        include Renderable
        include Trimmed
        include Bracketed
        include Numbered
        prepend Shouted
      end

      p Loud.new.render("  hi  ")
      p Everything.new.render("  hi  ")
      p Everything.new.render("  ho  ")

      # a prepended method with parameters, defaults and a block, cloned per class
      module Tagged
        def label(text, sep = ":", &blk) = "<#{super(text, sep, &blk)}>"
      end
      module Basic
        def label(text, sep = ":") = "#{text}#{sep}"
      end
      class D
        include Basic
        prepend Tagged
      end
      class E
        include Basic
        prepend Tagged
      end
      p [D.new.label("d"), E.new.label("e", "!")]

      # the module keeps its own identity for #owner-style questions
      p A.new.is_a?(Shouted)
      p A.ancestors.include?(Shouted)
    RUBY

    _(result).must_answer <<~'OUT'
      ["HI", "HI", "HI"]
      "HI"
      "1. [HI]"
      "1. [HO]"
      ["<d:>", "<e!>"]
      true
      true
    OUT
  end

  it "prepended operator reaches every call site" do
    result = ze0(<<~'RUBY')
      # Each redefinition falls back to `super`, so everything else the
      # operator does stays as it was.
      def add(a, b) = a + b
      def sub(a, b) = a - b
      def mul(a, b) = a * b
      def at(a, i) = a[i]

      p add(1, 2), sub(5, 1), mul(2, 3), at([7], 0)

      module Plus
        def +(o) = o == 100 ? :plus : super
      end
      Integer.prepend(Plus)
      p 1 + 100, add(1, 100), add(1, 2)

      module Later; end
      Integer.prepend(Later)
      module Later
        def -(o) = o == 100 ? :later : super
      end
      p 5 - 100, sub(5, 100), sub(5, 1)

      class Integer
        alias_method :times_before, :*
        def *(o) = o == 100 ? :redefined : times_before(o)
      end
      p 2 * 100, mul(2, 100), mul(2, 3)

      module Index
        def [](i, *rest) = i == 100 ? :index : super
      end
      Array.prepend(Index)
      p [7][100], at([7], 100), at([7], 0)

      class Integer
        private :%
      end
      def mod(a, b) = a % b
      begin
        p mod(7, 2)
      rescue NoMethodError => e
        p e.message
      end

    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      6
      7
      :plus
      :plus
      3
      :later
      :later
      4
      :redefined
      :redefined
      6
      :index
      :index
      7
      "private method '%' called for an instance of Integer"
    OUT
  end

  it "runtime prepend lands where it is written" do
    result = ze0(<<~'RUBY')
      # `K.prepend M` with an explicit receiver is an ordinary send, so the
      # ancestry changes where the CALL is written. zeo recorded it as a
      # compile-time ancestry edit instead, and the prepend was in place from the
      # program's first line -- `K.ancestors` read ABOVE the call already showed
      # the module. What the edit bought was reach: a statically dispatched `K#m`
      # never consults the runtime tables the send writes, so the prepend would
      # override nothing. That is what `defer_mixin_to_runtime` pays for, and the
      # `K.singleton_class.prepend M` form has paid it all along.

      module Loud
        def speak = "LOUD(#{super})"
      end

      class Dog
        def speak = "woof"
      end

      p Dog.ancestors.map(&:to_s)
      p Dog.new.speak
      Dog.prepend Loud
      p Dog.ancestors.map(&:to_s)
      p Dog.new.speak

      # One multi-argument call keeps its arguments in SOURCE order; separate
      # calls put the latest closest to self.
      module A; def tag = "A[#{super}]"; end
      module B; def tag = "B[#{super}]"; end

      class Multi
        def tag = "Multi"
      end
      Multi.prepend A, B
      p Multi.ancestors.map(&:to_s)
      p Multi.new.tag

      class Sep
        def tag = "Sep"
      end
      Sep.prepend A
      Sep.prepend B
      p Sep.ancestors.map(&:to_s)
      p Sep.new.tag
    RUBY

    _(result).must_answer <<~'OUT'
      ["Dog", "Object", "Kernel", "BasicObject"]
      "woof"
      ["Loud", "Dog", "Object", "Kernel", "BasicObject"]
      "LOUD(woof)"
      ["A", "B", "Multi", "Object", "Kernel", "BasicObject"]
      "A[B[Multi]]"
      ["B", "A", "Sep", "Object", "Kernel", "BasicObject"]
      "B[A[Sep]]"
    OUT
  end

  it "stacked prepends resolve in reverse declaration order" do
    result = ze0(<<~'RUBY')
      # `prepend M1; prepend M2` -- M2 (most recently prepended) is closest,
      # ahead of M1, ahead of the class's own definition.

      module M1
        def label
          "m1"
        end
      end
      module M2
        def label
          "m2"
        end
      end
      class Stacked
        prepend M1
        prepend M2
        def label
          "own"
        end
      end
      puts Stacked.new.label
    RUBY

    _(result).must_answer "m2\n"
  end
end
