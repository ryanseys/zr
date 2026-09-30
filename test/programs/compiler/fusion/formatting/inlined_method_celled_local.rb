# A method local captured by a block is reached through a heap cell. Here the
# method is INLINED at its call site -- which a `yield` in it forces -- and
# the inlined body reads and writes the same local as the block does.
#
# The same local seen from the other side: in another example the block
# becomes a function of its own, here the callee is folded into the caller.

# `each` on a user class that defines #each without #to_a -- the ordinary way
# to write one, forwarding the block -- runs that #each, and the sum is 7 as in
# CRuby. A class that answers #to_a gets the same result.

class Bag
  def initialize(a) = @a = a
  def each(&b) = @a.each(&b)
end

class Yielder
  def initialize(a) = @a = a
  def each
    @a.each { |x| yield x }
  end
end

class WithToA
  def initialize(a) = @a = a
  def to_a = @a
  def each(&b) = @a.each(&b)
end

module M
  def self.sum_of(list)
    n = 0
    list.each { |x| n += yield x }
    n
  end
end

def run(list) = M.sum_of(list) { |x| x }
puts run([1, 2])
puts run([3, 4, 5])

# captured locals that are not Integers
module F
  def self.join_of(list)
    s = ""
    list.each { |x| s += (yield x).to_s }
    s
  end

  def self.total_of(list)
    f = 0.0
    list.each { |x| f += (yield x) }
    f
  end

  def self.gather(list)
    a = []
    list.each { |x| a.push(yield x) }
    a
  end
end

def joined(list) = F.join_of(list) { |x| x }
def totalled(list) = F.total_of(list) { |x| x * 1.0 }
def gathered(list) = F.gather(list) { |x| x }
p joined([1, 2])
p totalled([1, 2])
p gathered([1, 2])

# a closure over the celled local outlives the loop
module K
  def self.keep(list)
    seen = []
    list.each { |x| seen.push(yield x) }
    seen.length
  end
end
def kept(list) = K.keep(list) { |x| x }
p kept([1, 2, 3])

p run(Bag.new([3, 4]))
p run(Yielder.new([5, 6]))
p run(WithToA.new([7, 8]))
p kept(Bag.new([1, 2, 3]))

# not inlined, which has always worked: the same answers
def walk(list)
  t = 0
  list.each { |x| t += x }
  t
end
p walk([1, 2])
p walk(Bag.new([3, 4]))
p walk(Yielder.new([5, 6]))

# a class with no each at all still walks as a container where it is one
p run([9])
