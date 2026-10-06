def found(id) = ObjectSpace._id2ref(id) rescue $!

x = Object.new
id = x.object_id
p found(id).equal?(x), found(4), found(12345678), found(1.object_id)
p found(id + 800000), found(2**64), found(-(2**63) - 1), found(1 << 40), found(2**64 - 1)
p found(1.5.object_id), found(0), found(8), found(2), found(99999999999998)
Ractor.new {}.value
p found(id).class, found(nil.object_id), found(1.object_id), found(:a.object_id)
p found("x".freeze.object_id), found(Object.object_id)
