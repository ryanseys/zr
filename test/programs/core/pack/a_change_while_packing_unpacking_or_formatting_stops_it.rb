# A conversion or a block that changes what pack, unpack or format reads
# stops it, as ruby 4.1 checks: pack reads its format at each byte and
# packs on into a buffer the conversion changed, unpack checks the String
# and the format after each value its block takes, and String#% checks its
# Array at each argument. A %c of a width the result cannot hold raises.
$stdout.sync = true
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end
buf = "x" * 10_000
o = Object.new
o.define_singleton_method(:to_int) { buf.clear; 1 }
try(:pack_R) { [o, 42].pack("R R", buffer: buf); buf }
buf = "x" * 10_000
o = Object.new
o.define_singleton_method(:to_int) { buf.clear; -2 }
try(:pack_r) { [o].pack("r", buffer: buf); buf }
fmt = "a" + " " * 1000
o = Object.new
o.define_singleton_method(:to_str) { fmt.clear; "A" }
try(:pack_fmt) { [o].pack(fmt) }
fmt2 = "a"
o2 = Object.new
o2.define_singleton_method(:to_str) { fmt2.clear; "A" }
try(:pack_fmt_no_tail) { [o2].pack(fmt2) }
s = "C" * 4000
try(:unpack_clear) { s.unpack("L*") { s.clear } }
s = "ABCD"
try(:unpack_grow) { s.unpack("C*") { s << "E" * 100 } }
fmt = "C" * 10_000
try(:unpack_fmt) { ("A" * 4000).unpack(fmt) { fmt.clear } }
got = []
try(:unpack_plain) { "ABC".unpack("C*") { got << _1 }; got }
try(:sprintf_c0) { sprintf("%*c", 0, ?!.ord) }
try(:sprintf_c_big) { sprintf("%*c", 2147483647, 0x80) }
# A one-byte character takes a wide width (the full INT_MAX would need 2 GB).
try(:sprintf_c_ascii) { sprintf("%*c", 100_000, 0x41).then { [_1.size, _1[-1], _1.count(" ")] } }
obj = Object.new
ary = [obj, *Array.new(9) { "x" }]
obj.define_singleton_method(:to_s) { ary.replace([]); "X" }
try(:format_modify) { ("%s" * 10) % ary }
try(:format_plain) { "%s-%s" % [1, 2] }
