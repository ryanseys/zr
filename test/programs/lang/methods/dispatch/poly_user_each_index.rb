# A blockless index enumerator call on a receiver of more than one class.
# When a user class owns the name, the call runs the user method, with its
# side effects. An Array receiver still answers an Enumerator.
class Rows
  def initialize
    @seen = []
  end

  attr_reader :seen

  def each_index
    @seen.push(:ran)
    [7]
  end
end

def indices(v) = v.each_index

r = Rows.new
got = indices(r)
p r.seen
p got.to_a
got.each { |x| p x }

p indices([1, 2]).to_a
p indices(["a", "b", "c"]).to_a

class Pairs
  def each_with_index
    ["p"]
  end
end

def pairs(v) = v.each_with_index
p pairs(Pairs.new).to_a
p pairs([1, 2]).to_a

# with no user class in sight the enumerators are what they were
p [1, 2, 3].each_index.to_a
p [1, 2].each_with_index.to_a
