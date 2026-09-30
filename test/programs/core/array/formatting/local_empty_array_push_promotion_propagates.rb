# A local starts as `[]` and then gets objects with `<<`. The object
# element type must also reach (a) an ivar set from the local, and
# (b) the method result when the local is the implicit return value.

class Item
  attr_accessor :id, :name
  def initialize
    @id = 0
    @name = ""
  end
end

# (a) ivar = local with push promotion.
class Holder
  def initialize
    @items = nil
  end

  def build
    results = []
    a = Item.new
    a.id = 1
    a.name = "first"
    results << a
    b = Item.new
    b.id = 2
    b.name = "second"
    results << b
    @items = results
  end

  def first_name
    @items[0].name
  end
end

h = Holder.new
h.build
puts h.first_name

# (b) method returns the local-pushed-into.
def collect_items
  results = []
  i = 0
  while i < 3
    item = Item.new
    item.id = i
    item.name = "item_" + i.to_s
    results << item
    i = i + 1
  end
  results
end

items = collect_items
puts items.length
puts items[1].name
