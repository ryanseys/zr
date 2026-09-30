s = 181.chr + "\n"
p s.encoding
p s.bytes
a = "x".encode("US-ASCII")
p (a + "y").encoding
p ("y" + a).encoding
p ("abc" + 200.chr).encoding
