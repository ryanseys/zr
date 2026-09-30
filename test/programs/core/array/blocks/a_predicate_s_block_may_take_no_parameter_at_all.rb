# any?/all?/none?/one? with a block that takes NO parameter. The block
# cannot reference the yielded value, so nothing binds it. Covers empty and
# non-empty arrays plus the range path.
p([].any? { true })
p([1, 2].any? { true })
p([].all? { false })
p([1, 2].all? { true })
p([1, 2].none? { false })
p([1, 2, 3].one? { true })
p([1].one? { true })
p((1..3).any? { true })
p((1..3).all? { false })
p((1..3).none? { false })
