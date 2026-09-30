# `fallback:` answers for each character the target has no room for:
# a Hash, a Proc, a Method or anything that answers `[]`, given the
# character in the encoding of the step that stopped.
p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"})
p "\u{1F600}".encode("EUC-JP", fallback: ->(c){ "y" })
p "\u{1F600}a".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}.method(:[]))
p "\u{1F600}".encode("ISO-8859-1", fallback: Hash.new { |h, k| k.bytesize.to_s })
begin; "\u{1F600}".encode("EUC-JP", fallback: {}); rescue => e; p e; end
begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"\u{1F601}"}); rescue => e; p e; end
begin; "\xFF".encode("EUC-JP", "UTF-8", fallback: {"\xFF"=>"x"}); rescue => e; p e; end
begin; "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>1}); rescue => e; p e; end
p "\u{1F600}".encode("EUC-JP", fallback: 5) rescue p $!
p "\u{1F600}".encode("EUC-JP", fallback: {"\u{1F600}"=>"x"}, undef: :replace)
p "\xA4".b.force_encoding("ISO-8859-1").encode("US-ASCII", fallback: ->(c) { p [c, c.encoding]; "E" })
p "é".encode("US-ASCII", fallback: ->(c) { "é" }) rescue p $!
p "aア日".encode("Shift_JIS", "UTF-8").encode("ISO-8859-1", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
p "\u{1F600}".encode("UTF-16LE", "UTF-8").encode("EUC-JP", fallback: ->(c) { p [c.encoding, c.bytes]; "?" })
p "\x81".b.encode("UTF-8", fallback: ->(c) { p [c.encoding, c.bytes]; "B" })

