# Each encoding gives a sample made of the code points it can hold, and
# ruby and zr agree on its validity, characters, inspect form, case maps
# and conversions.
POINTS = [0x41, 0x7A, 0x30, 0x20, 0xE9, 0xC4, 0x3B1, 0x416, 0x5D0, 0x627, 0x3042, 0x30A2, 0x4E2D, 0xAC00, 0x20AC, 0xFF21, 0x1F600, 0x10400]
def t(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end
Encoding.list.sort_by(&:name).each do |enc|
  # A Big5 sample that ruby joins from valid pieces keeps their coderange
  # (test/gaps/a_string_joined_from_valid_pieces_is_valid_without_a_scan.rb).
  next if enc.dummy? || %w[Big5-HKSCS Big5-UAO CP951].include?(enc.name)
  name = enc.name
  sample = +""
  POINTS.each do |cp|
    sample << cp.chr(Encoding::UTF_8).encode(enc)
  rescue EncodingError, RangeError
  end
  sample = sample.force_encoding(enc)
  next if sample.empty?
  puts "== #{name} #{sample.bytesize}"
  t("valid") { sample.valid_encoding? }
  t("chars") { sample.chars.map(&:bytes) }
  t("inspect") { sample.inspect }
  t("dump") { sample.dump }
  t("up") { sample.upcase.bytes }
  t("down") { sample.downcase.bytes }
  t("swap") { sample.swapcase.bytes }
  t("cap") { sample.capitalize.bytes }
  t("ord") { sample.chars.map(&:ord) rescue $!.class }
  t("reverse") { sample.reverse.bytes }
  t("index") { sample.index(sample[-1]) }
  t("succ") { sample.succ.bytes }
  t("broken") { (sample.b + "\xFF\xFE\x80".b).force_encoding(enc).then { |s| [s.valid_encoding?, s.scrub.bytes, s.chars.size] } }
  t("to utf8") { sample.encode(Encoding::UTF_8) }
  t("path") { Encoding::Converter.search_convpath(enc, Encoding::UTF_8) rescue $!.class }
  t("from utf8") { sample.encode(Encoding::UTF_8).encode(enc).bytes == sample.bytes }
  t("to 16le") { sample.encode(Encoding::UTF_16LE).bytes.size }
  t("undef") { "\u{10FFFF}x".encode(enc, undef: :replace).bytes }
  t("xml") { "<&>\u{1F600}".encode(enc, xml: :text, undef: :replace).bytes rescue $!.class }
  t("unpack") { sample.unpack("U*") rescue $!.class }
  t("center") { sample.center(sample.size + 4, "*".encode(enc)).bytes rescue $!.class }
  t("tr") { sample.tr("A".encode(enc), "B".encode(enc)).bytes rescue $!.class }
  t("split") { sample.split("").size }
  t("each_grapheme") { sample.grapheme_clusters.size }
  t("casecmp") { sample.casecmp?(sample.upcase) }
end
