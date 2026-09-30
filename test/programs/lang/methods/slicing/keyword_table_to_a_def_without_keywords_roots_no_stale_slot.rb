# Literal keywords reach a def that declares none as one Hash, made
# before the arity check fills the required parameters' slots: the
# collector must not read what an earlier frame left in them.
def fill(a, b) = [a, b]
def take(first, opts = nil) = [first, opts]

last = nil
2000.times do |i|
  fill(Object.new, Object.new)
  last = take("x", k: i)
end
p last

