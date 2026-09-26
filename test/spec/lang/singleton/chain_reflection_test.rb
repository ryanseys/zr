# frozen_string_literal: true

require "spec_helper"

describe "Singleton programs" do
  it "super_method walks the singleton chain one position per step" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      puts "== #super_method walks the singleton chain, one position per step"
      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      p Chained.tag
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end
      p names

    RUBY

    _(result).must_answer <<~'OUT'
      == #super_method walks the singleton chain, one position per step
      "own(S2(S1))"
      [["#<Class:Chained>", "own(S2(S1))"], ["S2", "S2(S1)"], ["S1", "S1"]]
    OUT
  end

  it "super_method through a doubled module stops instead of looping" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      puts "== #super_method through a DOUBLED module stops instead of looping"
      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end
      p seats

    RUBY

    _(result).must_answer <<~'OUT'
      == #super_method through a DOUBLED module stops instead of looping
      ["CM", "CM"]
    OUT
  end

  it "unbind, bind and instance_method reach through a singleton class" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end

      puts "== unbind/bind and instance_method through a singleton class"
      p Chained.singleton_class.instance_method(:tag).owner.to_s
      p Chained.method(:tag).unbind.owner.to_s
      p Chained.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == unbind/bind and instance_method through a singleton class
      "#<Class:Chained>"
      "#<Class:Chained>"
      ["#<Class:Chained>", "S2", "S1", "#<Class:Object>"]
    OUT
  end

  it "respond_to? and method_defined? agree with the walk" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end


      puts "== respond_to? and method_defined? agree with the walk"
      p [Chained.respond_to?(:tag), Chained.singleton_class.method_defined?(:tag)]
      p [Removed.respond_to?(:tag), Undefed.respond_to?(:tag)]

    RUBY

    _(result).must_answer <<~'OUT'
      == respond_to? and method_defined? agree with the walk
      [true, true]
      [true, false]
    OUT
  end

  it "a frozen class refuses extend and a singleton prepend alike" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      puts "== a frozen class refuses both singleton verbs"
      class FrozenSingleton; end
      FrozenSingleton.freeze
      begin; FrozenSingleton.extend M1; rescue => e; p [e.class, e.message]; end
      begin; FrozenSingleton.singleton_class.prepend M1; rescue => e; p e.class; end

    RUBY

    _(result).must_answer <<~'OUT'
      == a frozen class refuses both singleton verbs
      [FrozenError, "can't modify frozen Class: FrozenSingleton"]
      FrozenError
    OUT
  end

  it "extend on a plain object keeps that object's own chain" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      puts "== extend on a plain OBJECT keeps its own chain"
      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod
      p obj.tag
      p obj.singleton_class.ancestors.map(&:to_s).first(2)
      p obj.method(:tag).owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == extend on a plain OBJECT keeps its own chain
      "obj(top)"
      ["#<Class:#<Object:0xADDR>>", "ObjMod"]
      "ObjMod"
    OUT
  end

  it "a module extended onto a module answers super the same way" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      puts "== a module extended onto a MODULE, and its super"
      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end
      p Extendee.tag
      p Extendee.method(:tag).owner.to_s
      p Extendee.method(:tag).super_method&.owner.to_s

    RUBY

    _(result).must_answer <<~'OUT'
      == a module extended onto a MODULE, and its super
      "modself(M1(top))"
      "#<Class:Extendee>"
      "M1"
    OUT
  end

  it "the walk answers the same on every ask" do
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

      module Dual
        def tag = "dual(#{defined?(super) ? super : :top})"
      end
      class BothChannels
        include Dual
        extend Dual
        def tag = "inst(#{super})"
        def self.tag = "cls(#{super})"
      end

      module S1
        def tag = "S1"
      end
      module S2
        def tag = "S2(#{super})"
      end
      class Chained
        extend S1
        extend S2
        def self.tag = "own(#{super})"
      end
      m = Chained.method(:tag)
      names = []
      while m
        names << [m.owner.to_s, m.call]
        m = m.super_method
      end

      class DoubledSeat
        extend CM
        singleton_class.prepend CM
      end
      d = DoubledSeat.method(:tag)
      seats = []
      6.times do
        break unless d
        seats << d.owner.to_s
        d = d.super_method
      end



      class FrozenSingleton; end
      FrozenSingleton.freeze

      obj = Object.new
      module ObjMod
        def tag = "obj(#{defined?(super) ? super : :top})"
      end
      obj.extend ObjMod

      module Extendee
        extend M1
        def self.tag = "modself(#{defined?(super) ? super : :top})"
      end

      puts "== the walk is stable across repeated asks"
      3.times { print Chained.tag, " " }
      puts
      p Chained.singleton_class.ancestors.map(&:to_s).first(4)

    RUBY

    _(result).must_answer <<~'OUT'
      == the walk is stable across repeated asks
      own(S2(S1)) own(S2(S1)) own(S2(S1)) 
      ["#<Class:Chained>", "S2", "S1", "#<Class:Object>"]
    OUT
  end
end
