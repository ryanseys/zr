# Random#bytes and Random.bytes read the size as a C long, as Random.urandom
# does: a negative size raises ArgumentError, one past a long RangeError
# before any byte is drawn, and a Float truncates.
def try(l) = (p [l, yield]) rescue p([l, $!.class, $!.message])
b = 2 ** 63
try(:u_neg) { Random.urandom(-1) }
try(:u_big) { Random.urandom(b) }
try(:b_neg) { Random.new.bytes(-1) }
try(:b_big) { Random.new.bytes(b) }
try(:b_big2) { Random.bytes(b) }
try(:b_float) { Random.new.bytes(2.5).size }
try(:b_neg2) { Random.bytes(-1) }
try(:fmt) { Random.new.bytes("x") }
try(:sizes) { [0, 1, 3, 4, 5, 9].map { Random.new(1).bytes(_1).bytesize } }
try(:to_int) { Random.new(2).bytes(Class.new { def to_int = 6 }.new).bytesize }
