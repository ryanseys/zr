# String's own methods read wide and legacy text a character at a time:
# length and each_char, reverse and slicing, justification, strip and
# chomp with the encoding's own spaces and newlines, squeeze, count,
# delete and tr over the encoding's characters, case mapping, succ,
# inspect and dump, ord and codepoints, and lines in paragraph mode.
def shown(v)
  case v
  when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
  when Array then v.map { |x| shown(x) }
  else v
  end
end

def show(label)
  p [label, shown(yield)]
rescue StandardError, NotImplementedError => e
  p [label, e.class, e.message.b]
end

SAMPLES = {
  "UTF-16LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-16BE" => " Grüße 世界😀\r\n\n\nend \n",
  "UTF-32LE" => " Grüße 世界😀\r\n\n\nend \n", "UTF-32BE" => " Grüße 世界😀\r\n\n\nend \n",
  "CESU-8" => " Grüße 世界😀\r\n\n\nend \n", "GB18030" => " Grüße 世界😀\r\n\n\nend \n",
  "EUC-JP" => " カナ 世界ａ\r\n\n\nend \n", "Shift_JIS" => " カナ ソ表\\\r\n\n\nend \n", "Big5" => " 中文 測試\r\n\n\nend \n",
  "GBK" => " 中文 测试\r\n\n\nend \n", "EUC-KR" => " 한국 세계\r\n\n\nend \n", "ISO-8859-7" => " Καλη ΑΒ\r\n\n\nend \n",
}.freeze

SAMPLES.each do |name, sample|
  e = ->(s) { s.encode(name) }
  text = e.(sample)
  show(:"#{name}_length") { [text.length, text.bytesize, text.chars.size, text.each_char.first(3), text.valid_encoding?, text.ascii_only?] }
  show(:"#{name}_reverse") { [text.reverse, text[2, 3], text[-4..], text.slice(1), text.byteslice(2, 4).valid_encoding?] }
  show(:"#{name}_justify") { [text.strip.center(20, e.("*")), text.strip.ljust(18), text.strip.rjust(18, e.("-="))] }
  show(:"#{name}_strip") { [text.strip, text.lstrip, text.rstrip, text.chomp, text.chop, text.chomp(e.("\n")), text.chomp(e.("d \n"))] }
  show(:"#{name}_lines") { [text.lines, text.lines(chomp: true), text.lines(e.("")), text.lines(e.(""), chomp: true), text.each_line(e.("e")).to_a] }
  show(:"#{name}_lines_default") { [text.lines($/).size, (text.lines("\n") rescue $!.class)] }
  show(:"#{name}_count") { [text.count(e.("e")), text.count(e.("a-z")), text.delete(e.(" ")), text.squeeze, text.squeeze(e.("\n"))] }
  show(:"#{name}_tr") { [text.tr(e.("a-y"), e.("b-z")), text.tr_s(e.("\n"), e.("|")), text.delete(e.("^a-z"))] }
  show(:"#{name}_case") { [text.upcase, text.downcase, text.swapcase, text.capitalize, text.upcase(:ascii)] }
  show(:"#{name}_casecmp") { [text.casecmp(text.upcase), text.casecmp?(text.upcase), text == text.dup, text.eql?(e.(sample))] }
  show(:"#{name}_succ") { [e.("az").succ, e.("zz").succ, text.strip.succ] }
  show(:"#{name}_inspect") { [text.inspect, text.dump] }
  show(:"#{name}_codepoints") { [text.ord, text.codepoints.first(8), text.sum, text.getbyte(1), text.hash == e.(sample).hash] }
  show(:"#{name}_index") { [text.index(e.("e")), text.rindex(e.("e")), text.byteindex(e.("end")), text.include?(e.("nd")), text.start_with?(e.(" ")), text.end_with?(e.("\n"))] }
  show(:"#{name}_split") { [text.split, text.split(e.("\n")), text.split(e.(""), 4), text.partition(e.(" ")), text.rpartition(e.(" "))] }
  show(:"#{name}_insert") { [text.dup.insert(2, e.("<>")), text.dup.prepend(e.(">")), text.dup << e.("!"), text * 2 == text + text] }
  show(:"#{name}_each_grapheme") { text.each_grapheme_cluster.first(4) }
  show(:"#{name}_scrub") { [text.scrub, (text.b + "\xFF".b).force_encoding(name).scrub.bytesize] }
  show(:"#{name}_unicode_normalize") { text.unicode_normalize(:nfd).length }
  show(:"#{name}_encode") { [text.encode("UTF-8").bytesize, text.encode("UTF-16LE").bytesize] }
end

# A UTF-16 or UTF-32 text that ends in broken units: the decoder's
# tables say which bytes are invalid and which a longer text would
# complete, and a bad byte inside a unit takes the rest of the unit.
%w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
  ["  ", " ", "\x00 ", "\x00\x00 ", "\x00\x11  ", "   ", "\xD8\x00\x00\x00", "\x00\xD8\x00\x00", "\xDC\x00a", "\x00\xDCa", "\x00\xD8\x00\xDC"].each do |tail|
    s = ("a".encode(enc).b + tail.b).force_encoding(enc)
    label = :"#{enc}_tail_#{tail.unpack1('H*')}"
    show(label) do
      s.encode("UTF-8")
    rescue Encoding::InvalidByteSequenceError => e
      [e.message.b, e.error_bytes.b, e.readagain_bytes&.b, e.incomplete_input?]
    end
    show(:"#{label}_replaced") { [s.encode("UTF-8", invalid: :replace), s.valid_encoding?, s.length, s.scrub.bytesize, s.chars.map(&:bytesize)] }
  end
end


