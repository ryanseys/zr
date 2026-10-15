# The C that rounds a Float with a half mode, and that divides by a
# Complex, keeps the sign of a zero: a negative value that rounds to zero
# is -0.0, and an exact 0 part added to -0.0 leaves -0.0.
[-0.04, -0.4, -0.0004, 0.04, -0.06, -0.05].each do |v|
  p [v, v.round(1, half: :even), v.round(1, half: :down), v.round(1, half: :up), v.round(1), v.round(3, half: :even)]
end
p (-0.4).round(half: :even), (-0.4).round(half: :down)

p (-0.0) / Complex(0, 1.5), 0.0 / Complex(0, -1.5), -0.0 / Complex(1, 0)
p Complex(-0.0, 0.0) / Complex(0, 2.0), Complex(-0.0, -0.0) / Complex(2.0, 0)
p (-0.0) / 123.456 / ((-1.5)**0.5)
p Complex(3, 4) / Complex(1, 2), Complex(1r, 2) / Complex(3, 0), Complex(0, 1) / Complex(0, 0.5)
