# frozen_string_literal: true

# A `return`, `next` or `break` that carries more than one value answers
# one Array, and a lone `*xs` does too.

def pair = return 1, 2
def three
  return 3, 4, 5
end
def spread(a)
  return *a
end
def leading(a)
  return 1, *a
end
p pair
p three
p spread([7, 8])
p spread([9])
p leading([2, 3])

# The same rule for the two jumps a block writes.
p([1].map { next 5, 6 })
def broken
  [1, 2].each { break 7, 8 }
end
p broken
p [1, 2].map { |i| next i, i }

# One value stays one value, and none is nil.
def single = return 1
def bare
  return
end
p single
p bare
__END__
[1, 2]
[3, 4, 5]
[7, 8]
[9]
[1, 2, 3]
[[5, 6]]
[7, 8]
[[1, 1], [2, 2]]
1
nil
