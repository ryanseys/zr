# A Regexp written in UTF-16 or UTF-32 reads text of that encoding a
# character at a time: two or four bytes, a surrogate pair as one
# character, a newline as the character U+000A, and Unicode's classes,
# properties and case folds. Its source, inspect and errors show the
# pattern's own characters. CESU-8 reads a character past the BMP as its
# two three-byte surrogates.
def u(text, enc) = text.encode(enc)
def show(match) = match && [match.byteoffset(0), match[0].encode("UTF-8")]

%w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
  text = u("Grüße, 世界!\nδύο 😀 lines\n", enc)
  re = Regexp.new(u("(\\w+), (\\p{Han}+)", enc))
  m = re.match(text)
  p enc, m.byteoffset(0), m.captures.map { _1.encode("UTF-8") }, m.pre_match.bytesize, m.begin(2)
  p text.scan(Regexp.new(u(".", enc))).size, text.scan(Regexp.new(u("^\\S+", enc))).map { _1.encode("UTF-8") }
  p show(Regexp.new(u("GRÜSSE", enc), Regexp::IGNORECASE).match(text)), show(Regexp.new(u("ΔΎΟ", enc), Regexp::IGNORECASE).match(text))
  p show(Regexp.new(u("\\X\\s+lines$", enc)).match(text)), text.index(Regexp.new(u("😀", enc))), text.rindex(Regexp.new(u("\\w", enc)))
  p text.gsub(Regexp.new(u("[aeiouüύ]", enc)), u("*", enc)).encode("UTF-8"), text.split(Regexp.new(u("\\n", enc))).size
  p Regexp.new(u("\\bl\\w+", enc)).match(text)&.byteoffset(0), (Regexp.new(u("\\A\\p{Upper}", enc)) =~ text)
  p Regexp.new(u("a+b", enc)).source.encoding, Regexp.new(u("a+b", enc)).source.bytesize
end

cesu = "x\u{1F600}y".encode("CESU-8")
p cesu.bytesize, Regexp.new("x(.)y".encode("CESU-8")).match(cesu).byteoffset(1), cesu.scan(Regexp.new(".".encode("CESU-8"))).size
p Regexp.new("\\p{Emoji}".encode("CESU-8")).match(cesu)&.byteoffset(0)

# A warning shows a wide pattern a byte at a time.
$VERBOSE = true
Regexp.new(u("[aa]]", "UTF-16LE"))
Regexp.new(u("x**", "UTF-32BE"))
$VERBOSE = false

begin
  Regexp.new(u("(?<n>a)\\k<m>", "UTF-16LE"))
rescue RegexpError => e
  p e.message.encoding, e.message.bytesize
end
begin
  Regexp.new(u("\\p{Nope}", "UTF-32BE"))
rescue RegexpError => e
  p e.message.encoding, e.message.b[0, 40]
end
p (Regexp.new(u("a", "UTF-16LE")) =~ "a") rescue p $!.class, $!.message


