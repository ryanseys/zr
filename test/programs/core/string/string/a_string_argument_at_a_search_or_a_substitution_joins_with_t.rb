# A String argument at a search or a substitution site must join with
# the receiver -- CRuby's rb_enc_check, the same test `+` makes. Without
# it the argument's bytes are read under the receiver's encoding, so the
# search quietly fails (or matches) where ruby raises.
s = "日".encode("Shift_JIS")
pat = "日".encode("EUC-JP")

def show(name)
  p [name, yield]
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message}"
end

show("gsub") { s.gsub(pat, "x") }
show("sub") { s.sub(pat, "x") }
show("index") { s.index(pat) }
show("rindex") { s.rindex(pat) }
show("byteindex") { s.byteindex(pat) }
show("include?") { s.include?(pat) }
show("start_with?") { s.start_with?(pat) }
show("end_with?") { s.end_with?(pat) }
show("split") { s.split(pat) }
show("partition") { s.partition(pat) }
show("rpartition") { s.rpartition(pat) }
show("slice") { s[pat] }
show("count") { s.count(pat) }
show("delete") { s.delete(pat) }
show("squeeze") { s.squeeze(pat) }
show("tr") { s.tr(pat, "x") }
show("plus") { s + pat }

# Comparison makes no such test: two strings of different encodings are
# simply unequal, and they still order.
show("eq") { s == pat }
show("eql") { s.eql?(pat) }
show("cmp") { s <=> pat }

# An ASCII-only argument joins with any ASCII-compatible receiver, so
# these read the bytes and answer.
show("ascii index") { s.index("x".encode("EUC-JP")) }
show("ascii include?") { s.include?("x".encode("EUC-JP")) }
show("ascii gsub") { s.gsub("x".encode("EUC-JP"), "y") }

