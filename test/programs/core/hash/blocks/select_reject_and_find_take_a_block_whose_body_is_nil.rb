# The nil-block-body family on a HASH receiver: `select { nil }`,
# `reject {}` and `find { nil }`.
#
# A body whose value IS nil is statically FALSY, so select keeps nothing,
# reject keeps everything, and find never wins -- and the body still runs,
# for its effects.
h = { a: 1, b: 2 }
p h.select { nil }
p h.reject { nil }
p h.select {}
p h.reject {}
p h.find { nil }
p h.find {}
p h.detect { nil }
p h.filter { nil }

# min_by / max_by over a hash compare through the ORDERING entry, not the
# Comparable operator: a key that is always nil ties everywhere, so the first
# entry wins rather than the comparison failing
p h.min_by { nil }
p h.max_by { nil }
p h.min_by {}
p h.max_by {}

# side effects in a falsy body still happen
seen = []
h.select { seen << 1; nil }
p seen

# and the ordinary predicates keep working
p h.select { |k, v| v > 1 }
p h.reject { |k, v| v > 1 }
p h.find { |k, v| v > 1 }
p h.min_by { |k, v| -v }
p h.max_by { |k, v| -v }
