# String#split by a String in UTF-16 or UTF-32 matches only whole
# characters, so a separator's bytes across two characters do not split.
def show(parts) = parts.map { |s| s.encode("UTF-8") }
%w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
  p [enc, show("abc\0def".encode(enc).split("\0".encode(enc), -1))]
  p [enc, show("abc,def,".encode(enc).split(",".encode(enc)))]
  p [enc, show("a,b,c".encode(enc).split(",".encode(enc), 2))]
end
