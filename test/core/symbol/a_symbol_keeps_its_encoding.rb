# A Symbol is its bytes and the encoding they are in. Binary bytes past
# ASCII make another Symbol than the same bytes as UTF-8, ASCII bytes
# make the same one, and bytes invalid in their encoding make none.
def t = yield rescue [$!.class, $!.message]

p t { "é".b.to_sym == :"é" }, t { "é".b.to_sym.encoding }, t { :"é".encoding }
p t { "ab".b.to_sym == :ab }, t { "ab".b.to_sym.encoding }, t { :ab.encoding }
p t { "\xff".to_sym }, t { "\xff".b.to_sym.encoding }, t { "é".b.to_sym.inspect }
p t { "é".b.to_sym.to_s.encoding }, t { "é".b.to_sym.length }, t { "é".b.to_sym.name.encoding }
p t { "é".b.to_sym.equal?("é".b.intern) }, t { :"é".to_s.encoding }, t { "é".to_sym.equal?(:"é") }

__END__
false
#<Encoding:BINARY (ASCII-8BIT)>
#<Encoding:UTF-8>
true
#<Encoding:US-ASCII>
#<Encoding:US-ASCII>
[EncodingError, "invalid symbol in encoding UTF-8 :\"\\xFF\""]
#<Encoding:BINARY (ASCII-8BIT)>
":\"\\xC3\\xA9\""
#<Encoding:BINARY (ASCII-8BIT)>
2
#<Encoding:BINARY (ASCII-8BIT)>
true
#<Encoding:UTF-8>
true
