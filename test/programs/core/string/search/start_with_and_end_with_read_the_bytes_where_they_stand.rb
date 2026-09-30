# The comparison is of the receiver's own bytes: a prefix that ends
# inside a character is not a prefix, whatever its bytes say, and a
# suffix is read from the offset its length puts it at. CRuby's
# rb_str_start_with joins the encodings, checks the boundary and then
# memcmps, and the boundary is what tells this from a byte compare.
s = "日本語"
p s.start_with?("日"), s.start_with?(s.byteslice(0, 2)), s.start_with?(s.byteslice(0, 4))
p s.end_with?("語"), s.end_with?(s.byteslice(7, 2)), s.end_with?(s.byteslice(3, 6))
p s.start_with?(""), s.end_with?("")
p s.start_with?("x", "日本")
p "".start_with?(""), "".start_with?("a"), "".end_with?("a")
p "abc".start_with?("abcd"), "abc".end_with?("zabc")
p "abc".start_with?("abc"), "abc".end_with?("abc")
p "abc".start_with?(+"ab")
p "hello".start_with?(/l+/), "hello".start_with?(/h/), $~[0]
p "abc".start_with?("ab".dup.force_encoding("ASCII-8BIT"))
