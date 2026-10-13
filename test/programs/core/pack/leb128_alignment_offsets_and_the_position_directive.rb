# ruby 4.1's pack templates: R and r (unsigned and signed LEB128), x! and
# @! (align the position to a number or to a type), unpack's ^ (the
# position), a negative unpack offset (from the end), and a buffer that
# is packed into itself.
def t
  p yield
rescue => e
  p [e.class, e.message]
end

[0, 1, 63, 64, 127, 128, -1, -2, -63, -64, -65, -128, -129, 2**63, -(2**63), 2**64 - 1, 8191, 8192, -8192, -8193, 2**100].each do |n|
  t { [n, [n].pack("r").unpack1("H*"), [n].pack("r").unpack1("r") == n] }
  t { [n, [n].pack("R").unpack1("H*"), [n].pack("R").unpack1("R") == n] }
end
t { "\x80\x01\x7f\xc0\x00".unpack("R*") }
t { "\x80\x01\x7f\xc0\x00".unpack("r*") }
t { ["\x80".unpack("R"), "\x80".unpack("R2"), "\x80".unpack("R*"), "\x01\x80".unpack("R3"), "".unpack("R"), "".unpack("R*")] }
t { [1, 2, 300].pack("R*") }
t { [1.5, 2r, -3.9].pack("r3") }
t { ["a"].pack("R") }
t { [nil].pack("r") }
t { [].pack("R") }
t { x = []; "\x01\x02\x80".unpack("R4") { |v| x << v }; x }
t { "\x7f\x80\x01".unpack1("R*") }

t { "abc".unpack("C^C^") }
t { "abc".unpack("^") }
t { "abc".unpack1("^", offset: 2) }
t { "abcdef".unpack("C2", offset: -2) }
t { "abcdef".unpack("^C", offset: -6) }
t { "abc".unpack("C", offset: -4) }
t { "abc".unpack("C^", offset: -1) }
t { "abc".unpack1("C", offset: -3) }
t { "abc".unpack("C", offset: 4) }

t { [1, 2].pack("Cx!4C").bytes }
t { [1, 2].pack("Cx!lC").bytesize }
t { [1, 2].pack("Cx!l_C").bytesize }
t { [1, 2].pack("Cx!qC").bytesize }
t { [1, 2].pack("Cx!dC").bytesize }
t { [1, 2].pack("Cx!SC").bytesize }
t { [1, 2].pack("C@!8C").bytesize }
t { [1].pack("C@!4", buffer: +"zz").bytes }
t { [1].pack("Cx!4", buffer: +"zz").bytes }
t { [1].pack("x!") }
t { [1].pack("x!z") }
t { [1].pack("x!0") }
t { [1].pack("x!l<") }
t { [1].pack("x!C*") }
t { [1].pack("x!99999999999999999999") }
t { [1].pack("x!9223372036854775808") }
t { [1].pack("C x!1 C") }
t { "\x01\x00\x00\x00\x02".unpack("Cx!4C") }
t { "\x01\x00".unpack("Cx!4C") }
t { "\x01\x00".unpack("C@!4C") }
t { "\x09\x01\x00\x00\x00\x02".unpack("Cx!4C", offset: 1) }
t { "\x09\x01\x00\x00\x00\x02".unpack("C@!4C", offset: 1) }
t { "\x01\x02".unpack("x!4^") }

b = +"ab"
t { [b].pack("a*", buffer: b) }
t { [b].pack("m", buffer: b) }
t { [b].pack("M", buffer: b) }
t { [b].pack("P", buffer: b) }
t { [b.dup].pack("a*", buffer: b) }
t { [1].pack("^") }
