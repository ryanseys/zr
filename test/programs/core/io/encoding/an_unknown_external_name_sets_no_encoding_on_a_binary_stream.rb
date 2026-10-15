# IO#set_encoding with an external name that names no encoding warns and
# sets none, so a read gives the default external encoding (or the
# internal one given beside it), also on a stream opened "rb" or put in
# binmode before.
require "tmpdir"

path = File.join(Dir.tmpdir, "zr_set_encoding_unknown_#{Process.pid}.txt")
File.binwrite(path, "h\xC3\xA9llo\n")

def read_after(path, mode)
  File.open(path, mode) do |f|
    yield f
    text = f.read
    [f.external_encoding, f.internal_encoding, text.encoding, f.binmode?]
  end
end

p read_after(path, "rb") { |f| f.set_encoding("bogus") }
p read_after(path, "rb") { |f| f.set_encoding("bogus", nil) }
p read_after(path, "rb") { |f| f.set_encoding("bogus", "UTF-8") }
p read_after(path, "rb") { |f| f.set_encoding("bogus:bogus") }
p read_after(path, "rb") { |f| f.set_encoding("bogus:UTF-8") }
p read_after(path, "r") { |f| f.set_encoding("bogus", "ASCII-8BIT") }
p read_after(path, "r") { |f| f.binmode; f.set_encoding("bogus") }
p read_after(path, "r") { |f| f.set_encoding("ASCII-8BIT"); f.set_encoding("bogus") }
p read_after(path, "rb") { |f| f.set_encoding("bogus"); f.set_encoding("ASCII-8BIT") }
p read_after(path, "rb") { |f| f.set_encoding(nil) }
p read_after(path, "rb") { |f| f.set_encoding("UTF-8") }
p read_after(path, "rb") { |f| f.set_encoding(Encoding::UTF_8) }
File.open(path, "rb") do |f|
  f.set_encoding("bogus")
  p f.read(3).encoding, f.getc.encoding
end
File.delete(path)
