# The shapes branch and method coverage have to name. Every branch kind
# CRuby records one for is here, and so are the two it records none for
# (`||`, `&&`) and the method rows it leaves out (an attr, a def a branch
# never ran).
def cov_ladder(n)
  if n > 10
    :big
  elsif n > 5
    :mid
  else
    :small
  end
end

def cov_unless(n)
  :none unless n
end

def cov_ternary(n) = n.even? ? :even : :odd

def cov_when(n)
  case n
  when 1 then :one
  when 2 then :two
  else :other
  end
end

def cov_in(v)
  case v
  in Integer then :int
  in String then :str
  end
end

def cov_while(n)
  while n.positive?
    n -= 1
  end
  n
end

def cov_until(n)
  n += 1 until n >= 2
  n
end

def cov_safe(v) = v&.to_s

# Neither `||` nor `&&` is a branch to CRuby.
def cov_ops(a, b) = (a || b) && a

def cov_uncalled = :never

class CovShapes
  def instance_one = 1
  def self.singleton_one = 2
  define_method(:defined_one) { 3 }
  attr_reader :not_a_method
end

module CovMixin
  def mixed_one = 4
end

if CovShapes.name.empty?
  def cov_unreachable = :no
end
