# A shared-mutable string pushed into an Array of Strings.
#
# A string that is both aliased and mutated in place goes into the Array with
# its bytes, and each element reads back as the String that went in.
#
# The Array is in an ivar, which keeps its String element type. A local
# Array can get mixed elements instead.

class Holder
  attr_accessor :items, :map

  def initialize
    @items = [""]      # type seed; a bare [] infers an IntArray
    @items.pop
    @map = { "seed" => "" }
    @map.delete("seed")
  end
end

def built(x)
  s = +""
  s << "v"
  s << x
  s
end

h = Holder.new
h.items << built("1")
puts "after <<:   " + h.items[0]
h.items.push(built("2"))
h.items.unshift(built("0"))
h.items.insert(1, built("x"))
p h.items
h.items.each { |e| puts "in each:    " + e }

h.map["k"] = built("m")
p h.map["k"]

h.items.concat([built("c")])
p h.items.last
p h.items.join(",")
p h.items.length

# the reporter's shape, verbatim in spirit
s = +""
s << "b"
s << "=2"
h2 = Holder.new
h2.items << s
puts "reporter:   " + h2.items[0]
