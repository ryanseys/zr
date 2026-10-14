# Forwarding with no arguments: each def only spreads its `*rest` and
# `**rest` on, so an empty one needs no new Array or Hash.
class Inner
  def call(*args, **opts) = args.size + opts.size + 1
end

class Outer
  def initialize = @inner = Inner.new
  def call(*args, **opts) = @inner.call(*args, **opts)
end

class Base
  def run(*args, **opts) = args.size + opts.size
end

class Child < Base
  def run(*args, **opts) = super
end

outer = Outer.new
child = Child.new
sum = 0
i = 0
while i < 5_000_000
  sum += outer.call
  sum += child.run
  sum += outer.call(i) if (i & 1023).zero?
  i += 1
end
puts sum
