# A lambda literal nested inside a stored (escaping) block works like any
# other escaping closure.

makers = [1, 2, 3].map do |n|
  -> { n * 10 }
end
p makers.map(&:call)

def build
  total = 0
  adder = ->(x) { total += x }
  [adder, -> { total }]
end
add, get = build
add.call(5)
add.call(7)
p get.call

squares = (1..3).map { |i| -> { i * i } }
p squares.map(&:call)
