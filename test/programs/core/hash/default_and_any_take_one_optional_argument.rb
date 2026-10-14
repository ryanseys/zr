# Hash#default and Hash#any? take at most one argument; Enumerable's
# all?, none? and one? and their pattern forms too.
def show
  p yield
rescue ArgumentError => e
  p [e.class, e.message]
end

h = Hash.new { |hash, key| "made #{key}" }
h[:a] = 1
show { h.default }
show { h.default(:x) }
show { h.default(1, 2) }
show { Hash.new(5).default(:x) }
show { {}.any? }
show { h.any? }
show { h.any?([:a, 1]) }
show { h.any? { |k, v| v > 0 } }
show { h.any?(1, 2) }
show { h.any?(Array) { true } }

[[1, nil, 3], (1..3), { a: 1 }].each do |list|
  show { [list.all?, list.none?, list.one?, list.any?] }
  show { [list.all?(Integer), list.none?(String), list.one?(1), list.any?(3)] }
  show { [list.all? { |x| x }, list.none? { |x| x.nil? }, list.one? { |x| x }] }
  show { list.all?(1, 2) }
  show { list.none?(1, 2) }
  show { list.one?(1, 2) }
end
