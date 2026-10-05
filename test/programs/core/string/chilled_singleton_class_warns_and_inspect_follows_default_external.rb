# A chilled String warns when it gets a singleton class, as when it
# changes.
Warning[:deprecated] = true
"chilled".singleton_class
:chilled.to_s.singleton_class
s = "once"
s.singleton_class
s.singleton_class
$stderr.flush

# inspect gives US-ASCII text, all non-ASCII escaped, when the default
# encodings are not ASCII-compatible.
p "é".inspect.encoding, :a.inspect.encoding
Encoding.default_external = Encoding.find("UTF-32")
p "jp".encode("EUC-JP").inspect.encoding, "utf8".inspect.encoding, "é".inspect, "é".inspect.encoding
p ["utf8"].inspect.encoding, ["jp".encode("EUC-JP"), "utf8"].inspect.encoding, [1, "a"].to_s.encoding
p({ a: "x" }.inspect.encoding, :é.inspect)
Encoding.default_external = Encoding::UTF_8
p "é".inspect, "é".inspect.encoding
