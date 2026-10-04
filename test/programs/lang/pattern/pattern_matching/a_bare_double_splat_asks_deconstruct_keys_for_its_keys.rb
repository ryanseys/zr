# A bare `**` asks `deconstruct_keys` for the pattern's keys, as no rest
# does. `**rest`, `**nil` and an empty pattern ask for every key (nil).
o = Object.new
def o.deconstruct_keys(keys) = (p keys; {a: 1, b: 2})
case o
in {a: 1, b: 2, **} then p :bare
end
case o
in {a: 1, **r} then p r
end
case o
in {a: 1, **nil} then p :nil_rest
in {a: 1} then p :plain
end
case o
in {} then p :empty
in {**r} then p r
end
