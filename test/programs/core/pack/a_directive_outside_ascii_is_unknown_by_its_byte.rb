# pack and unpack read a template by its bytes: a byte of a character
# outside ASCII is an unknown directive, named by its byte, and the
# template shows as ruby quotes it.
["\u{3042}", ",", "\x7f", "\u{3042}".encode("euc-jp"), "C\u{00e9}"].each do |fmt|
  [1].pack(fmt)
  p :none
rescue ArgumentError => e
  p [e.message, e.message.encoding.name]
end
p(("x".unpack("\u{3042}") rescue $!.message))
p(("x".unpack1("a\u{00e9}") rescue $!.message))
p([1].pack("C") + [2].pack(" C "))
# The template reads as it goes: an earlier error wins, and unpack1 stops
# at its first value.
p(("x".unpack("x3\u{00e9}") rescue $!.message))
p(("x".unpack("C\u{00e9}") rescue $!.message))
p "xy".unpack1("C\u{00e9}")
