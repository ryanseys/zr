# A text with one byte past ASCII, matched many times, then changed
# under the memo: the scan's answer follows the bytes.
text = "id=1 café id=2 id=3"
p text.scan(/id=(\d+)/).flatten, text.ascii_only?, text.scan(/caf./)
text.sub!("café", "cafe")
p text.ascii_only?, text.scan(/caf./), text =~ /é/
text << "é"
p text.ascii_only?, text.scan(/caf./), text.index(/é/)
b = text.b
p b.ascii_only?, b.force_encoding("UTF-8").ascii_only?
u = "abc".encode("UTF-16LE")
p u.ascii_only?, u.force_encoding("UTF-8").ascii_only?, u.force_encoding("UTF-16LE").ascii_only?
r = /a/
p r.match?("a"), r.match?("é a"), r.match?("a".b), r.match?("é a".b), r.match?("xa".encode("Shift_JIS"))
