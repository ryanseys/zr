# frozen_string_literal: true

# A superclass is a NAME, written as a bare constant or as a path. zr
# resolves it outward from the class the statement is written in, the way
# ruby resolves any constant, and hands the backend the fully-qualified
# name it will assign an id to.

module Outer
  class Base
    def kind = "base"
  end

  class Mid < Base
    def kind = "mid/#{super}"
  end
end

class Leaf < Outer::Mid
  def kind = "leaf/#{super}"
end

module Outer
  # `Mid` here names `Outer::Mid`, not a top-level `Mid`.
  class Deep < Mid
    def kind = "deep/#{super}"
  end
end

p Leaf.new.kind
p Outer::Deep.new.kind
p Leaf.superclass.to_s, Outer::Deep.superclass.to_s
p Leaf.ancestors.take(4).map(&:to_s)
p Outer::Mid.name, Outer::Deep.name

# A class method is INHERITED: the runtime's class-method table walks no
# ancestry, so the compile copies each one onto every subclass that does
# not shadow it.
class Trunk
  def self.tag = :trunk
  def self.shared = :from_trunk
end

class Branch < Trunk
  def self.tag = :branch
end

class Twig < Branch
end

p Trunk.tag, Branch.tag, Twig.tag
p Trunk.shared, Branch.shared, Twig.shared
p Twig.singleton_methods.sort
p Twig.singleton_methods(false)
p Twig.respond_to?(:tag)
p Twig.method(:tag).owner

# Each copy carries its own class, so a class-level `@x` stays where it
# is read rather than pooling on the class that wrote the method.
class Register
  def self.seen = @seen ||= []
  def self.note(v) = seen << v
end

class RegisterA < Register; end
class RegisterB < Register; end

RegisterA.note(1)
RegisterB.note(2)
p RegisterA.seen, RegisterB.seen, Register.seen

# `BasicObject` is the root below the root: a class naming it inherits
# neither Object's methods nor Kernel's, which is the whole point of
# writing it.
class Bare < BasicObject
  def two = 2
end

p Bare.superclass.to_s
p Bare.ancestors.map(&:to_s)
p Bare.new.two
p Bare.instance_methods(false)
Bare.new.respond_to?(:to_s)
