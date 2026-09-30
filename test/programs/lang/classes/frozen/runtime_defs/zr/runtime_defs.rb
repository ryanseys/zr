# frozen_string_literal: true

# A `def` the declaration pass does not reach has no row: which class it
# lands on is not known until the statement runs. The body becomes a
# lambda-shaped Proc and the runtime installs it on the definee that is
# open, exactly as the interpreter resolves one.

M = Module.new do
  def greet = "hi"

  def twice(n) = n * 2

  def each_twice
    yield 1
    yield 2
  end

  def kw(a, *rest, b: 2, &blk) = [a, b, rest, blk.nil?]

  def early(n)
    return :small if n < 3

    :big
  end

  def counted
    total = 0
    [1, 2, 3].each { |n| total += n }
    total
  end

  def boom = raise(ArgumentError, "from a runtime def")

  private

  def hidden = :hidden
end

o = Object.new
o.extend(M)
p o.greet, o.twice(3), o.early(1), o.early(9), o.counted
p M.instance_methods(false).sort
p M.private_instance_methods(false).sort
p M.instance_method(:kw).parameters
p M.instance_method(:kw).arity
p M.instance_method(:greet).owner == M

out = []
o.each_twice { |n| out << n }
p out
p o.kw(1)
p o.kw(1, 5, b: 9)

begin
  o.kw
rescue ArgumentError => e
  p e.message
end

begin
  o.boom
rescue ArgumentError => e
  p e.message, e.backtrace.first
end

# A method body is its own scope: the name around it is invisible.
outside = 41

N = Module.new do
  def sees_nothing
    outside
  rescue NameError => e
    e.class.name
  end
end

p outside
p Object.new.extend(N).sees_nothing

# `Class.new` opens a class definee, so an `initialize` written here is
# the new class's, private as ruby makes every `initialize`.
C = Class.new do
  def initialize(v)
    @v = v
  end

  def value = @v
end

p C.new(7).value
p C.instance_methods(false).sort
p C.private_instance_methods(false).sort

# An `if` is a statement like any other, so the `def` inside one is
# installed when the branch runs -- on Object at the top level, privately,
# and on the class inside a class body.
if true
  def gated = "gated"
end
p gated, self.class.private_method_defined?(:gated)

class Host
  if true
    def inner = "inner"
  end
end
p Host.new.inner
p Host.private_method_defined?(:inner), Host.public_method_defined?(:inner)

# A `def` inside a `def` installs on the same class, when the outer one
# runs and not before.
class Outer
  def make
    def made = "made"
    :ok
  end
end
p Outer.method_defined?(:made)
p Outer.new.make, Outer.new.made
