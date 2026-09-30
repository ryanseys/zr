# Data.new by position and by keyword, the errors for a missing, an
# extra or an unknown value, and a frozen result.
D = Data.define(:x, :y)
p D.new(1, 2)
p D.new(x: 1, y: 2)
p D[3, 4]
p D.new(y: 2, x: 1) == D.new(1, 2)
p D.new(1, 2).frozen?
begin
  D.new(1)
rescue ArgumentError => e
  p e.message
end
begin
  D.new(1, 2, 3)
rescue ArgumentError => e
  p e.message
end
begin
  D.new(x: 1)
rescue ArgumentError => e
  p e.message
end
begin
  D.new(x: 1, y: 2, z: 3)
rescue ArgumentError => e
  p e.message
end
begin
  D.new(1, y: 2)
rescue ArgumentError => e
  p e.message
end
begin
  D.new(1, 2).instance_variable_set(:@z, 1)
rescue FrozenError => e
  p e.class
end
E = Data.define
p E.new
h = { x: 5, y: 6 }
p D.new(**h)
p D.new(1, 2).with(y: 7)
