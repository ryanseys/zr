# `self.class.<class method>` from an instance method dispatches on the runtime
# class. Three cases: the base class's own copy still runs when a subclass
# has its own; a class method can return a Symbol; and a class method can
# return a class-level ivar that can be nil.
class Base
  def self.key(k = nil)
    @key = k if k
    @key
  end
  def key_from_instance = self.class.key
end
class A < Base; end

A.key :a
p A.key
p A.new.key_from_instance
p Base.new.key_from_instance

# `class << self` reaches the same dispatch.
class Ring
  class << self
    def slot(v = nil)
      @slot = v if v
      @slot
    end
  end
  def slot_from_instance = self.class.slot
end
class Ring2 < Ring; end
Ring.slot :outer
Ring2.slot :inner
p Ring.new.slot_from_instance
p Ring2.new.slot_from_instance

# Arms that disagree on return type unify to poly, and each arm boxes its own.
class Tag
  def self.label = :base
  def label_from_instance = self.class.label
end
class Tag2 < Tag
  def self.label = "sub"
end
p Tag.new.label_from_instance
p Tag2.new.label_from_instance

# Arms that agree on a non-poly scalar stay that type.
class Kind
  def self.kind = :one
  def kind_of_self = self.class.kind
end
class Kind2 < Kind
  def self.kind = :two
end
p Kind.new.kind_of_self
p Kind2.new.kind_of_self
