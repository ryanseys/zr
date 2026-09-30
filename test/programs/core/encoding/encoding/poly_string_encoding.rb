# `encoding` on a String read out of an array with mixed element types.
# It answers the String's Encoding, not NoMethodError and not nil.

a = ["abc", 1][0]
p a.encoding
p a.encoding.to_s
p a.encoding == Encoding::UTF_8

b = [[65].pack("C"), 1][0]
p b.encoding.to_s

h = { "k" => "abc" }
p h["k"].encoding.to_s

def enc_of(v) = v.encoding.to_s
puts enc_of("abc")
puts enc_of([65].pack("C"))

# the concrete arm still answers
p "abc".encoding
p "abc".encoding.to_s
