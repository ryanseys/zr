# Each call to `Object.new` builds a distinct object, so two
# sentinels are distinct by identity.

A = Object.new
B = Object.new
p A == B
p A == A
p A.is_a?(Object)
