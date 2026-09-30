# newline: names one line end and wins over the older booleans, which
# combine; two line ends are a conversion ruby has none of. lf_newline
# turns CRLF and CR into LF, as universal does.
text = "a\r\nb\rc\n"
[{ newline: :crlf }, { newline: :lf }, { lf_newline: true }, { newline: nil }, { crlf_newline: false },
 { newline: :cr, crlf_newline: false }, { newline: :crlf, universal_newline: true },
 { crlf_newline: true, cr_newline: true }, { universal_newline: true, lf_newline: true }, { newline: :bogus },
 { newline: "x" }, { xml: :bogus }, { xml: "x" }].each do |options|
  p [options, (text.encode("UTF-8", "UTF-8", **options) rescue $!)]
  p [options, (text.encode("EUC-JP", "UTF-8", **options) rescue $!)]
  p [options, (Encoding::Converter.new("UTF-8", "EUC-JP", **options).convpath.drop(1) rescue $!)]
end
p((Encoding::Converter.new("UTF-8", "EUC-JP", invalid: :bogus) rescue $!))
p((Encoding::Converter.new("UTF-8", "EUC-JP", undef: :bogus) rescue $!))
