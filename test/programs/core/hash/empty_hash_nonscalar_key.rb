# A bare `{}` takes its key type from the KEY it gets. Here the key is not a
# Symbol, a String or an Integer, but an Array.
#
# The key is an EMPTY array, which is the harder case: it has no element to
# give it an element type.
p(
  [].each do
    {}.fetch [], 0
  end
)

class T
  def arr_key
    {}.fetch([1, 2], 0)
  end

  def empty_arr_key
    {}.fetch([], 0)
  end

  def empty_hash_key
    {}.fetch({}, 0)
  end

  def float_key
    {}.fetch(1.5, 0)
  end

  def nil_key
    {}.fetch(nil, 0)
  end

  def obj_key
    {}.fetch(Object.new, 0)
  end
end

t = T.new
p t.arr_key
p t.empty_arr_key
p t.empty_hash_key
p t.float_key
p t.nil_key
p t.obj_key

# and the widened variant really holds those keys, not just compiles
h = {}
h[[1, 2]] = "pair"
h[1.5] = "float"
h[nil] = "nil"
p h[[1, 2]]
p h[1.5]
p h[nil]
p h.fetch([9], "miss")
p h.key?([1, 2])
p h.dig([1, 2])
p h.size
