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
