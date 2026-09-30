# A String keeps the encoding ruby gives it: a partial read, and any
# read in binary mode, is binary; +s and -s keep it; a codepoint appends
# by the String's encoding; reverse walks characters, an invalid byte
# one of them.
def t = yield rescue [$!.class, $!.message]

path = "strings_keep_their_encodings.tmp"
File.binwrite(path, "\xff\xfeab\nc".b)
p t { File.open(path) { |f| f.read(1).encoding } }, t { File.open(path) { |f| f.read.encoding } }, t { File.open(path, "rb") { |f| f.read.encoding } }
p t { File.open(path, "rb") { |f| f.binmode? } }, t { File.open(path) { |f| f.binmode? } }, t { File.open(path) { |f| f.binmode; [f.binmode?, f.read.encoding] } }
p t { File.open(path, "r:UTF-8") { |f| f.read(2).encoding } }, t { File.open(path) { |f| f.read(0).encoding } }
p t { File.open(path) { |f| f.gets.encoding } }, t { File.open(path, "rb") { |f| f.gets.encoding } }
File.delete(path)

p t { (+"\xff".b.freeze).encoding }, t { (-"\xff".b).encoding }
p t { (+"").force_encoding("US-ASCII") << 200 }, t { ((+"").force_encoding("US-ASCII") << 200).encoding }, t { +"" << 0xD800 }, t { (+"") << 0x1F600 }
p t { "a\x80".reverse }, t { "aé".reverse }, t { "\xE3\x81a".reverse }

