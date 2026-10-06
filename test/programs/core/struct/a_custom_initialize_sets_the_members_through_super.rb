# A custom `initialize` in the block calls `super` (bare or explicit,
# positional) into the synthesized member-setter, reached via a two-level
# base/leaf hierarchy -- not the old "no initialize above" crash.

Trip = Struct.new(:x, :y, :z) do
  def initialize(x, y)
    super
  end
end
p Trip.new(1, 2).to_a
V = Struct.new(:a, :b, :c) do
  def initialize(a, b)
    super(a, b, a + b)
  end
end
p V.new(3, 4).to_a
