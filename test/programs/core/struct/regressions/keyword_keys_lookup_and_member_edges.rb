# Struct and Data keyword init, lookup and conversion edges that answer
# as ruby's do (rb_struct_pos and friends).
def t
  p yield
rescue => e
  p [e.class, e.message]
end

Named = Struct.new(:a, :b, keyword_init: true)
Plain = Struct.new(:a, :b)
Point = Data.define(:x, :y)
Empty = Data.define

# A keyword_init Struct takes String keys by name and Integer or Float
# keys by position; the last of two keys for a member wins.
t { Named.new("a" => 1, "b" => 2) }
t { Named.new(1 => 2) }
t { Named.new(-1 => 2, 0 => 1) }
t { Named.new(1.0 => 3) }
t { Named.new(5 => 1) }
t { Named.new(z: 1, w: 2, z: 3) }
t { Named.new(*[1], a: 1) }
t { Named.new(nil => 1) }

# A plain Struct given only keywords reads them the same way.
t { Plain.new(a: 1, "b" => 2) }
t { Plain.new(0 => 9) }

# dig, deconstruct_keys and [] take the same keys.
s = Plain.new(10, 20)
t { [s.dig(1.0), s.dig(0), s.dig(5), s.dig(:a)] }
t { s.deconstruct_keys(["a", 0, :b]) }
t { s[nil] }
t { Point.new(x: 1, y: 2).deconstruct_keys(["x"]) }
t { Point.new(x: 1, y: 2).deconstruct_keys([0]) }

# A Data with no members takes no keywords.
t { Empty.new(z: 1) }
t { Empty.new(*[], z: 1) }
t { Empty.new }

# to_h with a block names a bad pair as Hash#to_h does.
t { s.to_h { 1 } }
t { Point.new(x: 1, y: 2).to_h { 1 } }

# A Data subclass's new passes its block to initialize.
class Sized < Data.define(:x, :y)
  def initialize(x:, y: nil)
    super(x: x, y: y || (block_given? ? yield : 0))
  end

  def self.make(x, &) = new(x: x, &)
end
t { Sized.make(1) { 9 } }
t { Sized.make(1) }
