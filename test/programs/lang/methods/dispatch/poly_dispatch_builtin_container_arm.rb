# A call that can reach a builtin container or a user class that shadows the
# same method name. The non-yielding reads (first, last, keys, values) on a
# genuine Array or Hash run the builtin method. The yielding ones (map,
# select) run the block, and its writes to enclosing locals are kept.
class Shadow
  def first; nil; end
  def last; nil; end
  def keys; nil; end
  def values; nil; end
  def map; nil; end
  def select; nil; end
  def size; nil; end
  def length; nil; end
  def each; nil; end
end
class Src
  def self.hash_of(w)
    if w
      h = {}
      h["a"] = 1
      h
    else
      Shadow.new
    end
  end
  def self.arr(w)
    w ? [3, 1, 2] : Shadow.new
  end
end
a = Src.arr(true)
h = Src.hash_of(true)
p a.first
p a.last
p h.keys
p h.values
n = 0
a.map { |x| n = n + 1 }
p n
m = 0
a.select { |x| m = m + 1; x > 1 }
p m
p a.size
p a.length
p h.size
e = 0
a.each { |x| e = e + 1 }
p e
p a.map { |x| x * 2 }
p a.select { |x| x > 1 }
s = Src.arr(false)
p s.first
p s.map

# The reads the general mechanism reaches once a user class owns the name:
# analyze widens the union to poly and the dispatch's builtin arm re-enters the
# ordinary emission, so the builtin receiver answers exactly as it would with
# no user class in the program.
class Shadow2
  def min; :S; end
  def max; :S; end
  def sum; :S; end
  def sort; :S; end
  def reverse; :S; end
  def index(x); :S; end
end
class Src2
  def self.arr(w) = w ? [3, 1, 2] : Shadow2.new
end
b = Src2.arr(true)
p b.min
p b.max
p b.sum
p b.sort
p b.reverse
p b.index(1)
p Src2.arr(false).min
