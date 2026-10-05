# An Encoding is shareable: it crosses into a Ractor by reference.
p Encoding::UTF_8.frozen?, Ractor.shareable?(Encoding::UTF_8), Ractor.shareable?([Encoding::EUC_JP].freeze)
encodings = Encoding.list.first(5).freeze
r = Ractor.new(encodings) { |list| list.map { |enc| "abc".dup.force_encoding(enc).encoding.equal?(enc) } }
p r.value
