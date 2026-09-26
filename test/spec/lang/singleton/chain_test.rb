# frozen_string_literal: true

require "spec_helper"

describe "Singleton programs" do
  it "the class-method channel is the derived singleton chain, swept against ruby" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

    RUBY

    _(result).must_answer ""
  end

  it "one module extended onto a class holds one position, and super reaches the tail" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      puts "== one module, one position, super reaches the tail"
      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end
      p One.tag
      p One.singleton_class.ancestors.map(&:to_s).first(3)
      p One.method(:tag).owner.to_s
      p [One.respond_to?(:tag), One.singleton_methods(false)]

    RUBY

    _(result).must_answer <<~'OUT'
      == one module, one position, super reaches the tail
      "M1(top)"
      ["#<Class:One>", "M1", "#<Class:Object>"]
      "M1"
      [true, []]
    OUT
  end

  it "an own def self.x sits ahead of the module the class extended" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      puts "== an own def self.x sits BEFORE the extended module"
      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      p OwnFirst.tag
      p OwnFirst.method(:tag).owner.to_s
      p OwnFirst.method(:tag).super_method&.owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == an own def self.x sits BEFORE the extended module
      "own(M1(top))"
      "#<Class:OwnFirst>"
      "M1"
    OUT
  end

  it "the last extend is the closest of several" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      puts "== extend order: the LAST extend is closest"
      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end
      p TwoMods.tag
      p TwoMods.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == extend order: the LAST extend is closest
      "M2(M1(top))"
      ["#<Class:TwoMods>", "M2", "M1", "#<Class:Object>"]
    OUT
  end

  it "a module reached by both extend and a singleton prepend holds two positions" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      puts "== a module reached BOTH ways holds two positions"
      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      p BothWays.tag
      p BothWays.singleton_class.ancestors.map(&:to_s).first(4)

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end
      p BothNoOwn.tag
      p BothNoOwn.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == a module reached BOTH ways holds two positions
      "cm(own(cm(top)))"
      ["CM", "#<Class:BothWays>", "CM", "#<Class:Object>"]
      "cm(cm(top))"
      ["CM", "#<Class:BothNoOwn>", "CM", "#<Class:Object>"]
    OUT
  end

  it "the reverse order of those two verbs gives the module one position" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      puts "== the reverse order gives ONE position"
      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM
      p PrependFirst.tag
      p PrependFirst.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == the reverse order gives ONE position
      "cm(top)"
      ["CM", "#<Class:PrependFirst>", "#<Class:Object>"]
    OUT
  end

  it "two singleton prepends stack latest closest, and super walks down them" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      puts "== two prepends stack, latest closest, and super walks down"
      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB
      p Stacked.tag
      p Stacked.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == two prepends stack, latest closest, and super walks down
      "PB(PA(own(top)))"
      ["PB", "PA", "#<Class:Stacked>", "#<Class:Object>"]
    OUT
  end

  it "a module that includes another brings both into the singleton chain" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      puts "== a module that includes another, extended"
      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end
      p Nested.tag
      p Nested.singleton_class.ancestors.map(&:to_s).first(4)
      p Nested.method(:tag).owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == a module that includes another, extended
      "outer(inner(top))"
      ["#<Class:Nested>", "Outer", "Inner", "#<Class:Object>"]
      "Outer"
    OUT
  end

  it "the parent's extend is reached from the child" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      puts "== inheritance: the parent's extend is reached from the child"
      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end
      p [Parent.tag, Child.tag, GrandChild.tag]
      p Child.singleton_class.ancestors.map(&:to_s).first(4)
      p [Parent.method(:tag).owner.to_s, GrandChild.method(:tag).owner.to_s]

    RUBY

    _(result).must_answer <<~'OUT'
      == inheritance: the parent's extend is reached from the child
      ["M1(top)", "M1(top)", "M1(top)"]
      ["#<Class:Child>", "#<Class:Parent>", "M1", "#<Class:Object>"]
      ["M1", "M1"]
    OUT
  end

  it "the child's own extend sits ahead of the parent's" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      puts "== the child adds its own extend, which sits ahead of the parent's"
      class ChildExtends < Parent
        extend M2
      end
      p ChildExtends.tag
      p ChildExtends.singleton_class.ancestors.map(&:to_s).first(5)

    RUBY

    _(result).must_answer <<~'OUT'
      == the child adds its own extend, which sits ahead of the parent's
      "M2(M1(top))"
      ["#<Class:ChildExtends>", "M2", "#<Class:Parent>", "M1", "#<Class:Object>"]
    OUT
  end

  it "a prepend on the parent's singleton is reached by super from the child" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      puts "== a prepend on the PARENT's singleton, reached by super from the child"
      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end
      p [PrependedParent.tag, PrependedChild.tag]
      p PrependedChild.singleton_class.ancestors.map(&:to_s).first(5)

    RUBY

    _(result).must_answer <<~'OUT'
      == a prepend on the PARENT's singleton, reached by super from the child
      ["PA(pp(top))", "pc(PA(pp(top)))"]
      ["#<Class:PrependedChild>", "PA", "#<Class:PrependedParent>", "#<Class:Object>", "#<Class:BasicObject>"]
    OUT
  end

  it "super from the last singleton position reaches Class's own methods" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      puts "== super reaches the instance tail (Class's own methods)"
      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end
      p Tailed.to_s
      p Tailed.name
      p Tailed.inspect

    RUBY

    _(result).must_answer <<~'OUT'
      == super reaches the instance tail (Class's own methods)
      "T(Tailed)"
      "N(Tailed)"
      "Tailed"
    OUT
  end

  it "super with explicit arguments, and a bare super, both pass through a mixin" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      puts "== super with explicit arguments, and zsuper, through a mixin"
      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end
      p ArgHost.build(1)
      p ArgHost.build(1, 3)

    RUBY

    _(result).must_answer <<~'OUT'
      == super with explicit arguments, and zsuper, through a mixin
      "own(over(argmod(1,20)))"
      "own(over(argmod(1,30)))"
    OUT
  end

  it "a prepended module beats define_singleton_method at the same name" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      puts "== define_singleton_method beats a prepended module's copy? no -- prepend wins"
      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }
      p DynHost.tag

    RUBY

    _(result).must_answer <<~'OUT'
      == define_singleton_method beats a prepended module's copy? no -- prepend wins
      "PA(dyn(noSuper))"
    OUT
  end

  it "a class minted at run time takes the same rules" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      puts "== a runtime class takes the same rules"
      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      p RtBase.tag
      RtSub = Class.new(RtBase)
      p RtSub.tag

    RUBY

    _(result).must_answer <<~'OUT'
      == a runtime class takes the same rules
      "rt_own(M1(top))"
      "rt_own(M1(top))"
    OUT
  end

  it "a module has a singleton chain of its own" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      puts "== a MODULE's own singleton chain"
      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end
      p HasSingleton.tag
      p HasSingleton.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == a MODULE's own singleton chain
      "modown(M1(top))"
      ["#<Class:HasSingleton>", "M1", "Module"]
    OUT
  end

  it "remove_method in class << self empties one position, and undef ends the walk" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      puts "== remove_method in class << self empties one position, undef ends the walk"
      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      p Removed.tag
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end
      begin
        Undefed.tag
      rescue NoMethodError
        p "undef ends the walk"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      == remove_method in class << self empties one position, undef ends the walk
      "M1(top)"
      "undef ends the walk"
    OUT
  end

  it "a class-level method_missing is reached through the same chain" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      puts "== a class-level method_missing is reached through the same chain"
      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end
      p Ghosted.ghost
      p Ghosted.respond_to?(:ghost)

    RUBY

    _(result).must_answer <<~'OUT'
      == a class-level method_missing is reached through the same chain
      "mmod_ghost"
      true
    OUT
  end

  it "the instance and class channels answer the same shape independently" do
    result = zr(<<~'RUBY')
      # The CLASS-METHOD channel swept against ruby: every way a module can be
      # seated in a singleton class, every order they can be written in, and what
      # `super`, `defined?(super)`, `Method#owner`, `#super_method` and the
      # reflection surface answer at each position.
      #
      # zr has no singleton-class OBJECTS, so `#<Class:K>` is derived from the
      # instance ancestry: per non-module ancestor, its singleton prepends, its own
      # `def self.x` layer, then its extends. A class method resolves down that
      # derived chain exactly as an instance method resolves down an ordinary one --
      # which is why this file asks the same questions of both sides wherever it
      # can.
      #
      # The shapes that made it worth sweeping: a module reached BOTH ways holds two
      # positions and runs once per position; a materialized copy of an extended
      # module's method bakes the class it was extended ONTO while sitting at the
      # MODULE's position; and a `super` resolved at compile time enters a body the
      # walk also knows a position for, so it has to publish the same one.

      module M1
        def tag = "M1(#{defined?(super) ? super : :top})"
      end
      class One
        extend M1
      end

      class OwnFirst
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      module M2
        def tag = "M2(#{defined?(super) ? super : :top})"
      end
      class TwoMods
        extend M1
        extend M2
      end

      module CM
        def tag = "cm(#{defined?(super) ? super : :top})"
      end
      class BothWays
        extend CM
        singleton_class.prepend CM
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end

      class BothNoOwn
        singleton_class.include CM
        singleton_class.prepend CM
      end

      class PrependFirst; end
      PrependFirst.singleton_class.prepend CM
      PrependFirst.extend CM

      module PA
        def tag = "PA(#{defined?(super) ? super : :top})"
      end
      module PB
        def tag = "PB(#{defined?(super) ? super : :top})"
      end
      class Stacked
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      Stacked.singleton_class.prepend PA
      Stacked.singleton_class.prepend PB

      module Inner
        def tag = "inner(#{defined?(super) ? super : :top})"
      end
      module Outer
        include Inner
        def tag = "outer(#{super})"
      end
      class Nested
        extend Outer
      end

      class Parent
        extend M1
      end
      class Child < Parent; end
      class GrandChild < Child; end

      class ChildExtends < Parent
        extend M2
      end

      class PrependedParent
        def self.tag = "pp(#{defined?(super) ? super : :top})"
      end
      PrependedParent.singleton_class.prepend PA
      class PrependedChild < PrependedParent
        def self.tag = "pc(#{defined?(super) ? super : :top})"
      end

      module Tagger
        def to_s = "T(#{super})"
        def name = "N(#{super})"
      end
      class Tailed
        extend Tagger
      end

      module ArgMod
        def build(a, b = 2) = "argmod(#{a},#{b})"
      end
      class ArgBase
        extend ArgMod
      end
      module ArgOver
        def build(a, b = 2) = "over(#{super(a, b * 10)})"
      end
      class ArgHost < ArgBase
        extend ArgOver
        def self.build(a, b = 2) = "own(#{super})"
      end

      class DynHost
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      DynHost.singleton_class.prepend PA
      DynHost.define_singleton_method(:tag) { "dyn(#{:noSuper})" }

      RtBase = Class.new do
        def self.tag = "rt_own(#{defined?(super) ? super : :top})"
      end
      RtBase.extend M1
      RtSub = Class.new(RtBase)

      module HasSingleton
        extend M1
        def self.tag = "modown(#{defined?(super) ? super : :top})"
      end

      class Removed
        extend M1
        def self.tag = "own(#{defined?(super) ? super : :top})"
      end
      class Removed
        class << self
          remove_method :tag
        end
      end
      class Undefed
        extend M1
        def self.tag = "own"
      end
      class Undefed
        class << self
          undef_method :tag
        end
      end

      module MMod
        def method_missing(n, *a) = n == :ghost ? "mmod_ghost" : super
        def respond_to_missing?(n, p = false) = n == :ghost || super
      end
      class Ghosted
        extend MMod
      end

      puts "== instance and class channels answer the same shape independently"
      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end
      p [BothChannels.new.tag, BothChannels.tag]
      p BothChannels.ancestors.first(3).map(&:to_s)
      p BothChannels.singleton_class.ancestors.map(&:to_s).first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      == instance and class channels answer the same shape independently
      ["inst(dual(top))", "cls(dual(top))"]
      ["BothChannels", "Dual", "Object"]
      ["#<Class:BothChannels>", "Dual", "#<Class:Object>"]
    OUT
  end
end
