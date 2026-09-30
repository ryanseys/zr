# An empty array literal returned from a method through a LOCAL variable keeps
# its container type: it is an Array, not a String. In the caller, `<<` pushes
# a Float or an object as an Array element.
#
# Returning the very same literal directly (`def make_direct; []; end`) gives
# the same Array.

def make
  a = []
  a
end

xs = make
xs << 1.5
p xs
p xs.length

def make_direct
  []
end

ys = make_direct
ys << 1.5
p ys

# push instead of << also stayed correct: only << is ambiguous between Array
# and String, so only << followed the mistyped literal.
def make_push
  a = []
  a
end

zs = make_push
zs.push(1.5)
p zs

# The shape this was found in: a generic top-K helper whose result is assigned
# back over its argument, with the accumulator seeded from a bare [].
class Item
  attr_reader :score
  def initialize(s)
    @score = s
  end
end

def top1(kept)
  trimmed = []
  trimmed << kept[0]
  trimmed
end

items = []
items << Item.new(3.0)
items << Item.new(1.0)
items = top1(items)
p items.length
p items[0].score

# The other side: when the caller's slot really is a
# String, mutating the result of a method whose tail is a local still has to
# pull that local into the shared-handle set, so the mutation lands on the one
# buffer and aliases of it see the change.
def make_held
  s = +"x"
  s << "y"
  s
end

r = make_held
r << "z"
p r

def mk2
  a = +"p"
  a
end

q = mk2
q2 = q
q << "!"
p q
p q2
p q.equal?(q2)
