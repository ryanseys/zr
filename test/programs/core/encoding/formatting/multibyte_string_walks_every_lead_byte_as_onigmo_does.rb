# A String in a legacy multibyte encoding finds where each character
# ends by the lead-byte lengths and state tables of CRuby's enc/*.c:
# GB18030's four-byte characters all through their range, EUC-TW's
# planes, Emacs-Mule's leading codes, CESU-8's surrogate pairs, and
# the replicas that read as the encoding they copy. A character the text
# ends inside, or a byte that cannot follow its lead, reads as broken
# bytes, and scrub replaces a run of them as CRuby groups it.
def walk(bytes, enc)
  s = bytes.b.force_encoding(enc)
  [s.valid_encoding?, s.length, s.each_char.map(&:bytesize), s.scrub("?").b]
end

gb = ["\x81\x30\x81\x30", "\x84\x31\xA4\x39", "\x84\x31\xA5\x30", "\x90\x30\x81\x30", "\xE3\x32\x9A\x35",
      "\xFE\x39\xFE\x39", "\x81\x40", "\xFE\xFE", "\x81\x7F", "\x81\x30\x81", "\x81\x30", "\x81", "\x80", "\xFF", "\x81\x30\x7F\x30"]
gb.each { |b| p walk("a#{b}z", "GB18030") }

tw = ["\xA1\xA1", "\x8E\xA1\xA1\xA1", "\x8E\xA2\xFE\xFE", "\x8E\xB0\xA1\xA1", "\x8E\xA1\xA1", "\x8E\xA1", "\x8E", "\xA1", "\x8F\xA1\xA1"]
tw.each { |b| p walk("a#{b}z", "EUC-TW") }

mule = ["\x81\xA1", "\x92\xA4\xA2", "\x9A\xA0\xA1", "\x9C\xF0\xA1\xA1", "\x9D\xF5\xA1\xA1", "\x9E\xA1", "\x92\xA4", "\x80"]
mule.each { |b| p walk("a#{b}z", "Emacs-Mule"), walk("a#{b}z", "stateless-ISO-2022-JP") }

cesu = ["\xC3\xA9", "\xE3\x81\x82", "\xED\xA0\x80\xED\xB0\x80", "\xED\xA0\x80", "\xED\xB0\x80", "\xF0\x9F\x98\x80", "\xED\xA0\x80\xED", "\xC0\x80"]
cesu.each { |b| p walk("a#{b}z", "CESU-8") }

jp = ["\x8F\xA1\xA1", "\x8E\xB1", "\x8E\xA0", "\xA1\xA1", "\xA1", "\x8F\xA1", "\xFF\xA1"]
%w[EUC-JP eucJP-ms CP51932 EUC-JIS-2004].each { |enc| jp.each { |b| p walk("a#{b}z", enc) } }

sjis = ["\x81\x40", "\x81\x7F", "\x81\xFC", "\xA1", "\xDF", "\xE0\x40", "\xFC\xFC", "\xFD\x40", "\x80", "\xA0", "\x81"]
%w[Shift_JIS Windows-31J MacJapanese SJIS-KDDI].each { |enc| sjis.each { |b| p walk("a#{b}z", enc) } }

two = ["\x81\x41", "\x81\x5A", "\x81\x61", "\x81\x7F", "\xA1\x40", "\xA1\xA1", "\xFE\xFE", "\xFE\x30", "\x80\x40", "\xFF\xA1", "\xC8"]
%w[Big5 Big5-HKSCS Big5-UAO CP950 CP951 GBK CP949 EUC-KR GB2312 GB12345].each { |enc| two.each { |b| p walk("a#{b}z", enc) } }

text = "a\x95\x32\x82\x36b\xA2\xE3".b.force_encoding("GB18030")
p text.chars.map(&:bytes), text.reverse.b, text[1], text.byteindex("b"), text.index("b"), text.chop.bytesize
p text.encode("UTF-8"), "\u{20000}€".encode("GB18030").chars.map(&:bytesize)
p "a\x80\x81\x30".b.force_encoding("GB18030").scrub { |b| "<#{b.bytes.join(',')}>" }, "a\x80\x8F\xA1".b.force_encoding("EUC-JP").scrub
p "a\xED\xA0\x80".b.force_encoding("CESU-8").scrub, "a\xFF".b.force_encoding("UTF8-MAC").scrub, "a\xFF".b.force_encoding("US-ASCII").scrub, "a\xFF".scrub
p text.ljust(8,"\x81\x30\x81\x30".b.force_encoding("GB18030")).length, text.center(6).bytesize, text.each_grapheme_cluster.count


