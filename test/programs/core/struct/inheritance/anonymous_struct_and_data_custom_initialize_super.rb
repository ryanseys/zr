# A `super` inside a method defined in a NON-const `Struct.new` or
# `Data.define` block calls the built-in `initialize` that binds the members.
# The example checks bare (zsuper) and explicit positional forms, and the
# keyword form for Data.

pair = Struct.new(:x, :y) do
  def initialize(x)
    super(x, x * 2)
  end
end
p pair.new(5).to_a

echo = Struct.new(:a, :b) do
  def initialize(a, b)
    super
  end
end
p echo.new(1, 2).to_a

coord = Data.define(:lat, :lng) do
  def initialize(lat:, lng:)
    super(lat: lat * 10, lng: lng)
  end
end
p coord.new(lat: 1, lng: 2)
