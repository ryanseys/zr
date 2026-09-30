# A destructuring param may carry a splat, named or anonymous -- the same
# `before`/`splat`/`after` shape every multi-assignment target group has.

[[1, [2, 3, 4]]].each { |a, (b, *r)| p [a, b, r] }
[[1, 2, 3]].each { |a, (*), b| p [a, b] }
[[[1, 2, 3], 9]].each { |(*init, last), z| p [init, last, z] }
