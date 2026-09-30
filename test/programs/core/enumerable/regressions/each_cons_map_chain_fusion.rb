# `arr.each_cons(n)` called without a block returns an Enumerator in
# CRuby. When the very next call is a terminal like
# `.map { |pair| ... }`, the Enumerator is consumed immediately and
# the result is the same as a map over each window.
#
# The terminal block may take the window as a single param
# (`|pair|`) or destructure it (`|(a, b)|`, binds individual locals).

# T1: plain |pair| form, scalar block result
p [1, 2, 3, 4].each_cons(2).map { |pair| pair[0] + pair[1] }

# T2: destructure |(a, b)|, scalar block result
p [10, 20, 30, 40].each_cons(2).map { |(a, b)| b - a }

# T3: |pair| with array-returning block -> result is an Array of Arrays
p [1, 2, 3].each_cons(2).map { |pair| [pair[0], pair[1]] }

# T4: empty / short receiver (length < n) -> empty result
p [1].each_cons(2).map { |pair| pair[0] }
