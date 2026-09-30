# frozen_string_literal: true

# `return` written in a block leaves the METHOD, not the block. The
# value travels as a signal aimed at the activation the proc holds; the
# method's boundary folds it, and a dead activation answers
# LocalJumpError.

def first_over(list, limit)
  list.each { |n| return n if n > limit }
  :none
end

p first_over([1, 2, 3, 4], 2), first_over([1, 2], 9)

# The signal names ONE activation, so the return lands in the frame that
# wrote it rather than in whichever frame catches first.
def countdown(n)
  return :floor if n.zero?

  [n].each do |x|
    reached = countdown(x - 1)
    return "#{reached}/#{n}" if n == 1
  end
  :walked
end
p countdown(3), countdown(1)

# Two blocks deep, and through a method that only relays the proc.
def relay(&block) = run(block)
def run(block) = [block.call, :unreached]

def through
  relay { return :through }
  :no
end
p through

def deep
  [[1, 2], [3, 4]].each do |pair|
    pair.each { |n| return n if n > 2 }
  end
  :none
end
p deep

# A proc that outlives the method it was written in has nowhere to
# return to.
def escaped = proc { return :nowhere }

begin
  escaped.call
rescue LocalJumpError => e
  p e.class
end

# A lambda catches its own `return` and its own `break`: both are the
# lambda's value, and the method around it carries on.
def lambdas
  answer = -> (n) { return n * 2 }
  broken = -> (n) { break n + 1 }
  [answer.call(4), broken.call(4), :carried_on]
end
p lambdas

# `return` with no value is nil, and the value is read before `$!`
# unwinds.
def bare
  [1].each { return }
  :no
end
p bare

def rescued
  [1].each do |_|
    raise ArgumentError, "held"
  rescue ArgumentError
    return $!.message
  end
end
p rescued

# A block that returns is still an ordinary block everywhere else.
def mixed(list)
  seen = list.map do |n|
    next :skip if n == 2
    return :big if n > 3

    n
  end
  [:finished, seen]
end
p mixed([1, 2, 3]), mixed([1, 4])
