# A find pattern tries its middle at each place in turn, and a nested
# pattern there asks `deconstruct` of that place's element, not of the
# first one it met.
case [[1], [2]]
in [*, [2], *] then p :ok
end

case [[1, 2], [3, 4], [5, 6]]
in [*pre, [5, y], *post] then p [pre, y, post]
end

case [{k: 1}, {k: 2}]
in [*, {k: 2 => two}, *] then p two
end

p(([[0], [9]] in [*, [9], *]))
p(([[0], [8]] in [*, [9], *]))

__END__
:ok
[[[1, 2], [3, 4]], 6, []]
2
true
false
