# Big5 and EUC-JP encode as CRuby does, where WHATWG's tables disagree
# with CRuby's. The tables come from CRuby's converters (tool/gen/cjk.rb),
# so a sample of each region checks the encode path; a sweep of every code
# point took a minute and more on wasm and the walker.

def show(name)
  puts "#{name}\t#{yield}"
rescue Exception => e
  puts "#{name}\t#{e.class}"
end

# One code point in every 251 up to U+2FFFF (neither family maps anything
# above it). A code point that the family does not map encodes to "".
%w[Big5 EUC-JP].each do |enc|
  (0..0x2FFFF).step(251) do |cp|
    next if cp.between?(0xD800, 0xDFFF)
    e = cp.chr(Encoding::UTF_8).encode(enc, undef: :replace, replace: "")
    puts "#{enc}\tU+#{cp.to_s(16).upcase}\t#{e.unpack1('H*')}" unless e.empty?
  end
end

# One character of each region of the tables: ASCII, Latin-1, Greek,
# Cyrillic, symbols, kana, half-width kana, Han from JIS X 0208 and
# JIS X 0212, full-width forms, hangul and an emoji.
"a é × Ω Ж € ※ あ ア ｱ 中 丂 Ａ 한 😀".split.each do |ch|
  %w[Big5 EUC-JP].each do |enc|
    show("#{enc} #{ch}") { ch.encode(enc).unpack1("H*") }
  end
end

# Big5 DENIES Cyrillic and Latin-1, which WHATWG maps, and EUC-JP reaches
# JIS X 0212 through SS3 (é, 丂), as CRuby does.
show("euc roundtrip") { "é".encode("EUC-JP").encode("UTF-8") == "é" }

# DECODE is untouched, in both families.
show("big5 decode") { "\xa4\xa4".dup.force_encoding("Big5").encode("UTF-8") }
show("euc decode") { "\xa4\xa2".dup.force_encoding("EUC-JP").encode("UTF-8") }
show("euc decode ss3") { "\x8f\xab\xb1".dup.force_encoding("EUC-JP").encode("UTF-8") }
