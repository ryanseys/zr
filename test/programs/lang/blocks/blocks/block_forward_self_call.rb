# Self-call `m { ... }` &block forwarding (Site A).
#
# When a method on class C calls another method on the same class
# without an explicit receiver (`m { ... }` instead of `self.m { ... }`)
# -- call this Site A -- the literal block at the call site reaches
# the callee.

# 1. Bare self-call dispatch — one method invokes another method
#    of the same class with a literal block.
class Caller
  def kick
    inner { puts "1-self-call" }
  end

  def inner(&block)
    block.call
  end
end

Caller.new.kick

# 2. Self-call passes a value through to the block via block.call(arg).
class Wrapper
  def go
    forward(7) { |i| puts "2-arg=#{i}" }
  end

  def forward(n, &block)
    block.call(n)
  end
end

Wrapper.new.go

# 3. Self-call inside a loop — each iteration forwards a fresh block.
class Bank
  def run
    deposit_each(3) { |i| puts "3-dollar-#{i}" }
  end

  def deposit_each(n, &block)
    i = 0
    while i < n
      block.call(i)
      i = i + 1
    end
  end
end

Bank.new.run

puts "done"
