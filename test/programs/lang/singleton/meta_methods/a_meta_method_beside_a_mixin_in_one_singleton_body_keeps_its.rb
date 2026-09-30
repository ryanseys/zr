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
