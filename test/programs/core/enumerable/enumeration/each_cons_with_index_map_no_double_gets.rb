# `.each_cons[.with_index].map { ... }` over a side-effecting inner
# array evaluates the inner chain once. The inner block's side
# effects (`gets`, an accumulator method, ...) run once, so they do
# not consume twice the input lines or double the counter.

$counter = 0
def step
  $counter += 1
  $counter
end

# `3.times.map { step }` -> [1, 2, 3] (counter should advance by 3,
# not by 6 from a duplicate emission).
result = 3.times.map { step }.each_cons(2).with_index(1).map { |(x, y), i| [x - y, i] }
result.each do |pair|
  puts pair.inspect
end
puts $counter
