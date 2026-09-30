# A redefined initialize of a Data class gets keywords, also from
# values by position, and can give defaults; a subclass keeps it.
D = Data.define(:x, :y) do
  def initialize(x:, y: 0)
    super
  end
end
p D.new(1)
p D.new(x: 2)
p D.new(1, 2)
class E < D
  def initialize(x:, y: 9)
    super(x: x * 10, y: y)
  end
end
p E.new(1)
p E.new(x: 2, y: 3)
p E.new(1).frozen?
F = Data.define(:a)
class G < F; end
p G.new(4)
p G.new(a: 5).a
p G.new(4) == F.new(4)
