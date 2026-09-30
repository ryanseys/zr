# A redefined initialize runs, with or without super, in a subclass of
# a subclass too, and a redefined `new` runs in place of Class#new.
P = Struct.new(:a, :b)
class Q < P
  def initialize(a)
    super(a, a * 2)
  end
end
class R < Q
  def initialize
    super(5)
  end
end
p Q.new(3).to_a
p R.new.to_a
p R.new == Q.new(5)
p R.new.b
N = Struct.new(:x) do
  def initialize(*) = nil
end
p N.new(1).x
M = Struct.new(:x) do
  def self.new(*args) = "new #{args.inspect}"
end
p M.new(1)
S = Struct.new(:x, :y)
class S
  def initialize(x, y = x) = super
end
p S.new(1).to_a
s = S.new(1, 2)
s.y = 9
p [s.x, s.y, s[1], s.to_a]
s.freeze
begin
  s.x = 3
rescue FrozenError => e
  p e.class
end
