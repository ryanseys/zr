# A user class that owns `merge` does not hide Hash#merge: a Hash that arrives
# at the same call still runs Hash#merge. This is also true when the user
# method's parameter is a different kind of hash.
class Flash
  def merge(other)
    other.size
  end
end

def pick(f) = f ? {a: 1} : Flash.new

p pick(true).merge(b: 2)
p pick(true).merge({b: 2})
p pick(false).merge({"x" => "y"})
p pick(true).merge({a: 9})
p pick(true).merge(b: 2, c: 3)

# a hash whose keys are not symbols, through the same dispatch
def pick2(f) = f ? {"a" => 1} : Flash.new
p pick2(true).merge({"b" => 2})

# and the ordinary typed receivers, unchanged
p({a: 1}.merge(b: 2))
p({"a" => 1}.merge({"b" => 2}))
p Flash.new.merge({"a" => "b"})
