# A module ivar initialized to an empty hash literal (`@slots = {}`)
# gets its key and value types from the writes in the module's class
# methods: here Symbol keys and String values. Same idea for arrays
# via `@<iname> << v` / `@<iname>.push(v)`.

module M
  @slots = {}

  def self.set(k, v)
    @slots[k] = v
    nil
  end

  def self.get(k)
    @slots[k] || ""
  end

  def self.size
    @slots.length
  end
end

M.set(:foo, "bar")
M.set(:baz, "qux")
puts M.get(:foo)         # bar
puts M.get(:baz)         # qux
puts M.get(:missing)     # (empty default)
puts M.size              # 2

# Empty array literal — same refinement applies via `<<` writes.
module N
  @items = []

  def self.add(s)
    @items << s
  end

  def self.read(i)
    @items[i]
  end

  def self.size
    @items.length
  end
end

N.add("alpha")
N.add("beta")
N.add("gamma")
puts N.size              # 3
puts N.read(0)           # alpha
puts N.read(2)           # gamma
