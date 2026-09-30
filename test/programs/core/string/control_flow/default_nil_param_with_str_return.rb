# A method with `default = nil` whose body also returns a String from
# another path. `return default` gives nil or the String that the
# caller passed.

class Bag
  def initialize
    @data = {}
    @data["a"] = "alpha"
  end

  def fetch(key, default = nil)
    return @data[key] if @data.key?(key)
    default
  end
end

b = Bag.new
puts b.fetch("a")
puts b.fetch("missing").nil?

# Top-level method variant.
def lookup(map, key, default = nil)
  return map[key] if map.key?(key)
  default
end

m = { "x" => "ex" }
puts lookup(m, "x")
puts lookup(m, "z").nil?
