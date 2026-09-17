# A Regexp over EUC-JP, Shift_JIS or Windows-31J text reads it a character
# at a time, with that encoding's own classes and case folds: `.` takes a
# whole two-byte character. The engine carries Onigmo's UTF-8 and ASCII
# encodings only, so text in any other multibyte encoding is read a byte
# at a time.
def re(source, enc, options = 0) = Regexp.new(source.encode(enc), options)
euc = "日本語テキスト".encode("EUC-JP")
p euc.scan(re(".", "EUC-JP")).size, euc =~ re("語", "EUC-JP"), euc.index(re("テ", "EUC-JP"))
p re(".", "EUC-JP").match(euc)[0].bytesize, re("\\w+", "EUC-JP").match(euc)&.[](0)&.bytesize
sjis = "表示ソフト".encode("Shift_JIS")
p re(".", "Shift_JIS").match(sjis)[0].bytesize, re("\\\\", "Shift_JIS") =~ sjis, sjis.split(re("", "Shift_JIS")).size
p re("ト", "Windows-31J").match("ソフト".encode("Windows-31J")).begin(0)
p re("[ア-ン]+", "EUC-JP").match("カタカナ".encode("EUC-JP"))[0].bytesize
p re("ａ", "EUC-JP", Regexp::IGNORECASE) =~ "Ａ".encode("EUC-JP")
p "ｶﾀｶﾅ".encode("Shift_JIS").scan(re(".", "Shift_JIS")).size

__END__
7
2
3
2
nil
2
nil
5
2
8
0
4
