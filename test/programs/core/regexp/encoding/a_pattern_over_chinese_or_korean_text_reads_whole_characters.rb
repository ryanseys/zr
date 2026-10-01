# A Regexp over Chinese or Korean text in a legacy multibyte encoding
# reads whole characters of it: one to four bytes as the encoding lays
# them out, and a search that steps back onto a character's first byte.
# Replicas (CP950, CP936, GB2312, ...) read as the encoding they copy.
def re(source, enc) = Regexp.new(source.encode(enc), Regexp::FIXEDENCODING)
def show(match) = match && [match.byteoffset(0), match[0].encode("UTF-8")]

%w[Big5 CP950 Big5-HKSCS Big5-UAO GBK CP936 GB18030 EUC-KR GB2312 GB12345 CP949].each do |enc|
  sample = { "Big5" => "中文字元，測試", "GBK" => "中文字符，测试", "GB18030" => "中文字符，测试\u{20000}€",
             "EUC-KR" => "한국어 문자열", "CP949" => "한국어 똠방각하" }
  base = { "CP950" => "Big5", "Big5-HKSCS" => "Big5", "Big5-UAO" => "Big5", "CP936" => "GBK", "GB2312" => "GBK", "GB12345" => "GBK" }
  source = sample.fetch(base.fetch(enc, enc)) { sample.fetch("EUC-KR") }
  source = "中文字符" if enc.start_with?("GB2312", "GB12345")
  text = source.encode(enc)
  chars = source.each_char.to_a
  p enc, text.scan(re(".", enc)).size, show(re("#{chars[1]}(.)", enc).match(text)), text.rindex(re(chars[0], enc))
  p text.index(re(chars.last, enc)), show(re("\\w+", enc).match(text)), show(re("[#{chars[0]}#{chars[2]}]+", enc).match(text))
  p show(re("(?<!#{chars[0]})#{chars[2]}", enc).match(text)), text.split(re(chars[1], enc)).map(&:bytesize)
end

# EUC-TW has no converter: its characters are written as bytes, two for
# plane 1 and four (0x8E, the plane, two bytes) for the others.
def tw(bytes) = bytes.dup.force_encoding("EUC-TW")
text = tw("\xC4\xA1\xC4\xA2a\x8E\xA2\xA1\xA1\xC5\xE3 \xC4\xA1")
p text.scan(Regexp.new(tw("."))).map(&:bytesize), text.rindex(Regexp.new(tw("\xC4\xA1"))), Regexp.new(tw("\xC4\xA2(.)")).match(text)&.byteoffset(0)
p Regexp.new(tw("\\w+")).match(text).byteoffset(0), Regexp.new(tw("(?<=\x8E\xA2\xA1\xA1)\xC5\xE3")).match(text)&.byteoffset(0), text.split(Regexp.new(tw("a"))).map(&:bytesize)
four = tw("\x8E\xA2\xA1\xA1a")
p four.valid_encoding?, Regexp.new(tw(".")).match(four).byteoffset(0), (Regexp.new(tw("a")) =~ four)
mule = "a\x92\xA4\xA2b\x81\xA1".dup.force_encoding("Emacs-Mule")
p mule.valid_encoding?, mule.scan(Regexp.new(".".force_encoding("Emacs-Mule"))).map(&:bytesize)
p Regexp.new("b".force_encoding("stateless-ISO-2022-JP")).match(mule.dup.force_encoding("stateless-ISO-2022-JP"))&.byteoffset(0)
gb = "a\x81\x30\x81\x30b".dup.force_encoding("GB18030")
p gb.valid_encoding?, gb.scan(re(".", "GB18030")).map(&:bytesize), gb.rindex(re("\\w", "GB18030"))
