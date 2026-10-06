# sort_by / min_by / max_by order by a Rational or a Bignum key, as Array#sort
# and #max order Rationals.
p [3, 1, 2].sort_by { |n| Rational(n, 2) }
p [3, 1, 2].min_by { |n| Rational(n, 2) }
p [3, 1, 2].max_by { |n| Rational(n, 2) }

# a descending key, so the answer is not the identity either way
p [3, 1, 2].sort_by { |n| Rational(10 - n, 3) }
p [3, 1, 2].min_by { |n| Rational(10 - n, 3) }

# a Bignum key
p [3, 1, 2].sort_by { |n| 10**20 * n }
p [3, 1, 2].max_by { |n| 10**20 * n }

# the count forms and a hash receiver take the same route
p [3, 1, 2].min_by(2) { |n| Rational(n, 2) }
p({ "a" => 3, "b" => 1 }.sort_by { |k, v| Rational(v, 2) })
p [1.5, 0.5].sort_by { |f| f.to_r }

# the count form orders its keys the same way, so a String or Symbol key works
# there too
p %w[pear fig apple].min_by(2) { |w| w }
p [:c, :a, :b].max_by(2) { |s| s }
p [[2, 9], [1, 0]].min_by(1) { |a| a }
