# A user method `def []=(key, value)` that dispatches on `key` and
# assigns into ivars of mixed types (Integer #@id, String @name).
# The call `f[:id] = 42` runs the user method, also when it is
# inherited.
#
# Coverage:
#   - Mixed-type ivars (`@id` int, `@name` string) — the
#     canonical Rails-fixture shape from the issue's repro.
#   - Homogeneous-type ivars to verify the dispatch still
#     works through the simpler typed-param path.

class Foo
  attr_reader :id, :name
  def initialize
    @id = 0
    @name = ""
  end
  def []=(key, value)
    case key
    when :id
      @id = value
    when :name
      @name = value
    end
  end
end

f = Foo.new
f[:id] = 42
f[:name] = "alice"
puts f.id.to_s              # 42
puts f.name                 # alice

class Bag
  attr_reader :a, :b
  def initialize
    @a = 0
    @b = 0
  end
  def []=(key, value)
    case key
    when :a
      @a = value
    when :b
      @b = value
    end
  end
end

bg = Bag.new
bg[:a] = 7
bg[:b] = 11
puts (bg.a + bg.b).to_s     # 18

