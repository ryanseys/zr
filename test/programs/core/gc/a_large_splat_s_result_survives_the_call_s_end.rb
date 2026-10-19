# A call with a splat stages its arguments on the task's spread stack and
# gives the stack back when the call returns. A splat of more than 64
# arguments grew the stack's Array, and the give back made a new one, so
# a collection could run there and free the value that the call had just
# returned. Each result here is read after collections.
NAMES = (1..200).map { |i| :"m#{i}" }
names = NAMES

def rest(*a) = a

[8, 64, 65, 200].each do |n|
  kept = rest(*names.first(n))
  GC.start
  p [n, kept.size, kept.first, kept.last]
end

# The result as an argument of the next call, and as a block's value.
p rest(*rest(*names)).size
p [1].map { rest(*names) }.first.size

# A module body's last value, as the last statement of fileutils.rb.
module Many
  NAMES.each { |m| define_singleton_method(m) {} }
  class << self
    p public(*Many.singleton_methods.sort).size
  end
end

def forward(...) = rest(...)
p forward(*names).size
GC.start
p :done
