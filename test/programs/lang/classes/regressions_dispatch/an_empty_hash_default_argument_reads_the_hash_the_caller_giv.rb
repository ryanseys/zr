# A parameter with an empty Hash default, `def m(h = {})`, reads the
# Hash that the caller gives, with Symbol keys or String keys.

class T_issue176_empty_hash_default_A
  def initialize(attrs = {})
    @x = attrs[:x]
  end
  def x; @x; end
end

puts T_issue176_empty_hash_default_A.new({x: 42}).x

class T_issue176_empty_hash_default_B
  def initialize(attrs = {})
    @name = attrs[:name]
  end
  def name; @name; end
end

puts T_issue176_empty_hash_default_B.new({name: "alice"}).name

# String-keyed hash also works.
class T_issue176_empty_hash_default_C
  def initialize(attrs = {})
    @v = attrs["v"]
  end
  def v; @v; end
end

puts T_issue176_empty_hash_default_C.new({"v" => 7}).v
