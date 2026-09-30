# Array pattern with a `*rest` splat target. The rest local exists in
# the surrounding scope.
case [1, 2, 3]
in [first, *rest]
  puts "first=" + first.to_s
  puts "rest=" + rest.inspect
end

# `Array(...)` with capture constant + rest
case [10, 20, 30]
in Array(head, *tail)
  puts "head=" + head.to_s
  puts "tail=" + tail.inspect
end
