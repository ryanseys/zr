# String#each_codepoint walks a String of single-byte characters (ASCII
# text, or a single-byte encoding) byte by byte as each_byte does, so a
# change made during the walk shows; any other String is walked as a
# frozen copy of what it was when the walk started.
def walk(s)
  e = s.each_codepoint
  first = e.next
  yield s
  [first, *loop.map { e.next }]
end

p walk(+"ab") { |s| s.replace("XYZ") }
p walk(+"ab") { |s| s.replace("éY") }
p walk((+"ab").force_encoding("ISO-8859-1")) { |s| s.replace("\xE9YZ".force_encoding("ISO-8859-1")) }
p walk(+"aé") { |s| s.replace("XYZ") }
p walk(+"aé") { |s| s.clear }
p walk(+"abc") { |s| s.clear }

seen = []
s = +"abc"
s.each_codepoint { |c| seen << c; s << "d" if seen.size == 1 }
p seen
seen = []
u = +"aéb"
u.each_codepoint { |c| seen << c; u << "d" if seen.size == 1 }
p seen, u
p "aé".each_codepoint.size, "".each_codepoint.to_a
seen = []
s = +"abc"
p s.codepoints { |c| seen << c; s << "d" if seen.size == 1 }.equal?(s), seen
