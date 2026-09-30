# A mode string names its encodings as parse_mode_enc reads them, split
# at the last colon: a name that matches nothing warns and is ignored,
# and nothing converts from binary. set_encoding reads a spec string
# the same way, and raises for a name given on its own.
path = "/tmp/zr_spec_mode_enc.txt"
File.write(path, "x")
File.open(path, "r:utf-8:") { |f| p [f.external_encoding, f.internal_encoding] }
File.open(path, "r:-") { |f| p f.external_encoding }
File.open(path, "r::utf-8") { |f| p [f.external_encoding, f.internal_encoding] }
File.open(path, "r:binary:utf-8") { |f| p f.internal_encoding }
File.open(path) do |f|
  f.set_encoding("bogus")
  p f.external_encoding
  f.set_encoding("utf-8:bogus")
  p f.internal_encoding
  f.set_encoding("bom|utf-8")
  p f.external_encoding
  f.set_encoding("binary:utf-8")
  p f.internal_encoding
  p((f.set_encoding("utf-16le") rescue $!))
  p((f.set_encoding rescue $!))
  p((f.set_encoding(nil, "utf-8") rescue $!))
  p((f.set_encoding(1, 2, 3) rescue $!))
  p((f.set_encoding("bogus", "utf-8") rescue $!))
end
File.delete(path)
