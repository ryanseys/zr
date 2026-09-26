# frozen_string_literal: true

require "spec_helper"

describe "Singleton programs" do
  it "a def self.x inside a singleton body sits one level further up" do
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


      puts "== a def self.x inside a singleton body is one level FURTHER up"
      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end
      p MetaHost.plain
      p (MetaHost.meta rescue "MetaHost.meta -> #{$!.class}")
      p MetaHost.singleton_class.meta
      p MetaHost.singleton_class.singleton_methods(false)
      p MetaHost.singleton_methods(false).sort

    RUBY

    _(result).must_answer <<~'OUT'
      == a def self.x inside a singleton body is one level FURTHER up
      "plain"
      "MetaHost.meta -> NoMethodError"
      "meta"
      [:meta]
      [:plain]
    OUT
  end

  it "the same def inside class << obj sits one level further up too" do
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


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      puts "== the same inside class << obj"
      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end
      p target.plain
      p (target.meta rescue "target.meta -> #{$!.class}")
      p target.singleton_class.meta

    RUBY

    _(result).must_answer <<~'OUT'
      == the same inside class << obj
      "obj_plain"
      "target.meta -> NoMethodError"
      "obj_meta"
    OUT
  end

  it "a meta method takes arguments and a block like any other" do
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


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end

      puts "== a meta method takes arguments and a block like any other"
      class MetaArgs
        class << self
          def self.build(a, b = 2) = "build(#{a},#{b})"
          def self.each_twice = [yield(1), yield(2)]
        end
      end
      p MetaArgs.singleton_class.build(9)
      p MetaArgs.singleton_class.build(9, 3)
      p(MetaArgs.singleton_class.each_twice { |i| i * 10 })

    RUBY

    _(result).must_answer <<~'OUT'
      == a meta method takes arguments and a block like any other
      "build(9,2)"
      "build(9,3)"
      [10, 20]
    OUT
  end

  it "a meta method beside a mixin in one singleton body keeps its position" do
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


      class MetaHost
        class << self
          def plain = "plain"
          def self.meta = "meta"
        end
      end

      target = Object.new
      class << target
        def plain = "obj_plain"
        def self.meta = "obj_meta"
      end

      class MetaArgs
        class << self
          def self.build(a, b = 2) = "build(#{a},#{b})"
          def self.each_twice = [yield(1), yield(2)]
        end
      end

      puts "== a meta method beside a mixin in the same singleton body"
      module MetaMix
        def mixed = "mixed"
      end
      class MetaBoth
        class << self
          extend MetaMix
          def self.meta = "meta"
        end
      end
      p MetaBoth.singleton_class.meta
      p MetaBoth.singleton_class.mixed
    RUBY

    _(result).must_answer <<~'OUT'
      == a meta method beside a mixin in the same singleton body
      "meta"
      "mixed"
    OUT
  end

  it "a def in a class << obj body installs on the object, and a private below it marks the singleton" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true

      # `class << obj` opens the object's singleton class, which no class row
      # can name: a singleton is minted per object at run time. So each `def`
      # in the body is installed on the object itself, and a `private` run
      # marks the methods below it on the singleton class -- which is exactly
      # how ruby spells a private singleton method.

      class Box
        class << self
          def make(v) = new(v)

          def label = "box"

          def described = "#{label}: #{secret}"

          private

          def secret = :quiet
        end

        def initialize(v)
          @v = v
        end

        attr_reader :v
      end

      p Box.make(3).v
      p Box.label
      p Box.described
      p Box.singleton_methods.sort
      p Box.respond_to?(:secret), Box.respond_to?(:secret, true)
      p Box.singleton_class.private_method_defined?(:secret)

      # A named method retagged where the verb stands, rather than a mode over
      # the lines below it.
      class Later
        class << self
          def one = 1
          def two = 2

          private :two
        end
      end

      p Later.one
      p Later.singleton_methods.sort
      p Later.respond_to?(:two), Later.respond_to?(:two, true)

      # `class << obj` on a plain object touches that object alone.
      one = Object.new
      class << one
        def only_mine = :mine
      end

      p one.only_mine
      p Object.new.respond_to?(:only_mine)
      p one.singleton_methods

      # A singleton method takes arguments and a block like any other.
      class Maker
        class << self
          def build(*parts, sep: "-")
            yield parts.join(sep)
          end
        end
      end

      p Maker.build("a", "b") { |s| s.upcase }
      p Maker.build("a", "b", sep: "+") { |s| s }
      p Maker.method(:build).arity
      # `def obj.name` is `class << obj` with one method in it: the object no
      # compile can know gets the method where the statement stands.
      plain = Object.new

      def plain.greet(who = "you") = "hi #{who}"

      # The body is a LAMBDA, so a `return` leaves the method rather than the
      # block it was built from.
      def plain.early(n)
        return :small if n < 3

        :big
      end

      p plain.greet
      p plain.greet("ada")
      p plain.early(1), plain.early(9)
      p plain.singleton_methods.sort
      p plain.method(:greet).arity
      p plain.method(:greet).parameters
      p plain.respond_to?(:greet)
      p Object.new.respond_to?(:greet)

      # The statement answers the method's name, like any other `def`.
      p(def plain.later = 1)
      p plain.later

      # A class object takes one: that is a class method by another name.
      class Boxed
        def initialize(v) = @v = v
      end

      def Boxed.of(v) = new(v)
      def Boxed.tag = :boxed

      p Boxed.of(3).class
      p Boxed.tag
      p Boxed.singleton_methods.sort

      # `def self.name` inside a block installs on whatever `self` is there,
      # which inside `Module.new` is the new module.
      Made = Module.new do
        def self.built = :made

        def instance_side = :inst
      end

      p Made.built
      p Made.instance_methods(false)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "box"
      "box: quiet"
      [:described, :label, :make]
      false
      true
      true
      1
      [:one]
      false
      true
      :mine
      false
      [:only_mine]
      "A-B"
      "a+b"
      -1
      "hi you"
      "hi ada"
      :small
      :big
      [:early, :greet]
      -1
      [[:opt, :who]]
      true
      false
      :later
      1
      Boxed
      :boxed
      [:of, :tag]
      :made
      [:instance_side]
    OUT
  end

  it "class << obj on a named object overrides its methods, with super reaching the class" do
    result = zr(<<~'RUBY')
      # `class << obj` (block form of def obj.m) on a statically-traceable object.
      class Widget
        def initialize(n)
          @n = n
        end
        def label
          "w#{@n}"
        end
      end

      W = Widget.new(1)
      class << W
        def label
          "custom-#{super}"
        end
        def extra
          "x"
        end
      end
      p W.label
      p W.extra
      p W.class
      p W.is_a?(Widget)
      p W.instance_of?(Widget)

      # local receiver
      class Thing
        def base
          "b"
        end
      end
      x = Thing.new
      class << x
        def special
          "s-#{base}"
        end
      end
      p x.special

      # constant with a body method reached from the singleton method
      class Config
        def base
          10
        end
      end
      CONFIG = Config.new
      class << CONFIG
        def reload
          "reload-#{base}"
        end
      end
      p CONFIG.reload
    RUBY

    _(result).must_answer <<~'OUT'
      "custom-w1"
      "x"
      Widget
      true
      true
      "s-b"
      "reload-10"
    OUT
  end

  it "prepending onto a singleton class puts the module's instance methods ahead of def self.x" do
    result = zr(<<~'RUBY')
      # `C.singleton_class.prepend(M)` prepends a module onto a class's SINGLETON
      # class, so M's INSTANCE methods become C's CLASS methods at higher priority
      # than C's own `def self.x` -- which they override, with `super` reaching the
      # original. For a whole-program AOT target this is a static structural fact
      # (recorded as `class_method_prepends`, the class-method mirror of `prepends`),
      # resolved through the ordinary flattened class-method tables and the singleton
      # super chain -- no runtime metaprogramming. Oracle-exact.

      # override + super reaching the original class method
      module Hook
        def greet
          "[" + super + "]"
        end
      end
      class Foo
        def self.greet
          "hi"
        end
      end
      Foo.singleton_class.prepend(Hook)
      puts Foo.greet

      # super with an argument passthrough
      module Audit
        def build(x)
          "audit(" + super + ")"
        end
      end
      class Maker
        def self.build(x)
          "made:#{x}"
        end
      end
      Maker.singleton_class.prepend(Audit)
      puts Maker.build("wheel")

      # multiple prepended modules -> a super chain across both, most-recent closest
      module M1
        def tag
          "M1[" + super + "]"
        end
      end
      module M2
        def tag
          "M2[" + super + "]"
        end
      end
      class Svc
        def self.tag
          "svc"
        end
      end
      Svc.singleton_class.prepend(M1)
      Svc.singleton_class.prepend(M2)
      puts Svc.tag

      # full override (the prepended method never calls super)
      module Force
        def mode
          "forced"
        end
      end
      class Engine
        def self.mode
          "stock"
        end
      end
      Engine.singleton_class.prepend(Force)
      puts Engine.mode

      # a NEW class method the module adds (no original to override), alongside an
      # untouched own class method
      module Extra
        def hello
          "hi from extra"
        end
      end
      class Plain
        def self.name_tag
          "plain"
        end
      end
      Plain.singleton_class.prepend(Extra)
      puts Plain.hello
      puts Plain.name_tag
    RUBY

    _(result).must_answer <<~'OUT'
      [hi]
      audit(made:wheel)
      M2[M1[svc]]
      forced
      hi from extra
      plain
    OUT
  end

  it "a singleton class's superclass is the superclass's singleton class" do
    result = zr(<<~'RUBY')
      # A singleton class's superclass is the singleton class of the superclass:
      #
      #     String.singleton_class.superclass  #=> #<Class:Object>
      #
      # zr answers `Class`, collapsing the parallel hierarchy to its base. That
      # chain is what makes class methods inherit -- `Sub.some_class_method` resolves
      # by walking `#<Class:Sub>` -> `#<Class:Base>` -> ... -> `Class` -- so a flat
      # answer describes an inheritance that is not the one actually used.
      #
      # Class-method inheritance itself already WORKS in zr (the `Sub.f` line
      # below), so the walk is right and only its reflection is wrong. Anything that
      # reasons about the chain rather than calling through it -- a library deciding
      # where to install a class method, `ancestors` on a singleton class -- reads
      # the wrong shape.

      p String.singleton_class.superclass
      p Object.singleton_class.superclass
      p BasicObject.singleton_class.superclass

      class Base; def self.f = :base_f; end
      class Sub < Base; end
      p Sub.f
      p Sub.singleton_class.superclass
      p Sub.singleton_class.ancestors.first(3)

      o = Object.new
      p o.singleton_class.superclass
    RUBY

    _(result).must_answer <<~'OUT'
      #<Class:Object>
      #<Class:BasicObject>
      Class
      :base_f
      #<Class:Base>
      [#<Class:Sub>, #<Class:Base>, #<Class:Object>]
      Object
    OUT
  end

  it "a singleton-class constant survives a reopen, reads the enclosing scope, and hides from outside" do
    result = zr(<<~'RUBY')
      # Singleton-class constants (`class << self` surrogates) beyond the promoted
      # gap shape: reopens, enclosing-scope reads, nesting depth, and the reach
      # rules from outside the singleton body.

      # The enclosing module's OWN constants stay readable from the singleton body
      # (it sits in the lexical nesting), and the singleton's shadow the module's.
      module Outer
        PLAIN = :module_const
        SHADOWED = :from_module
        class << self
          SC = :singleton_const
          SHADOWED = :from_singleton
          def both = [SC, PLAIN, SHADOWED]
        end
      end
      p Outer.both

      # A class method defined OUTSIDE the `class << self` body cannot reach the
      # singleton's constant by bare name.
      module Outer
        def self.blind
          SC
        rescue NameError
          :name_error
        end
      end
      p Outer.blind

      # A second `class << self` body reopens the SAME singleton class -- its
      # constants join the first body's.
      module Outer
        class << self
          SC2 = :second_body
          def pair = [SC, SC2]
        end
      end
      p Outer.pair
      p Outer.singleton_class.constants(false).sort

      # Nested modules: the surrogate sits inside the full lexical chain, so a
      # singleton body in `A::B` reads A's constants too.
      module A
        ROOT = :a_const
        module B
          class << self
            INNER = :inner
            def chain = [INNER, ROOT]
            def nest = Module.nesting.map(&:to_s)
          end
        end
      end
      p A::B.chain
      p A::B.nest

      # Reflection through the singleton value: the constant is reachable with
      # const_get on the singleton class, and invisible from the module itself.
      p Outer.singleton_class.const_get(:SC)
      p [Outer.const_defined?(:SC), Outer.singleton_class.const_defined?(:SC)]
    RUBY

    _(result).must_answer <<~'OUT'
      [:singleton_const, :module_const, :from_singleton]
      :name_error
      [:singleton_const, :second_body]
      [:SC, :SC2, :SHADOWED]
      [:inner, :a_const]
      ["#<Class:A::B>", "A::B", "A"]
      :singleton_const
      [false, true]
    OUT
  end

  it "a bare private does not reach a following def self.x, which stays public" do
    result = zr(<<~'RUBY')
      # A bare `private` sets the default only for subsequent INSTANCE defs; a
      # singleton def (`def self.name` / `def Recv.name`) that follows is a
      # method on another object and stays public. net/protocol's
      # `private; def Protocol.protocol_param` is this shape.

      class Proto
        private
        def Proto.cls_param; "cls_ok"; end
        def self.self_param; "self_ok"; end
        def inst; "inst"; end
      end
      puts Proto.cls_param
      puts Proto.self_param
      begin
        Proto.new.inst
      rescue NoMethodError
        puts "inst_private"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      cls_ok
      self_ok
      inst_private
    OUT
  end

  it "a singleton method belongs to the object, so an Array or a String takes one and an Integer refuses" do
    result = zr(<<~'RUBY')
      # A singleton method belongs to the OBJECT, and in Ruby that includes any heap
      # value -- csv defines `def NO_QUOTED_FIELDS.[](i)` on a bare Array.
      NO_QUOTED = []
      def NO_QUOTED.[](_index) = false
      NO_QUOTED.freeze
      p NO_QUOTED[0], NO_QUOTED[99]
      p NO_QUOTED.size, NO_QUOTED.frozen?, NO_QUOTED.respond_to?(:[])

      # It is per-OBJECT, so a sibling of the same class is untouched.
      p [].respond_to?(:shout)
      s = +"hello"
      def s.shout = upcase + "!"
      p s.shout, s.length, s.class
      p (+"hello").respond_to?(:shout)

      h = {}
      h.define_singleton_method(:fetch_or) { |k| self[k] || :none }
      p h.fetch_or(:x)
      h[:x] = 1
      p h.fetch_or(:x)
      p h.singleton_methods

      # An immediate has no identity to attach one to, which is why Ruby refuses.
      begin
        1.define_singleton_method(:nope) { }
      rescue TypeError => e
        puts e.message
      end

      # ...but nil/true/false each have exactly one instance, so their singleton
      # class IS their class and Ruby accepts it there.
      nil.define_singleton_method(:blank?) { true }
      p nil.blank?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      0
      true
      true
      false
      "HELLO!"
      5
      String
      false
      :none
      1
      [:fetch_or]
      can't define singleton
      true
    OUT
  end

  it "a module prepended into a singleton wins the lookup, and Method#owner names it bare" do
    result = zr(<<~'RUBY')
      # A module prepended into a singleton class WINS the class-method lookup, so
      # `super` inside it reaches the class's own `def self.x` and `Method#owner`
      # names the module.
      #
      # zr flattens a singleton prepend: the module's body becomes the class's
      # winning class-method row and the class's own `def self.x` becomes that
      # row's super target. Two reflection answers have to say what ruby says in
      # spite of the flattening -- `defined?(super)`, which asked the CLASS's
      # instance ancestry (`Class`, holding no `def self.x`, so always nil), and
      # `#owner`, whose scan correctly finds the host the row sits on.
      #
      # A module reached through the singleton chain is named BARE, the same rule
      # an `extend`ed module already followed: only a real `def self.x` is reported
      # as owned by a singleton class.
      module SA
        def s = "SA(#{defined?(super) ? super : 'top'})"
      end
      module SB
        def s = "SB(#{defined?(super) ? super : 'top'})"
      end

      # The call form.
      class Runtime
        def self.s = "Runtime"
      end
      Runtime.singleton_class.prepend(SB)
      p Runtime.s
      p Runtime.method(:s).owner.to_s
      p Runtime.singleton_class.instance_method(:s).owner.to_s

      # The `class << self` form.
      class Written
        def self.s = "Written"
        class << self
          prepend SB
        end
      end
      p Written.s
      p Written.method(:s).owner.to_s

      # Two modules stack, and the second prepend runs first.
      class Stacked
        def self.s = "Stacked"
      end
      Stacked.singleton_class.prepend(SA)
      Stacked.singleton_class.prepend(SB)
      p Stacked.s
      p Stacked.method(:s).owner.to_s

      # An `extend` behind the class's own definition still loses, and its owner
      # is reported bare for the same reason.
      class Mixed
        extend SA
      end
      p Mixed.s
      p Mixed.method(:s).owner.to_s

      # Nothing prepended: the owner is the singleton class itself.
      class Plain
        def self.s = "Plain"
      end
      p Plain.method(:s).owner.to_s
      p Plain.singleton_class.instance_method(:s).owner.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "SB(Runtime)"
      "SB"
      "SB"
      "SB(Written)"
      "SB"
      "SB(SA(Stacked))"
      "SB"
      "SA(top)"
      "SA"
      "#<Class:Plain>"
      "#<Class:Plain>"
    OUT
  end

  it "the same prepend works on a Class.new receiver, and a subclass sees it through the ancestor walk" do
    result = zr(<<~'RUBY')
      # `X.singleton_class.prepend(M)` where X only ever exists at RUNTIME (a
      # `Class.new` minting -- the same shape as a rails class behind a computed
      # autoload): M's instance methods become X's class methods ABOVE X's own
      # `def self.x`, and `super` from one resumes at the shadowed definition.
      # The compile-time ancestry edit cannot name X, so this exercises the runtime
      # layer (`prepend_into_class_singleton` + the prepend-aware `super` resume);
      # a statically-registered receiver still takes the compile-time edit instead.
      # The subclass call checks the prepend is visible through inheritance -- the
      # ancestor walk finds the prepend layer at the parent's position.
      K = Class.new do
        def self.hi = "orig"
      end
      module Patch
        def hi = "patched-" + super
        def extra = "extra"
      end
      K.singleton_class.prepend(Patch)
      p K.hi
      p K.extra
      p K.respond_to?(:extra)
      Sub = Class.new(K)
      p Sub.hi
    RUBY

    _(result).must_answer <<~'OUT'
      "patched-orig"
      "extra"
      true
      "patched-orig"
    OUT
  end

  it "a subclass inherits its parent's singleton prepend for dispatch as well as reflection" do
    result = zr(<<~'RUBY')
      # A module prepended into a SINGLETON class, reached from every direction a
      # subclass chain gives it.
      #
      # zr has no singleton-class objects: a class method resolves through the
      # `class_method_prepends` stack, the extend sources and the flattened
      # `class_methods` tables. Three things that model got wrong, and each needed a
      # different half of the answer.
      #
      # `defined?(super)` and the `super` WALK disagreed. The probe scanned from the
      # target's own position, which INCLUDES the module prepended into its
      # singleton, while the walk skips that layer -- it got there THROUGH it. A
      # prepended module with no row beneath it therefore reported a super target
      # and then raised looking for it. One resolution serves both now.
      #
      # A SUBCLASS did not inherit its parent's singleton prepend for DISPATCH, only
      # for reflection: `prepended_class_methods` is keyed on the class the
      # `prepend` named, and the flat probe found the parent's own `def self.x`
      # instead -- which sits BEHIND the module in ruby's chain.
      #
      # And a prepend on an ANCESTOR was unreachable by `super` from a prepend on
      # the subclass, because materialization flattens an inherited `def self.x`
      # onto every descendant's table and the walk took the nearest copy. Only the
      # OWN-set can tell a class's real definition from the copy it was given.

      module L1
        def tag = "L1(#{defined?(super) ? super : 'top'})"
      end
      module L2
        def tag = "L2(#{defined?(super) ? super : 'top'})"
      end

      # A prepend with nothing beneath it: `defined?(super)` is false, and the
      # fallback branch runs rather than raising.
      class A1
        singleton_class.prepend L1
      end
      p A1.tag

      # ... and with the host's own row beneath it.
      class A2
        def self.tag = "own"
        singleton_class.prepend L1
      end
      p A2.tag

      # A subclass inherits the prepend, at its parent's position in the chain.
      class B0
        def self.tag = "B0"
      end
      class B1 < B0; end
      class B2 < B1; end
      B0.singleton_class.prepend L1
      p [B0.tag, B1.tag, B2.tag]

      # A prepend on the SUBCLASS resumes into the one on the ancestor.
      B2.singleton_class.prepend L2
      p [B0.tag, B1.tag, B2.tag]
      p B2.singleton_class.ancestors.first(5).map(&:to_s)

      # A subclass's OWN `def self.x` still outranks an ancestor's prepend, and its
      # `super` reaches it.
      class B3 < B0
        def self.tag = "B3(#{super})"
      end
      p B3.tag
      p B3.singleton_class.ancestors.first(4).map(&:to_s)

      # An `extend` of the same module is a different layer, and the two orders
      # answer differently.
      class C1
        extend L1
      end
      p C1.tag
      class C2
        def self.tag = "own2"
        extend L1
      end
      p C2.tag

      # The walk's tail is `Class`'s own instance methods.
      class D1
        def self.to_s = "d1(" + super + ")"
      end
      p D1.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "L1(top)"
      "L1(own)"
      ["L1(B0)", "L1(B0)", "L1(B0)"]
      ["L1(B0)", "L1(B0)", "L2(L1(B0))"]
      ["L2", "#<Class:B2>", "#<Class:B1>", "L1", "#<Class:B0>"]
      "B3(L1(B0))"
      ["#<Class:B3>", "L1", "#<Class:B0>", "#<Class:Object>"]
      "L1(top)"
      "own2"
      "d1(D1)"
    OUT
  end
end
