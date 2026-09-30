# `<int_array>.method(:op)` gives a Method object that works like any
# other Method. The shape comes from optcarrot's CPU memory-mapping
# `add_mappings(0x0000..0x07ff, @ram, @ram.method(:[]=))` —
# the captured Method later sits in @store and is invoked via
# `@store[addr][addr, val]`.
#
# The example checks three operators: `:[]`, `:[]=` and `:push`.

a = [10, 20, 30, 40, 50]

mget = a.method(:[])
mset = a.method(:[]=)
mpush = a.method(:push)

# Read via captured Method: bracket-call shape.
puts mget[0]
puts mget[2]
puts mget[4]

# Write via captured Method: mutates the receiver in place.
mset[1, 200]
mset[3, 400]
puts a[0]
puts a[1]
puts a[2]
puts a[3]
puts a[4]

# Push via captured Method: extends the receiver.
mpush[60]
mpush[70]
puts a.length
puts a[5]
puts a[6]
