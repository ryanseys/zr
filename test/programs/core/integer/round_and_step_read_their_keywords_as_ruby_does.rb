# int_round reads no keyword without digits; with digits, an unknown
# keyword raises before the rounding mode is read. num_step takes up to
# two positional arguments and the to: and by: keywords.
def show
  p yield
rescue ArgumentError, TypeError => e
  p [e.class, e.message]
end

show { 15.round }
show { 15.round(foo: 1) }
show { 15.round(-1) }
show { 15.round(-1, half: :even) }
show { 25.round(-1, half: :down) }
show { 15.round(-1, half: :bad, foo: 1) }
show { 15.round(-1, foo: 1, bar: 2) }
show { 15.round(-1, half: :bad) }
show { 15.round(1, 2) }
show { 15.round("x", foo: 1) }
show { 15.round(1) }

steps = []
1.step(7, 3) { |i| steps << i }
1.step(3) { |i| steps << i }
10.step(4, -2) { |i| steps << i }
1.step(by: 2, to: 6) { |i| steps << i }
1.step(2, 0.5) { |i| steps << i }
p steps
show { 1.step(1, 2, 3) }
show { 1.step(3, by: 1, foo: 2) {} }
show { 1.step(foo: 2) }
show { 1.step(by: 2, to: 5) }
show { 1.step(5, 2) }
show { 1.step(5, 2).to_a }
show { 1.step(5).first(2) }
show { 1.step(5, 0) {} }
show { 1.step(5, nil) {} }
show { 1.step(5, to: 6) }
show { 1.step(5, 2, by: 1) }
show { 1.step(3, by: 0) {} }
