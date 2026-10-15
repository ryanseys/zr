# String#append_as_bytes checks the type of every part before it appends
# a byte, so a bad part appends nothing; then a frozen String raises,
# also with no parts. Each part's bytes are those it has at the start.
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

s = +"ab"
try("bad last part") { s.append_as_bytes(1, "x", :sym) }
p s
try("bad first part") { s.append_as_bytes(nil, 1) }
p s
frozen = "fr".freeze
try("frozen, no parts") { frozen.append_as_bytes }
try("frozen, a part") { frozen.append_as_bytes("x") }
try("frozen, a bad part") { frozen.append_as_bytes(:x) }
try("self") { s.append_as_bytes(s) }
try("self twice") { s.append_as_bytes(s, s).bytesize }
try("integers") { (+"").append_as_bytes(65, 256 + 66, -1, 2**70 + 67).bytes }
try("returns self") { t = +"q"; t.append_as_bytes("r").equal?(t) }
e = +"é"
e.append_as_bytes(0xC3, 0xA9)
p e, e.valid_encoding?, e.length
u = (+"a").force_encoding("US-ASCII")
u.append_as_bytes(0xFF)
p u.encoding, u.valid_encoding?
b = "".b
b.append_as_bytes("é")
p b, b.encoding
