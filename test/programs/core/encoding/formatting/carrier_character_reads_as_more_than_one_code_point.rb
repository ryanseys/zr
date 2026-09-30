# The carriers' own encodings hold characters that stand for more than
# one code point: a flag is two regional letters, and a keycap is a digit
# with a mark after it. One character in, two out, so a table of code
# points is not enough to read them.
[["SJIS-KDDI", "\xF3\x48"], ["SJIS-SoftBank", "\xF2\xD9"], ["SJIS-DoCoMo", "\xF9\x85"]].each do |name, bytes|
  text = bytes.dup.force_encoding(name)
  up = text.encode("UTF-8")
  p [name, text.length, up.length, up.codepoints.map { |point| format("U+%04X", point) }]
end

