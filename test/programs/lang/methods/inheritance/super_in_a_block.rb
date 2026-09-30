# frozen_string_literal: true

# `super` resumes the MRO walk above the class the `def` was WRITTEN in.
# A block has no method of its own, so a `super` in one belongs to the
# method that wrote the block -- and a class method walks the singleton
# chain instead.

class Base
  def greet(a, b = 2) = "base #{a} #{b}"
  def with_block = "base #{yield 5}"
  def self.make(x) = "base make #{x}"
  def channels(*xs, **k) = "base #{xs} #{k}"
end

class Child < Base
  # A bare `super` sends the parameters by their CURRENT values, which
  # the block has to carry even though it names none of them.
  def greet(a, b = 2)
    a = a.upcase
    [1].map { [1].map { super } }.flatten.first
  end

  # The block a bare `super` forwards is the enclosing method's, the
  # same channel a bare `yield` written there reads.
  def with_block
    [1].map { super }.first
  end

  def self.make(x)
    [1].map { super }.first
  end

  # Every argument channel, forwarded by a bare `super`.
  def channels(*xs, **k) = super
end

p Child.new.greet("q")
p Child.new.with_block { |n| n * 3 }
p Child.make(4)
p Child.new.channels(1, 2, a: 3)

# An inherited class method keeps walking from where it was written.
class Grand < Child; end
p Grand.make(9)

# A lambda is a block too.
class Lam < Base
  def greet(a, b = 2)
    l = -> { super }
    l.call
  end
end
p Lam.new.greet("l")

# A block written AT the `super` replaces the one that would forward.
class Blocky < Base
  def with_block
    [1].map { super { |n| n + 100 } }.first
  end
end
p Blocky.new.with_block

# The anonymous channels forward by the names ruby gives them.
class Anon < Base
  def channels(*, **) = super
end
p Anon.new.channels(6, z: 7)

# A `class << self` body writes the same singleton row a `def self.x` does.
class Singly < Base
  class << self
    def make(x) = super
  end
end
p Singly.make(8)
