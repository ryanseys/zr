# A Regexp over Japanese text in a legacy multibyte encoding reads
# whole characters of it: one to three bytes as the encoding lays them
# out, a search that steps back onto a character's first byte, the JIS
# encodings' kana and kanji properties, and their fullwidth, Greek and
# Cyrillic case folds. Replicas (eucJP-ms, CP51932, Windows-31J, ...)
# read as the encoding they copy.
# MacJapanese has no converter of its own; its bytes are Shift_JIS's.
def conv(text, enc) = enc == "MacJapanese" ? text.encode("Shift_JIS").force_encoding(enc) : text.encode(enc)
def re(source, enc, options = 0) = Regexp.new(conv(source, enc), options | Regexp::FIXEDENCODING)
def utf8(s) = s.encoding.name == "MacJapanese" ? s.dup.force_encoding("Shift_JIS").encode("UTF-8") : s.encode("UTF-8")
def show(match) = match && [match.byteoffset(0), utf8(match[0])]

%w[EUC-JP eucJP-ms CP51932 Shift_JIS Windows-31J SJIS-DoCoMo MacJapanese].each do |enc|
  text = conv("カタカナとひらがな、漢字ＡＢＣαβγ ｶﾀｶﾅ ДЖ", enc)
  p enc, text.scan(re(".", enc)).size, show(re("\\p{Hiragana}+", enc).match(text)), show(re("\\p{Han}+", enc).match(text))
  p show(re("\\p{Katakana}+$", enc).match(conv("カナ ｶﾅ", enc))), show(re("ａｂｃ", enc, Regexp::IGNORECASE).match(text))
  p show(re("ΑΒΓ", enc, Regexp::IGNORECASE).match(text)), show(re("дж", enc, Regexp::IGNORECASE).match(text))
  p text.index(re("ひ", enc)), text.rindex(re("カ", enc)), text.split(re("、", enc)).size, show(re("\\w+$", enc).match(text))
  p show(re("(?<=漢)字", enc).match(text)), utf8(text.gsub(re("[かが]", enc), conv("*", enc)))
  p show(re("\\\\", enc).match(conv("表\\示", enc))), re("ソ", enc).match(conv("表ソ", enc))&.byteoffset(0)
end

p show(re("\\p{Latin}+", "EUC-JP").match("ｘ ＸＹ".encode("EUC-JP"))), show(re(".", "EUC-JP").match("丨".encode("EUC-JP")))
