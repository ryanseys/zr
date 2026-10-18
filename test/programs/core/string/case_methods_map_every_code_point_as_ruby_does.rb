# upcase, downcase, swapcase and capitalize map every Unicode character
# as ruby does, in each mode: one character to one, one to several
# (ß, ŉ, ΐ, ﬃ), the Turkish dotted and dotless i, and :ascii, which leaves
# each character past ASCII alone. A CRC of each result shows any
# character that maps another way.
require "zlib"

chars = (0..0x10FFFF).filter_map { |cp| cp.chr(Encoding::UTF_8) unless (0xD800..0xDFFF).cover?(cp) }
text = chars.join
words = chars.each_slice(7).map(&:join)
[[], [:turkic], [:ascii], [:lithuanian]].each do |opts|
  %i[upcase downcase swapcase capitalize].each do |m|
    whole = text.send(m, *opts)
    each = words.map { |w| w.send(m, *opts) }.join
    puts "#{m} #{opts.inspect}: #{whole.length} #{Zlib.crc32(whole)} #{Zlib.crc32(each)} #{whole.encoding}"
  end
end
samples = ["Straße", "ŉ", "ΐ", "ﬃ", "İstanbul", "ıi", "ǅǄǆ", "ǰ", "ΣΊΣΥΦΟΣ", "\u{1E900}", "ᾳ", "Ꭰꭰ", "aBc", ""]
samples.each do |s|
  p [s.upcase, s.downcase, s.swapcase, s.capitalize, s.upcase(:turkic), s.downcase(:turkic), s.capitalize(:turkic), s.swapcase(:ascii)]
end
p "Ǆemal".capitalize, "ǆEMAL".capitalize, "ﬃx".capitalize, "ßa".capitalize
x = +"äb"
p x.upcase!, x, x.downcase!, x.swapcase!, x.capitalize!, x.capitalize!
p "ÄB".encode("ISO-8859-1").downcase.encode("UTF-8"), "äb".encode("UTF-16LE").upcase.encode("UTF-8")
