# rb_str_inspect writes its text in default_internal, else in
# default_external. A character prints as itself only when its String
# is in that encoding; a Hash prints a Symbol key the same way.
$VERBOSE = nil
[Encoding::US_ASCII, Encoding::UTF_8].each do |encoding|
  Encoding.default_external = encoding
  p [encoding, :"あ".inspect, { "あ": 1 }.inspect, "あ".inspect, :"aあb".inspect]
end

p({ "あ=": 1, "@あ": 2, "あ!": 3, "aあ": 4 }.inspect)
p [:"あ=".inspect, :"@あ".inspect]

sjis = "\x87]".force_encoding("Windows-31J")
[Encoding::Windows_31J, Encoding::UTF_8].each do |encoding|
  Encoding.default_external = encoding
  p [encoding, sjis.inspect.bytes, sjis.inspect.encoding]
  p [sjis.to_sym.inspect.bytes, { sjis.to_sym => 1 }.inspect.bytes]
end
Encoding.default_external = Encoding::Shift_JIS
p "\x82\xA0x".force_encoding("Shift_JIS").inspect.bytes
